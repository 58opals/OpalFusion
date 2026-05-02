// OpalFusion+Execution+RoundEngine.swift

extension OpalFusion.Execution {
    struct RoundEngine: Sendable {
        enum Input: Sendable, Equatable {
            case configurationRejected(summary: String)
            case primaryConnected
            case primaryDisconnected
            case primaryTransportFailed(summary: String)
            case covertTransportFailed(summary: String)
            case protocolRejected(summary: String)
            case primaryMessage(OpalFusion.ProtocolModel.ServerMessage)
            case covertResponse(OpalFusion.ProtocolModel.CovertResponse)
            case participantReservationLoaded(OpalFusion.Host.ParticipantReservation)
            case participantReservationRejected
            case finalizedTransactionLoaded(OpalFusion.Host.FinalizedTransaction)
            case transactionFinalizationRejected
            case clockAdvanced
        }

        enum Effect: Sendable, Equatable {
            case sendPrimary(OpalFusion.ProtocolModel.ClientMessage)
            case prepareCovert(OpalFusion.Runtime.CovertEndpointContext)
            case submitCovert(OpalFusion.ProtocolModel.CovertMessage)
            case requestParticipantReservation(roundIdentifier: OpalFusion.Round.Identifier)
            case requestTransactionFinalization(
                roundIdentifier: OpalFusion.Round.Identifier,
                proposal: OpalFusion.Host.TransactionFinalizationProposal
            )
            case emitHostEvent(
                roundIdentifier: OpalFusion.Round.Identifier?,
                event: OpalFusion.Host.Event
            )
        }

        private(set) var session: OpalFusion.Execution.SessionContext
        private(set) var round: OpalFusion.Execution.RoundContext?
        let workflow: OpalFusion.Execution.WorkflowContext

        init(
            configuration: OpalFusion.Client.Configuration,
            genesisHash: [UInt8]? = nil,
            joinPools: OpalFusion.ProtocolModel.JoinPools,
            workflow: OpalFusion.Execution.WorkflowContext,
            baseline: OpalFusion.Transport.BaselineConfiguration = .electronCash443
        ) {
            self.session = .init(
                configuration: configuration,
                baseline: baseline,
                genesisHash: genesisHash,
                joinPools: joinPools
            )
            self.round = nil
            self.workflow = workflow
        }

        var clientState: OpalFusion.Client.State {
            .init(
                isConnected: session.isConnected,
                round: projectedRoundState
            )
        }

        mutating func apply(
            input: OpalFusion.Execution.RoundEngine.Input,
            now: OpalFusion.Execution.Instant
        ) -> [OpalFusion.Execution.RoundEngine.Effect] {
            switch input {
            case let .configurationRejected(summary):
                session.isConnected = false
                return failBeforeRound(
                    error: .invalidConfiguration,
                    summary: summary
                )
            case .primaryConnected:
                return handlePrimaryConnected()
            case .primaryDisconnected:
                return handlePrimaryDisconnected()
            case let .primaryTransportFailed(summary):
                if session.connectionSubstate == .failed {
                    session.isConnected = false
                    return []
                }
                session.isConnected = false
                if round?.substate == .terminal {
                    session.connectionSubstate = .disconnected
                    return []
                }
                if round?.identifier != nil {
                    return failRound(
                        completionStatus: .transportFailed,
                        clientError: .transportUnavailable,
                        summary: summary
                    )
                }
                return failBeforeRound(
                    error: .transportUnavailable,
                    summary: summary
                )
            case let .covertTransportFailed(summary):
                if round?.substate == .terminal {
                    return []
                }
                if round?.identifier != nil {
                    return failRound(
                        completionStatus: .transportFailed,
                        clientError: .transportUnavailable,
                        summary: summary
                    )
                }
                return failBeforeRound(
                    error: .transportUnavailable,
                    summary: summary
                )
            case let .protocolRejected(summary):
                if round?.substate == .terminal {
                    return []
                }
                if round?.identifier != nil {
                    return failRound(
                        completionStatus: .protocolIncompatible,
                        clientError: .protocolIncompatible,
                        summary: summary
                    )
                }
                return failBeforeRound(
                    error: .protocolIncompatible,
                    summary: summary
                )
            case let .primaryMessage(message):
                return handlePrimaryMessage(message, now: now)
            case let .covertResponse(response):
                return handleCovertResponse(response)
            case let .participantReservationLoaded(reservation):
                return handleParticipantReservationLoaded(reservation)
            case .participantReservationRejected:
                if round?.substate == .terminal {
                    return []
                }
                return failRound(
                    completionStatus: .hostRejected,
                    clientError: .hostRejected,
                    summary: "Host rejected participant reservation"
                )
            case let .finalizedTransactionLoaded(transaction):
                return handleFinalizedTransactionLoaded(transaction, now: now)
            case .transactionFinalizationRejected:
                if round?.substate == .terminal {
                    return []
                }
                return failRound(
                    completionStatus: .hostRejected,
                    clientError: .hostRejected,
                    summary: "Host rejected transaction finalization"
                )
            case .clockAdvanced:
                return handleClockAdvanced(now: now)
            }
        }

        private var projectedRoundState: OpalFusion.Round.State? {
            guard let round, let identifier = round.identifier else {
                return nil
            }

            let phase: OpalFusion.Round.Phase
            switch round.substate {
            case .warmup:
                phase = .connecting
            case .collectingInputs:
                phase = .registeringInputs
            case .awaitingBlindSignatures:
                phase = .awaitingBlindSignatures
            case .awaitingAllCommitments, .awaitingCovertComponentWindow, .submittingCovertComponents:
                phase = .awaitingCommitments
            case .awaitingSharedComponents, .awaitingHostFinalization, .awaitingSignatureWindow,
                    .submittingSignatures, .awaitingResult:
                phase = .assemblingTransaction
            case .awaitingTheirProofs, .submittingBlames, .awaitingRestart:
                phase = .blame
            case .terminal:
                phase = .completed
            }

            let completionStatus = round.completionStatus

            if let completionStatus {
                return .init(
                    identifier: identifier,
                    participantCount: nil,
                    completionStatus: completionStatus
                )
            }

            return .init(
                identifier: identifier,
                phase: phase,
                participantCount: nil
            )
        }

        private mutating func handlePrimaryConnected() -> [OpalFusion.Execution.RoundEngine.Effect] {
            guard session.connectionSubstate == .disconnected else {
                return []
            }

            session.isConnected = true
            session.connectionSubstate = .awaitingServerHello
            session.lastError = nil
            session.lastErrorSummary = nil

            let hello = OpalFusion.ProtocolModel.ClientHello(
                versionBytes: session.baseline.protocolIdentity.versionBytes,
                genesisHash: session.genesisHash
            )

            return [
                .sendPrimary(.clientHello(hello)),
                hostEvent(
                    roundIdentifier: nil,
                    kind: .status,
                    phase: .connecting,
                    summary: "Primary channel connected; sending ClientHello"
                )
            ]
        }

        private mutating func handlePrimaryDisconnected() -> [OpalFusion.Execution.RoundEngine.Effect] {
            session.isConnected = false

            if session.connectionSubstate == .failed {
                return []
            }

            if round?.substate == .terminal {
                session.connectionSubstate = .disconnected
                return []
            }

            if round?.identifier != nil {
                return failRound(
                    completionStatus: .transportFailed,
                    clientError: .transportUnavailable,
                    summary: "Primary channel disconnected"
                )
            }

            round = nil
            session.connectionSubstate = .disconnected
            session.lastError = .transportUnavailable
            session.lastErrorSummary = "Primary channel disconnected"
            return [
                hostEvent(
                    roundIdentifier: nil,
                    kind: .failure,
                    phase: .connecting,
                    summary: "Primary channel disconnected"
                )
            ]
        }

        private mutating func handlePrimaryMessage(
            _ message: OpalFusion.ProtocolModel.ServerMessage,
            now: OpalFusion.Execution.Instant
        ) -> [OpalFusion.Execution.RoundEngine.Effect] {
            if round?.substate == .terminal {
                return []
            }

            if case let .serverFailure(failure) = message {
                return failForServerFailure(failure)
            }

            if round == nil {
                switch session.connectionSubstate {
                case .awaitingServerHello:
                    guard case let .serverHello(serverHello) = message else {
                        return failBeforeRound(
                            error: .protocolIncompatible,
                            summary: "Unexpected message before ServerHello"
                        )
                    }

                    session.latestServerHello = serverHello
                    session.connectionSubstate = .awaitingFusionBegin

                    return [
                        .sendPrimary(.joinPools(session.joinPools)),
                        hostEvent(
                            roundIdentifier: nil,
                            kind: .status,
                            phase: .connecting,
                            summary: "ServerHello received; joining eligible pools"
                        )
                    ]
                case .awaitingFusionBegin:
                    switch message {
                    case let .tierStatusUpdate(update):
                        session.latestTierStatus = update
                        return []
                    case let .fusionBegin(fusionBegin):
                        guard let serverHello = session.latestServerHello else {
                            return failBeforeRound(
                                error: .protocolIncompatible,
                                summary: "FusionBegin arrived before a valid ServerHello was recorded"
                            )
                        }
                        guard session.joinPools.tiers.contains(fusionBegin.tier) else {
                            return failBeforeRound(
                                error: .protocolIncompatible,
                                summary: "FusionBegin tier was not requested"
                            )
                        }
                        guard isServerTimeAcceptable(fusionBegin.serverTimeUnixSeconds, now: now) else {
                            return failBeforeRound(
                                error: .protocolIncompatible,
                                summary: "FusionBegin server time exceeded the allowed clock skew"
                            )
                        }

                        round = .init(
                            fusionBegin: fusionBegin,
                            serverHello: serverHello,
                            deadlines: .fromFusionBegin(
                                fusionBegin,
                                timing: session.baseline.roundTiming
                            )
                        )
                        session.connectionSubstate = .inRound

                        return [
                            .prepareCovert(makeCovertEndpointContext(from: fusionBegin)),
                            hostEvent(
                                roundIdentifier: nil,
                                kind: .status,
                                phase: .connecting,
                                summary: "Fusion warmup started"
                            )
                        ]
                    default:
                        return failBeforeRound(
                            error: .protocolIncompatible,
                            summary: "Unexpected message before FusionBegin"
                        )
                    }
                case .disconnected, .inRound, .failed:
                    return []
                }
            }

            guard var round else {
                return []
            }

            switch message {
            case let .startRound(startRound):
                guard round.substate == .warmup else {
                    return failRound(
                        completionStatus: .protocolIncompatible,
                        clientError: .protocolIncompatible,
                        summary: "StartRound arrived out of order"
                    )
                }
                guard isServerTimeAcceptable(startRound.serverTimeUnixSeconds, now: now) else {
                    return failRound(
                        completionStatus: .protocolIncompatible,
                        clientError: .protocolIncompatible,
                        summary: "StartRound server time exceeded the allowed clock skew"
                    )
                }

                round.startRound = startRound
                round.identifier = makeRoundIdentifier(from: startRound.roundPublicKey)
                round.deadlines = round.deadlines.withStartRound(
                    startRound,
                    timing: session.baseline.roundTiming
                )
                round.substate = .collectingInputs
                self.round = round

                return [
                    .requestParticipantReservation(roundIdentifier: round.identifier!),
                    hostEvent(
                        roundIdentifier: round.identifier,
                        kind: .status,
                        phase: .registeringInputs,
                        summary: "StartRound received; collecting reserved inputs and outputs"
                    )
                ]
            case let .blindSignatureResponses(responses):
                guard round.substate == .awaitingBlindSignatures else {
                    return failRound(
                        completionStatus: .protocolIncompatible,
                        clientError: .protocolIncompatible,
                        summary: "Blind signature responses arrived out of order"
                    )
                }

                round.blindSignatureResponses = responses
                round.substate = .awaitingAllCommitments
                self.round = round

                return [
                    hostEvent(
                        roundIdentifier: round.identifier,
                        kind: .status,
                        phase: .awaitingCommitments,
                        summary: "Blind signature responses received"
                    )
                ]
            case let .allCommitments(allCommitments):
                guard round.substate == .awaitingAllCommitments else {
                    return failRound(
                        completionStatus: .protocolIncompatible,
                        clientError: .protocolIncompatible,
                        summary: "AllCommitments arrived out of order"
                    )
                }

                round.allCommitments = allCommitments
                round.substate = .awaitingCovertComponentWindow
                self.round = round

                var effects = [
                    hostEvent(
                        roundIdentifier: round.identifier,
                        kind: .status,
                        phase: .awaitingCommitments,
                        summary: "All commitments received; waiting for covert submit window"
                    )
                ]
                effects.append(contentsOf: maybeOpenCovertSubmission(now: now))
                return effects
            case let .shareCovertComponents(sharedComponents):
                guard round.substate == .submittingCovertComponents ||
                        round.substate == .awaitingSharedComponents ||
                        round.substate == .awaitingCovertComponentWindow else {
                    return failRound(
                        completionStatus: .protocolIncompatible,
                        clientError: .protocolIncompatible,
                        summary: "Shared components arrived out of order"
                    )
                }

                round.sharedComponents = sharedComponents

                if sharedComponents.skipSignatures == true {
                    round.substate = .awaitingResult
                    self.round = round
                    return [
                        hostEvent(
                            roundIdentifier: round.identifier,
                            kind: .warning,
                            phase: .assemblingTransaction,
                            summary: "Coordinator skipped signatures; awaiting result"
                        )
                    ]
                }

                let proposal: OpalFusion.Host.TransactionFinalizationProposal
                do {
                    proposal = try workflow.buildTransactionFinalizationProposal(&round)
                } catch {
                    return failForWorkflowFailure(error)
                }
                round.substate = .awaitingHostFinalization
                self.round = round

                return [
                    .requestTransactionFinalization(
                        roundIdentifier: round.identifier!,
                        proposal: proposal
                    ),
                    hostEvent(
                        roundIdentifier: round.identifier,
                        kind: .status,
                        phase: .assemblingTransaction,
                        summary: "Shared components received; requesting transaction finalization"
                    )
                ]
            case let .fusionResult(result):
                guard round.substate == .submittingSignatures ||
                        round.substate == .awaitingResult ||
                        round.sharedComponents?.skipSignatures == true else {
                    return failRound(
                        completionStatus: .protocolIncompatible,
                        clientError: .protocolIncompatible,
                        summary: "FusionResult arrived out of order"
                    )
                }

                round.fusionResult = result
                if result.isSuccess {
                    round.substate = .terminal
                    round.completionStatus = .success
                    self.round = round
                    return [
                        hostEvent(
                            roundIdentifier: round.identifier,
                            kind: .completed,
                            phase: .completed,
                            summary: "Round completed successfully",
                            isTerminal: true
                        )
                    ]
                }

                let myProofsList: OpalFusion.ProtocolModel.MyProofsList
                do {
                    myProofsList = try workflow.buildMyProofsList(&round)
                } catch {
                    return failForWorkflowFailure(error)
                }
                round.myProofsList = myProofsList
                round.substate = .awaitingTheirProofs
                self.round = round

                return [
                    .sendPrimary(.myProofsList(myProofsList)),
                    hostEvent(
                        roundIdentifier: round.identifier,
                        kind: .warning,
                        phase: .blame,
                        summary: "Round result requires blame handling"
                    )
                ]
            case let .theirProofsList(theirProofsList):
                guard round.substate == .awaitingTheirProofs else {
                    return failRound(
                        completionStatus: .protocolIncompatible,
                        clientError: .protocolIncompatible,
                        summary: "TheirProofsList arrived out of order"
                    )
                }

                round.theirProofsList = theirProofsList
                let blames: OpalFusion.ProtocolModel.Blames
                do {
                    blames = try workflow.buildBlames(&round)
                } catch {
                    return failForWorkflowFailure(error)
                }
                round.blames = blames
                round.substate = .submittingBlames
                self.round = round

                round.substate = .awaitingRestart
                self.round = round

                return [
                    .sendPrimary(.blames(blames)),
                    hostEvent(
                        roundIdentifier: round.identifier,
                        kind: .warning,
                        phase: .blame,
                        summary: "Submitting blame proofs and awaiting restart"
                    )
                ]
            case .restartRound:
                guard round.substate == .awaitingRestart else {
                    return failRound(
                        completionStatus: .protocolIncompatible,
                        clientError: .protocolIncompatible,
                        summary: "RestartRound arrived out of order"
                    )
                }

                let priorIdentifier = round.identifier
                self.round = nil
                session.restartCount += 1
                session.connectionSubstate = .awaitingFusionBegin

                return [
                    hostEvent(
                        roundIdentifier: priorIdentifier,
                        kind: .status,
                        phase: .connecting,
                        summary: "Restarting round after blame handling"
                    )
                ]
            case .serverHello, .tierStatusUpdate, .fusionBegin:
                return failRound(
                    completionStatus: .protocolIncompatible,
                    clientError: .protocolIncompatible,
                    summary: "Received an unexpected coordinator message mid-round"
                )
            case .serverFailure:
                return []
            }
        }

        private mutating func handleCovertResponse(
            _ response: OpalFusion.ProtocolModel.CovertResponse
        ) -> [OpalFusion.Execution.RoundEngine.Effect] {
            if round?.substate == .terminal {
                return []
            }

            switch response {
            case .acknowledgement:
                guard var round else {
                    return []
                }

                switch round.substate {
                case .submittingCovertComponents:
                    round.substate = .awaitingSharedComponents
                    self.round = round
                case .submittingSignatures:
                    round.substate = .awaitingResult
                    self.round = round
                default:
                    break
                }

                return []
            case let .serverFailure(failure):
                return failForServerFailure(failure)
            }
        }

        private mutating func handleParticipantReservationLoaded(
            _ reservation: OpalFusion.Host.ParticipantReservation
        ) -> [OpalFusion.Execution.RoundEngine.Effect] {
            if round?.substate == .terminal {
                return []
            }

            guard var round, round.substate == .collectingInputs else {
                return failRound(
                    completionStatus: .protocolIncompatible,
                    clientError: .protocolIncompatible,
                    summary: "Participant reservation arrived out of order"
                )
            }

            round.participantReservation = reservation
            let commit: OpalFusion.ProtocolModel.PlayerCommit
            do {
                commit = try workflow.buildPlayerCommit(&round)
            } catch {
                return failForWorkflowFailure(error)
            }
            round.playerCommit = commit
            round.substate = .awaitingBlindSignatures
            self.round = round

            return [
                .sendPrimary(.playerCommit(commit)),
                hostEvent(
                    roundIdentifier: round.identifier,
                    kind: .status,
                    phase: .awaitingBlindSignatures,
                    summary: "Submitting player commitments and blind requests"
                )
            ]
        }

        private mutating func handleFinalizedTransactionLoaded(
            _ transaction: OpalFusion.Host.FinalizedTransaction,
            now: OpalFusion.Execution.Instant
        ) -> [OpalFusion.Execution.RoundEngine.Effect] {
            if round?.substate == .terminal {
                return []
            }

            guard var round, round.substate == .awaitingHostFinalization else {
                return failRound(
                    completionStatus: .protocolIncompatible,
                    clientError: .protocolIncompatible,
                    summary: "Finalized transaction arrived out of order"
                )
            }

            round.finalizedTransaction = transaction
            do {
                _ = try workflow.buildCovertSignatureMessages(&round)
            } catch {
                return failForWorkflowFailure(error)
            }
            round.substate = .awaitingSignatureWindow
            self.round = round

            var effects = [
                hostEvent(
                    roundIdentifier: round.identifier,
                    kind: .status,
                    phase: .assemblingTransaction,
                    summary: "Transaction finalized; waiting for signature window"
                )
            ]
            effects.append(contentsOf: maybeOpenSignatureSubmission(now: now))
            return effects
        }

        private mutating func handleClockAdvanced(
            now: OpalFusion.Execution.Instant
        ) -> [OpalFusion.Execution.RoundEngine.Effect] {
            if let timeoutEffects = timeoutEffectsIfNeeded(now: now), timeoutEffects.isEmpty == false {
                return timeoutEffects
            }

            var effects = maybeOpenCovertSubmission(now: now)
            effects.append(contentsOf: maybeOpenSignatureSubmission(now: now))
            return effects
        }

        private mutating func maybeOpenCovertSubmission(
            now: OpalFusion.Execution.Instant
        ) -> [OpalFusion.Execution.RoundEngine.Effect] {
            guard var round,
                  round.substate == .awaitingCovertComponentWindow,
                  let covertComponentsStart = round.deadlines.covertComponentsStart,
                  let covertComponentsDeadline = round.deadlines.covertComponentsDeadline,
                  now >= covertComponentsStart else {
                return []
            }

            guard now <= covertComponentsDeadline else {
                return failRound(
                    completionStatus: .transportFailed,
                    clientError: .transportUnavailable,
                    summary: "Covert component deadline elapsed before submission"
                )
            }

            let messages: [OpalFusion.ProtocolModel.CovertMessage]
            do {
                messages = try workflow.buildCovertComponentMessages(&round)
            } catch {
                return failForWorkflowFailure(error)
            }
            round.substate = .submittingCovertComponents
            self.round = round

            var effects = messages.map(OpalFusion.Execution.RoundEngine.Effect.submitCovert)
            effects.append(
                hostEvent(
                    roundIdentifier: round.identifier,
                    kind: .status,
                    phase: .awaitingCommitments,
                    summary: "Submitting covert components"
                )
            )
            return effects
        }

        private mutating func maybeOpenSignatureSubmission(
            now: OpalFusion.Execution.Instant
        ) -> [OpalFusion.Execution.RoundEngine.Effect] {
            guard var round,
                  round.substate == .awaitingSignatureWindow,
                  let signaturesStart = round.deadlines.signaturesStart,
                  let signaturesDeadline = round.deadlines.signaturesDeadline,
                  now >= signaturesStart else {
                return []
            }

            guard now <= signaturesDeadline else {
                return failRound(
                    completionStatus: .transportFailed,
                    clientError: .transportUnavailable,
                    summary: "Signature deadline elapsed before submission"
                )
            }

            let messages: [OpalFusion.ProtocolModel.CovertMessage]
            do {
                messages = try workflow.buildCovertSignatureMessages(&round)
            } catch {
                return failForWorkflowFailure(error)
            }
            round.substate = .submittingSignatures
            self.round = round

            var effects = messages.map(OpalFusion.Execution.RoundEngine.Effect.submitCovert)
            effects.append(
                hostEvent(
                    roundIdentifier: round.identifier,
                    kind: .status,
                    phase: .assemblingTransaction,
                    summary: "Submitting covert transaction signatures"
                )
            )
            return effects
        }

        private mutating func timeoutEffectsIfNeeded(
            now: OpalFusion.Execution.Instant
        ) -> [OpalFusion.Execution.RoundEngine.Effect]? {
            guard let round else {
                return nil
            }

            switch round.substate {
            case .warmup:
                if now > round.deadlines.warmupDeadline {
                    return failRound(
                        completionStatus: .transportFailed,
                        clientError: .transportUnavailable,
                        summary: "Warmup expired before StartRound arrived"
                    )
                }
            case .collectingInputs, .awaitingBlindSignatures, .awaitingAllCommitments, .awaitingCovertComponentWindow:
                if let covertComponentsDeadline = round.deadlines.covertComponentsDeadline,
                   now > covertComponentsDeadline {
                    return failRound(
                        completionStatus: .transportFailed,
                        clientError: .transportUnavailable,
                        summary: "Round expired before covert component submission completed"
                    )
                }
            case .submittingCovertComponents, .awaitingSharedComponents, .awaitingHostFinalization,
                    .awaitingSignatureWindow, .submittingSignatures, .awaitingResult:
                if let conclusionTimeout = round.deadlines.conclusionTimeout,
                   now > conclusionTimeout {
                    return failRound(
                        completionStatus: .transportFailed,
                        clientError: .transportUnavailable,
                        summary: "Round conclusion timeout elapsed"
                    )
                }
            case .awaitingTheirProofs, .submittingBlames, .awaitingRestart:
                if let blameVerifyDeadline = round.deadlines.blameVerifyDeadline,
                   now > blameVerifyDeadline {
                    return failRound(
                        completionStatus: .transportFailed,
                        clientError: .transportUnavailable,
                        summary: "Blame handling exceeded the allowed deadline"
                    )
                }
            case .terminal:
                return nil
            }

            return nil
        }

        private mutating func failForServerFailure(
            _ failure: OpalFusion.ProtocolModel.ServerFailure
        ) -> [OpalFusion.Execution.RoundEngine.Effect] {
            let summary = failure.message ?? "Coordinator rejected the current flow"

            if round?.identifier != nil {
                return failRound(
                    completionStatus: .coordinatorRejected,
                    clientError: .coordinatorRejected,
                    summary: summary
                )
            }

            return failBeforeRound(
                error: .coordinatorRejected,
                summary: summary
            )
        }

        private mutating func failForWorkflowFailure(
            _ error: Swift.Error
        ) -> [OpalFusion.Execution.RoundEngine.Effect] {
            if let workflowFailure = error as? OpalFusion.Execution.WorkflowFailure {
                return failRound(
                    completionStatus: workflowFailure.completionStatus,
                    clientError: workflowFailure.clientError,
                    summary: workflowFailure.summary
                )
            }

            return failRound(
                completionStatus: .hostRejected,
                clientError: .notImplemented,
                summary: "Execution materialization failed: \(String(describing: error))"
            )
        }

        private mutating func failBeforeRound(
            error: OpalFusion.Client.Error,
            summary: String
        ) -> [OpalFusion.Execution.RoundEngine.Effect] {
            round = nil
            session.lastError = error
            session.lastErrorSummary = summary
            session.connectionSubstate = .failed
            return [
                hostEvent(
                    roundIdentifier: nil,
                    kind: .failure,
                    phase: .connecting,
                    summary: summary
                )
            ]
        }

        private mutating func failRound(
            completionStatus: OpalFusion.Round.CompletionStatus,
            clientError: OpalFusion.Client.Error,
            summary: String
        ) -> [OpalFusion.Execution.RoundEngine.Effect] {
            guard var round else {
                return failBeforeRound(
                    error: clientError,
                    summary: summary
                )
            }

            round.substate = .terminal
            round.completionStatus = completionStatus
            self.round = round
            session.lastError = clientError
            session.lastErrorSummary = summary
            session.connectionSubstate = .failed

            return [
                hostEvent(
                    roundIdentifier: round.identifier,
                    kind: .failure,
                    phase: .completed,
                    summary: summary,
                    isTerminal: true
                )
            ]
        }

        private func hostEvent(
            roundIdentifier: OpalFusion.Round.Identifier?,
            kind: OpalFusion.Host.Event.Kind,
            phase: OpalFusion.Round.Phase,
            summary: String,
            isTerminal: Bool = false
        ) -> OpalFusion.Execution.RoundEngine.Effect {
            .emitHostEvent(
                roundIdentifier: roundIdentifier,
                event: .init(
                    kind: kind,
                    phase: phase,
                    summary: summary,
                    isTerminal: isTerminal
                )
            )
        }

        private func isServerTimeAcceptable(
            _ serverTimeUnixSeconds: UInt64,
            now: OpalFusion.Execution.Instant
        ) -> Bool {
            let serverTime = OpalFusion.Execution.Instant(unixSeconds: serverTimeUnixSeconds)
            let absoluteDistance = abs(serverTime.distance(to: now).wholeMilliseconds)
            return absoluteDistance <= session.baseline.roundTiming.maximumClockDiscrepancy.wholeMilliseconds
        }

        private func makeRoundIdentifier(
            from roundPublicKey: [UInt8]
        ) -> OpalFusion.Round.Identifier {
            let hexDigits = Array("0123456789abcdef")
            let hex = roundPublicKey.reduce(into: String()) { partialResult, byte in
                partialResult.append(hexDigits[Int(byte >> 4)])
                partialResult.append(hexDigits[Int(byte & 0x0F)])
            }
            return .init(rawValue: hex)
        }

        private func makeCovertEndpointContext(
            from fusionBegin: OpalFusion.ProtocolModel.FusionBegin
        ) -> OpalFusion.Runtime.CovertEndpointContext {
            .init(
                roundIdentifier: nil,
                host: fusionBegin.covertDomain,
                port: fusionBegin.covertPort,
                requiresTLS: fusionBegin.covertSsl,
                entryPath: session.configuration.covertChannel.entryPath,
                maxPayloadBytes: session.configuration.covertChannel.maxPayloadBytes,
                requestTimeoutMilliseconds: session.configuration.covertChannel.requestTimeoutMilliseconds,
                connectTimeout: session.baseline.covertTiming.connectTimeout,
                connectWindow: session.baseline.covertTiming.connectWindow,
                submitTimeout: session.baseline.covertTiming.submitTimeout,
                submitWindow: session.baseline.covertTiming.submitWindow,
                spareConnectionCount: session.baseline.covertTiming.spareConnectionCount
            )
        }
    }
}

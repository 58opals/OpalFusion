// OpalFusion+Execution+RoundEngine.swift

import Foundation

extension OpalFusion.Execution {
    struct RoundEngine: Sendable {
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
            case .stopped:
                return handleStopped()
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
                return failActiveFlow(
                    completionStatus: .transportFailed,
                    clientError: .transportUnavailable,
                    summary: summary
                )
            case let .covertTransportFailed(summary):
                return failActiveFlow(
                    completionStatus: .transportFailed,
                    clientError: .transportUnavailable,
                    summary: summary
                )
            case let .protocolRejected(summary):
                return failActiveFlow(
                    completionStatus: .protocolIncompatible,
                    clientError: .protocolIncompatible,
                    summary: summary
                )
            case let .primaryMessage(message):
                return handlePrimaryMessage(message, now: now)
            case let .covertResponse(response):
                return handleCovertResponse(response)
            case let .participantReservationLoaded(reservation):
                return handleParticipantReservationLoaded(reservation, now: now)
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
            case let .transactionFinalizationRejected(failure):
                if round?.substate == .terminal {
                    return []
                }
                OpalFusionDiagnostics.record(
                    OpalFusion.Diagnostics.Events.transactionFinalizationFailed,
                    category: OpalFusion.Diagnostics.Categories.transaction,
                    traceID: OpalFusionDiagnostics.makeTraceID(for: round?.identifier),
                    fields: [
                        OpalFusionDiagnostics.makeOperationField("transaction_finalization")
                    ] + OpalFusionDiagnostics.makeErrorFields(for: failure)
                )
                return failRound(
                    completionStatus: failure.completionStatus,
                    clientError: failure.clientError,
                    summary: failure.summary
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
                    summary: "Primary channel disconnected",
                    errorCode: OpalFusion.Diagnostics.ErrorCodes.transportUnavailable
                )
            ]
        }

        private mutating func handleStopped() -> [OpalFusion.Execution.RoundEngine.Effect] {
            session.isConnected = false
            session.connectionSubstate = .disconnected
            session.lastError = nil
            session.lastErrorSummary = nil

            if round?.substate != .terminal {
                round = nil
            }

            return []
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
                    guard serverHello.numberOfComponents > 0 else {
                        return failBeforeRound(
                            error: .protocolIncompatible,
                            summary: "ServerHello component count was invalid"
                        )
                    }
                    guard serverHello.minimumExcessFeeSatoshis <= serverHello.maximumExcessFeeSatoshis else {
                        return failBeforeRound(
                            error: .protocolIncompatible,
                            summary: "ServerHello excess fee range was invalid"
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
                        guard serverHello.tiers.contains(fusionBegin.tier) else {
                            return failBeforeRound(
                                error: .protocolIncompatible,
                                summary: "FusionBegin tier was not advertised by ServerHello"
                            )
                        }
                        guard (1 ... UInt32(UInt16.max)).contains(fusionBegin.covertPort) else {
                            return failBeforeRound(
                                error: .protocolIncompatible,
                                summary: "FusionBegin covert port was outside the supported range"
                            )
                        }
                        guard isValidCovertDomain(fusionBegin.covertDomain) else {
                            return failBeforeRound(
                                error: .protocolIncompatible,
                                summary: "FusionBegin covert domain was invalid"
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
                guard startRound.blindNoncePoints.count == Int(round.serverHello.numberOfComponents) else {
                    return failRound(
                        completionStatus: .protocolIncompatible,
                        clientError: .protocolIncompatible,
                        summary: "StartRound blind nonce count did not match ServerHello component count"
                    )
                }
                guard startRound.roundPublicKey.isEmpty == false else {
                    return failRound(
                        completionStatus: .protocolIncompatible,
                        clientError: .protocolIncompatible,
                        summary: "StartRound round public key was missing"
                    )
                }
                guard startRound.blindNoncePoints.allSatisfy({ $0.isEmpty == false }) else {
                    return failRound(
                        completionStatus: .protocolIncompatible,
                        clientError: .protocolIncompatible,
                        summary: "StartRound blind nonce point was missing"
                    )
                }

                let roundIdentifier = makeRoundIdentifier(from: startRound.roundPublicKey)
                let reservationContext = makeParticipantReservationContext(
                    roundIdentifier: roundIdentifier,
                    fusionBegin: round.fusionBegin,
                    serverHello: round.serverHello
                )

                round.startRound = startRound
                round.identifier = roundIdentifier
                round.deadlines = round.deadlines.withStartRound(
                    startRound,
                    timing: session.baseline.roundTiming
                )
                round.substate = .collectingInputs
                self.round = round
                OpalFusionDiagnostics.record(
                    OpalFusion.Diagnostics.Events.roundEntered,
                    category: OpalFusion.Diagnostics.Categories.round,
                    traceID: OpalFusionDiagnostics.makeTraceID(for: roundIdentifier),
                    fields: [
                        OpalFusionDiagnostics.makeOperationField("round_enter"),
                        OpalFusionDiagnostics.phaseField(.registeringInputs),
                        OpalFusionDiagnostics.roundStateField(round.substate),
                        OpalFusionDiagnostics.messageKindField("StartRound")
                    ]
                )

                return [
                    .requestParticipantReservation(context: reservationContext),
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
                guard let playerCommit = round.playerCommit,
                      responses.responses.count == playerCommit.blindSignatureRequests.count else {
                    return failRound(
                        completionStatus: .protocolIncompatible,
                        clientError: .protocolIncompatible,
                        summary: "Blind signature response count did not match PlayerCommit request count"
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
                guard let playerCommit = round.playerCommit,
                      playerCommit.initialCommitments.allSatisfy({
                          allCommitments.initialCommitments.contains($0)
                      }) else {
                    return failRound(
                        completionStatus: .protocolIncompatible,
                        clientError: .protocolIncompatible,
                        summary: "AllCommitments omitted a local commitment"
                    )
                }
                guard Self.hasDuplicateInitialCommitments(allCommitments.initialCommitments) == false else {
                    return failRound(
                        completionStatus: .protocolIncompatible,
                        clientError: .protocolIncompatible,
                        summary: "AllCommitments contained duplicate commitments"
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
                        round.substate == .awaitingSharedComponents else {
                    return failRound(
                        completionStatus: .protocolIncompatible,
                        clientError: .protocolIncompatible,
                        summary: "Shared components arrived out of order"
                    )
                }

                round.sharedComponents = sharedComponents

                if sharedComponents.skipSignatures == true {
                    do {
                        _ = try workflow.buildTransactionFinalizationProposal(&round)
                    } catch {
                        recordTransactionProposalFailure(
                            error,
                            roundIdentifier: round.identifier
                        )
                        return failForWorkflowFailure(error)
                    }
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
                    recordTransactionProposalFailure(
                        error,
                        roundIdentifier: round.identifier
                    )
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
                        round.substate == .awaitingResult else {
                    return failRound(
                        completionStatus: .protocolIncompatible,
                        clientError: .protocolIncompatible,
                        summary: "FusionResult arrived out of order"
                    )
                }

                round.fusionResult = result
                if result.isSuccess {
                    if round.sharedComponents?.skipSignatures == true {
                        self.round = round
                        return failRound(
                            completionStatus: .protocolIncompatible,
                            clientError: .protocolIncompatible,
                            summary: "FusionResult reported success after signatures were skipped"
                        )
                    }

                    round.substate = .terminal
                    round.completionStatus = .success
                    self.round = round
                    OpalFusionDiagnostics.record(
                        OpalFusion.Diagnostics.Events.roundCompleted,
                        category: OpalFusion.Diagnostics.Categories.round,
                        traceID: OpalFusionDiagnostics.makeTraceID(for: round.identifier),
                        fields: [
                            OpalFusionDiagnostics.makeOperationField("round_complete"),
                            OpalFusionDiagnostics.phaseField(.completed),
                            OpalFusionDiagnostics.roundStateField(round.substate),
                            OpalFusionDiagnostics.settlementStateField(.success)
                        ]
                    )
                    return [
                        hostEvent(
                            roundIdentifier: round.identifier,
                            kind: .completed,
                            phase: .completed,
                            summary: "Round completed successfully",
                            isTerminal: true,
                            shouldRecordDiagnostics: false
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
                    OpalFusionDiagnostics.record(
                        OpalFusion.Diagnostics.Events.blameProofValidationFailed,
                        category: OpalFusion.Diagnostics.Categories.blame,
                        traceID: OpalFusionDiagnostics.makeTraceID(for: round.identifier),
                        fields: [
                            OpalFusionDiagnostics.makeOperationField("blame_build"),
                            OpalFusionDiagnostics.phaseField(.blame),
                            OpalFusionDiagnostics.roundStateField(round.substate)
                        ] + OpalFusionDiagnostics.makeErrorFields(for: error)
                    )
                    return failForWorkflowFailure(error)
                }
                round.blames = blames
                round.substate = .submittingBlames
                self.round = round

                round.substate = .awaitingRestart
                self.round = round
                OpalFusionDiagnostics.record(
                    OpalFusion.Diagnostics.Events.blameSubmissionStarted,
                    category: OpalFusion.Diagnostics.Categories.blame,
                    traceID: OpalFusionDiagnostics.makeTraceID(for: round.identifier),
                    fields: [
                        OpalFusionDiagnostics.makeOperationField("blame_submit"),
                        OpalFusionDiagnostics.phaseField(.blame),
                        OpalFusionDiagnostics.roundStateField(round.substate),
                        OpalFusionDiagnostics.messageKindField("Blames")
                    ]
                )

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
                OpalFusionDiagnostics.record(
                    OpalFusion.Diagnostics.Events.roundRestarted,
                    category: OpalFusion.Diagnostics.Categories.round,
                    traceID: OpalFusionDiagnostics.makeTraceID(for: priorIdentifier),
                    fields: [
                        OpalFusionDiagnostics.makeOperationField("round_restart"),
                        OpalFusionDiagnostics.phaseField(.connecting)
                    ]
                )

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
                    return failBeforeRound(
                        error: .protocolIncompatible,
                        summary: "Covert acknowledgement arrived out of order"
                    )
                }

                switch round.substate {
                case .submittingCovertComponents:
                    round.substate = .awaitingSharedComponents
                    self.round = round
                case .submittingSignatures:
                    round.substate = .awaitingResult
                    self.round = round
                default:
                    return failRound(
                        completionStatus: .protocolIncompatible,
                        clientError: .protocolIncompatible,
                        summary: "Covert acknowledgement arrived out of order"
                    )
                }

                return []
            case let .serverFailure(failure):
                return failForServerFailure(failure)
            }
        }

        private mutating func handleParticipantReservationLoaded(
            _ reservation: OpalFusion.Host.ParticipantReservation,
            now: OpalFusion.Execution.Instant
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
            if let commitmentsDeadline = round.deadlines.commitmentsDeadline,
               now > commitmentsDeadline {
                return failRound(
                    completionStatus: .transportFailed,
                    clientError: .transportUnavailable,
                    summary: "Commitment deadline elapsed before PlayerCommit submission"
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

            if let conclusionTimeout = round.deadlines.conclusionTimeout,
               now > conclusionTimeout {
                return failRound(
                    completionStatus: .transportFailed,
                    clientError: .transportUnavailable,
                    summary: "Round conclusion timeout elapsed"
                )
            }

            if let signaturesDeadline = round.deadlines.signaturesDeadline,
               now > signaturesDeadline {
                return failRound(
                    completionStatus: .transportFailed,
                    clientError: .transportUnavailable,
                    summary: "Signature deadline elapsed before submission"
                )
            }

            round.finalizedTransaction = transaction
            do {
                _ = try workflow.buildCovertSignatureMessages(&round)
            } catch {
                recordTransactionSignatureMaterialFailure(
                    error,
                    roundIdentifier: round.identifier
                )
                return failForWorkflowFailure(error)
            }
            round.substate = .awaitingSignatureWindow
            self.round = round
            OpalFusionDiagnostics.record(
                OpalFusion.Diagnostics.Events.transactionFinalizationSucceeded,
                category: OpalFusion.Diagnostics.Categories.transaction,
                traceID: OpalFusionDiagnostics.makeTraceID(for: round.identifier),
                fields: [
                    OpalFusionDiagnostics.makeOperationField("transaction_finalization"),
                    OpalFusionDiagnostics.phaseField(.assemblingTransaction),
                    OpalFusionDiagnostics.roundStateField(round.substate)
                ]
            )

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
                OpalFusionDiagnostics.record(
                    OpalFusion.Diagnostics.Events.covertMessageEncodeFailed,
                    category: OpalFusion.Diagnostics.Categories.covert,
                    traceID: OpalFusionDiagnostics.makeTraceID(for: round.identifier),
                    fields: [
                        OpalFusionDiagnostics.makeOperationField("covert_component_material")
                    ] + OpalFusionDiagnostics.makeErrorFields(for: error)
                )
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
                recordTransactionSignatureMaterialFailure(
                    error,
                    roundIdentifier: round.identifier
                )
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
            case .collectingInputs:
                if let commitmentsDeadline = round.deadlines.commitmentsDeadline,
                   now > commitmentsDeadline {
                    return failRound(
                        completionStatus: .transportFailed,
                        clientError: .transportUnavailable,
                        summary: "Commitment deadline elapsed before PlayerCommit submission"
                    )
                }
            case .awaitingBlindSignatures, .awaitingAllCommitments, .awaitingCovertComponentWindow:
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
                        completionStatus: .blameRequired,
                        clientError: .blameRequired,
                        summary: "Blame handling did not complete"
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
            let summary = serverFailureSummary(failure)

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

        private func serverFailureSummary(
            _ failure: OpalFusion.ProtocolModel.ServerFailure
        ) -> String {
            guard let message = failure.message,
                  message.contains(where: { $0.isWhitespace == false }) else {
                return "Coordinator rejected the current flow"
            }

            return message
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
                summary: "Execution materialization failed"
            )
        }

        private mutating func failBeforeRound(
            error: OpalFusion.Client.Error,
            summary: String
        ) -> [OpalFusion.Execution.RoundEngine.Effect] {
            round = nil
            recordSessionFailure(error: error, summary: summary)
            OpalFusionDiagnostics.record(
                OpalFusion.Diagnostics.Events.roundFailed,
                category: OpalFusion.Diagnostics.Categories.round,
                fields: [
                    OpalFusionDiagnostics.makeOperationField("pre_round_failure"),
                    OpalFusionDiagnostics.phaseField(.connecting)
                ] + OpalFusionDiagnostics.makeSanitizedSummaryFields(
                    errorCode: OpalFusionDiagnostics.errorCode(for: error),
                    summary: summary
                )
            )
            return [
                hostEvent(
                    roundIdentifier: nil,
                    kind: .failure,
                    phase: .connecting,
                    summary: summary,
                    shouldRecordDiagnostics: false
                )
            ]
        }

        private mutating func failActiveFlow(
            completionStatus: OpalFusion.Round.CompletionStatus,
            clientError: OpalFusion.Client.Error,
            summary: String
        ) -> [OpalFusion.Execution.RoundEngine.Effect] {
            if round?.substate == .terminal {
                return []
            }

            guard round?.identifier != nil else {
                return failBeforeRound(
                    error: clientError,
                    summary: summary
                )
            }

            return failRound(
                completionStatus: completionStatus,
                clientError: clientError,
                summary: summary
            )
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
            recordSessionFailure(error: clientError, summary: summary)
            OpalFusionDiagnostics.record(
                OpalFusion.Diagnostics.Events.roundFailed,
                category: OpalFusion.Diagnostics.Categories.round,
                traceID: OpalFusionDiagnostics.makeTraceID(for: round.identifier),
                fields: [
                    OpalFusionDiagnostics.makeOperationField("round_failure"),
                    OpalFusionDiagnostics.phaseField(.completed),
                    OpalFusionDiagnostics.roundStateField(round.substate),
                    OpalFusionDiagnostics.settlementStateField(completionStatus)
                ] + OpalFusionDiagnostics.makeSanitizedSummaryFields(
                    errorCode: OpalFusionDiagnostics.errorCode(for: clientError),
                    summary: summary
                )
            )

            return [
                hostEvent(
                    roundIdentifier: round.identifier,
                    kind: .failure,
                    phase: .completed,
                    summary: summary,
                    isTerminal: true,
                    shouldRecordDiagnostics: false
                )
            ]
        }

        private mutating func recordSessionFailure(
            error: OpalFusion.Client.Error,
            summary: String
        ) {
            session.isConnected = false
            session.lastError = error
            session.lastErrorSummary = summary
            session.connectionSubstate = .failed
        }

        private func hostEvent(
            roundIdentifier: OpalFusion.Round.Identifier?,
            kind: OpalFusion.Host.Event.Kind,
            phase: OpalFusion.Round.Phase,
            summary: String,
            isTerminal: Bool = false,
            errorCode: String? = nil,
            shouldRecordDiagnostics: Bool = true
        ) -> OpalFusion.Execution.RoundEngine.Effect {
            if shouldRecordDiagnostics {
                recordHostEventDiagnostics(
                    roundIdentifier: roundIdentifier,
                    kind: kind,
                    phase: phase,
                    summary: summary,
                    isTerminal: isTerminal,
                    errorCode: errorCode
                )
            }
            return .emitHostEvent(
                roundIdentifier: roundIdentifier,
                event: .init(
                    kind: kind,
                    phase: phase,
                    summary: summary,
                    isTerminal: isTerminal
                )
            )
        }

        private func recordTransactionProposalFailure(
            _ error: Swift.Error,
            roundIdentifier: OpalFusion.Round.Identifier?
        ) {
            OpalFusionDiagnostics.record(
                OpalFusion.Diagnostics.Events.transactionProposalFailed,
                category: OpalFusion.Diagnostics.Categories.transaction,
                traceID: OpalFusionDiagnostics.makeTraceID(for: roundIdentifier),
                fields: [
                    OpalFusionDiagnostics.makeOperationField("transaction_proposal"),
                    OpalFusionDiagnostics.phaseField(.assemblingTransaction)
                ] + OpalFusionDiagnostics.makeErrorFields(for: error)
            )
        }

        private func recordTransactionSignatureMaterialFailure(
            _ error: Swift.Error,
            roundIdentifier: OpalFusion.Round.Identifier?
        ) {
            OpalFusionDiagnostics.record(
                OpalFusion.Diagnostics.Events.transactionFinalizationFailed,
                category: OpalFusion.Diagnostics.Categories.transaction,
                traceID: OpalFusionDiagnostics.makeTraceID(for: roundIdentifier),
                fields: [
                    OpalFusionDiagnostics.makeOperationField("transaction_signature_material")
                ] + OpalFusionDiagnostics.makeErrorFields(for: error)
            )
        }

        private func recordHostEventDiagnostics(
            roundIdentifier: OpalFusion.Round.Identifier?,
            kind: OpalFusion.Host.Event.Kind,
            phase: OpalFusion.Round.Phase,
            summary: String,
            isTerminal: Bool,
            errorCode: String?
        ) {
            let event: OpalFusion.Diagnostics.Event
            if kind == .completed {
                event = OpalFusion.Diagnostics.Events.roundCompleted
            } else if kind == .failure {
                event = OpalFusion.Diagnostics.Events.roundFailed
            } else {
                event = OpalFusion.Diagnostics.Events.roundProgressed
            }

            var fields = [
                OpalFusionDiagnostics.makeOperationField("host_event"),
                OpalFusionDiagnostics.phaseField(phase)
            ]
            if isTerminal {
                fields.append(OpalFusionDiagnostics.publicField("terminal", true))
            }
            if kind == .failure {
                fields.append(
                    contentsOf: OpalFusionDiagnostics.makeSanitizedSummaryFields(
                        errorCode: errorCode ?? OpalFusion.Diagnostics.ErrorCodes.unknown,
                        summary: summary
                    )
                )
            }

            OpalFusionDiagnostics.record(
                event,
                category: OpalFusion.Diagnostics.Categories.round,
                traceID: OpalFusionDiagnostics.makeTraceID(for: roundIdentifier),
                fields: fields
            )
        }

        private func isServerTimeAcceptable(
            _ serverTimeUnixSeconds: UInt64,
            now: OpalFusion.Execution.Instant
        ) -> Bool {
            guard let serverTime = OpalFusion.Execution.Instant(
                validatingUnixSeconds: serverTimeUnixSeconds
            ) else {
                return false
            }
            let maximumDistance = session.baseline.roundTiming.maximumClockDiscrepancy
                .wholeMilliseconds
            guard maximumDistance >= 0 else {
                return false
            }
            let distance = serverTime.distance(to: now).wholeMilliseconds
            return distance >= -maximumDistance && distance <= maximumDistance
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

        private func makeParticipantReservationContext(
            roundIdentifier: OpalFusion.Round.Identifier,
            fusionBegin: OpalFusion.ProtocolModel.FusionBegin,
            serverHello: OpalFusion.ProtocolModel.ServerHello
        ) -> OpalFusion.Host.ParticipantReservationContext {
            .init(
                roundIdentifier: roundIdentifier,
                tierSatoshis: fusionBegin.tier,
                numberOfComponents: serverHello.numberOfComponents,
                componentFeeRateSatoshisPerKb: serverHello.componentFeeRateSatoshisPerKb,
                minimumExcessFeeSatoshis: serverHello.minimumExcessFeeSatoshis,
                maximumExcessFeeSatoshis: serverHello.maximumExcessFeeSatoshis
            )
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

        private func isValidCovertDomain(
            _ domain: String
        ) -> Bool {
            guard domain.isEmpty == false,
                  domain.hasWhitespace == false else {
                return false
            }

            return OpalFusion.Runtime.isValidHostName(domain)
        }

        private static func hasDuplicateInitialCommitments(
            _ commitments: [OpalFusion.Commitment.InitialCommitment]
        ) -> Bool {
            for index in commitments.indices {
                guard index < commitments.index(before: commitments.endIndex) else {
                    continue
                }

                if commitments[commitments.index(after: index)...].contains(commitments[index]) {
                    return true
                }
            }

            return false
        }
    }
}

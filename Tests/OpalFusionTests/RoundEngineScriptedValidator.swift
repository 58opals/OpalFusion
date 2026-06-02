// RoundEngineScriptedValidator.swift

@testable import OpalFusion
import Testing

struct RoundEngineScriptedValidator {
    @Test("Scripted round engine drives a happy-path round to success")
    func validateHappyPathRoundEngine() {
        var engine = Self.makeEngine()
        let roundIdentifier = OpalFusion.Round.Identifier(rawValue: "aabb")

        let connectEffects = engine.apply(
            input: .primaryConnected,
            now: Self.instant(995)
        )
        #expect(engine.clientState.isConnected == true)
        #expect(
            connectEffects == [
                .sendPrimary(.clientHello(Self.clientHello)),
                .emitHostEvent(
                    roundIdentifier: nil,
                    event: .init(
                        kind: .status,
                        phase: .connecting,
                        summary: "Primary channel connected; sending ClientHello"
                    )
                )
            ]
        )

        let helloEffects = engine.apply(
            input: .primaryMessage(.serverHello(Self.serverHello)),
            now: Self.instant(996)
        )
        #expect(
            helloEffects == [
                .sendPrimary(.joinPools(Self.joinPools)),
                .emitHostEvent(
                    roundIdentifier: nil,
                    event: .init(
                        kind: .status,
                        phase: .connecting,
                        summary: "ServerHello received; joining eligible pools"
                    )
                )
            ]
        )

        let warmupEffects = engine.apply(
            input: .primaryMessage(.fusionBegin(Self.fusionBegin)),
            now: Self.instant(1_000)
        )
        #expect(engine.round?.substate == .warmup)
        #expect(engine.clientState.round == nil)
        #expect(
            warmupEffects == [
                .prepareCovert(Self.covertEndpointContext),
                .emitHostEvent(
                    roundIdentifier: nil,
                    event: .init(
                        kind: .status,
                        phase: .connecting,
                        summary: "Fusion warmup started"
                    )
                )
            ]
        )

        let startRoundEffects = engine.apply(
            input: .primaryMessage(.startRound(Self.startRound)),
            now: Self.instant(1_030)
        )
        #expect(
            startRoundEffects == [
                .requestParticipantReservation(context: Self.participantReservationContext),
                .emitHostEvent(
                    roundIdentifier: roundIdentifier,
                    event: .init(
                        kind: .status,
                        phase: .registeringInputs,
                        summary: "StartRound received; collecting reserved inputs and outputs"
                    )
                )
            ]
        )
        #expect(
            engine.clientState.round == .init(
                identifier: roundIdentifier,
                phase: .registeringInputs
            )
        )

        let commitEffects = engine.apply(
            input: .participantReservationLoaded(Self.participantReservation),
            now: Self.instant(1_031)
        )
        #expect(
            commitEffects == [
                .sendPrimary(.playerCommit(Self.playerCommit)),
                .emitHostEvent(
                    roundIdentifier: roundIdentifier,
                    event: .init(
                        kind: .status,
                        phase: .awaitingBlindSignatures,
                        summary: "Submitting player commitments and blind requests"
                    )
                )
            ]
        )
        #expect(engine.clientState.round?.phase == .awaitingBlindSignatures)

        let blindEffects = engine.apply(
            input: .primaryMessage(.blindSignatureResponses(Self.blindSignatureResponses)),
            now: Self.instant(1_032)
        )
        #expect(
            blindEffects == [
                .emitHostEvent(
                    roundIdentifier: roundIdentifier,
                    event: .init(
                        kind: .status,
                        phase: .awaitingCommitments,
                        summary: "Blind signature responses received"
                    )
                )
            ]
        )

        let commitmentEffects = engine.apply(
            input: .primaryMessage(.allCommitments(Self.allCommitments)),
            now: Self.instant(1_034)
        )
        #expect(
            commitmentEffects == [
                .emitHostEvent(
                    roundIdentifier: roundIdentifier,
                    event: .init(
                        kind: .status,
                        phase: .awaitingCommitments,
                        summary: "All commitments received; waiting for covert submit window"
                    )
                )
            ]
        )
        #expect(engine.clientState.round?.phase == .awaitingCommitments)

        let covertEffects = engine.apply(
            input: .clockAdvanced,
            now: Self.instant(1_035)
        )
        #expect(
            covertEffects == [
                .submitCovert(Self.covertComponentMessage),
                .emitHostEvent(
                    roundIdentifier: roundIdentifier,
                    event: .init(
                        kind: .status,
                        phase: .awaitingCommitments,
                        summary: "Submitting covert components"
                    )
                )
            ]
        )

        let sharedEffects = engine.apply(
            input: .primaryMessage(.shareCovertComponents(Self.sharedComponents)),
            now: Self.instant(1_040)
        )
        #expect(
            sharedEffects == [
                .requestTransactionFinalization(
                    roundIdentifier: roundIdentifier,
                    proposal: Self.transactionProposal
                ),
                .emitHostEvent(
                    roundIdentifier: roundIdentifier,
                    event: .init(
                        kind: .status,
                        phase: .assemblingTransaction,
                        summary: "Shared components received; requesting transaction finalization"
                    )
                )
            ]
        )

        let finalizedEffects = engine.apply(
            input: .finalizedTransactionLoaded(Self.finalizedTransaction),
            now: Self.instant(1_042)
        )
        #expect(
            finalizedEffects == [
                .emitHostEvent(
                    roundIdentifier: roundIdentifier,
                    event: .init(
                        kind: .status,
                        phase: .assemblingTransaction,
                        summary: "Transaction finalized; waiting for signature window"
                    )
                )
            ]
        )
        #expect(engine.clientState.round?.phase == .assemblingTransaction)

        let signatureEffects = engine.apply(
            input: .clockAdvanced,
            now: Self.instant(1_050)
        )
        #expect(
            signatureEffects == [
                .submitCovert(Self.signatureMessage),
                .emitHostEvent(
                    roundIdentifier: roundIdentifier,
                    event: .init(
                        kind: .status,
                        phase: .assemblingTransaction,
                        summary: "Submitting covert transaction signatures"
                    )
                )
            ]
        )

        let resultEffects = engine.apply(
            input: .primaryMessage(.fusionResult(Self.successResult)),
            now: Self.instant(1_055)
        )
        #expect(
            resultEffects == [
                .emitHostEvent(
                    roundIdentifier: roundIdentifier,
                    event: .init(
                        kind: .completed,
                        phase: .completed,
                        summary: "Round completed successfully",
                        isTerminal: true
                    )
                )
            ]
        )
        #expect(
            engine.clientState.round == .init(
                identifier: roundIdentifier,
                participantCount: nil,
                completionStatus: .success
            )
        )
    }

    @Test("Round engine rejects mismatched blind signature response counts at receipt")
    func validateBlindSignatureResponseCountMismatch() {
        var engine = Self.makeEngine()
        Self.driveThroughStartRound(engine: &engine)
        _ = engine.apply(
            input: .participantReservationLoaded(Self.participantReservation),
            now: Self.instant(1_031)
        )

        let effects = engine.apply(
            input: .primaryMessage(
                .blindSignatureResponses(
                    .init(
                        responses: Self.blindSignatureResponses.responses + [
                            .init(scalar: [0x28])
                        ]
                    )
                )
            ),
            now: Self.instant(1_032)
        )

        #expect(engine.session.lastError == .protocolIncompatible)
        #expect(engine.round?.completionStatus == .protocolIncompatible)
        #expect(
            effects == [
                .emitHostEvent(
                    roundIdentifier: Self.roundIdentifier,
                    event: .init(
                        kind: .failure,
                        phase: .completed,
                        summary: "Blind signature response count did not match PlayerCommit request count",
                        isTerminal: true
                    )
                )
            ]
        )
    }

    @Test("Round engine rejects AllCommitments that omit local commitments")
    func validateAllCommitmentsMustIncludeLocalCommitments() {
        var engine = Self.makeEngine()
        Self.driveThroughStartRound(engine: &engine)
        _ = engine.apply(
            input: .participantReservationLoaded(Self.participantReservation),
            now: Self.instant(1_031)
        )
        _ = engine.apply(
            input: .primaryMessage(.blindSignatureResponses(Self.blindSignatureResponses)),
            now: Self.instant(1_032)
        )

        let effects = engine.apply(
            input: .primaryMessage(.allCommitments(.init(initialCommitments: []))),
            now: Self.instant(1_034)
        )

        #expect(engine.session.lastError == .protocolIncompatible)
        #expect(engine.round?.completionStatus == .protocolIncompatible)
        #expect(
            effects == [
                .emitHostEvent(
                    roundIdentifier: Self.roundIdentifier,
                    event: .init(
                        kind: .failure,
                        phase: .completed,
                        summary: "AllCommitments omitted a local commitment",
                        isTerminal: true
                    )
                )
            ]
        )
    }

    @Test("Round engine rejects duplicate AllCommitments at receipt")
    func validateAllCommitmentsRejectsDuplicates() {
        var engine = Self.makeEngine()
        Self.driveThroughStartRound(engine: &engine)
        _ = engine.apply(
            input: .participantReservationLoaded(Self.participantReservation),
            now: Self.instant(1_031)
        )
        _ = engine.apply(
            input: .primaryMessage(.blindSignatureResponses(Self.blindSignatureResponses)),
            now: Self.instant(1_032)
        )

        let effects = engine.apply(
            input: .primaryMessage(
                .allCommitments(
                    .init(
                        initialCommitments: [
                            Self.initialCommitment,
                            Self.initialCommitment
                        ]
                    )
                )
            ),
            now: Self.instant(1_034)
        )

        #expect(engine.session.lastError == .protocolIncompatible)
        #expect(engine.round?.completionStatus == .protocolIncompatible)
        #expect(
            effects == [
                .emitHostEvent(
                    roundIdentifier: Self.roundIdentifier,
                    event: .init(
                        kind: .failure,
                        phase: .completed,
                        summary: "AllCommitments contained duplicate commitments",
                        isTerminal: true
                    )
                )
            ]
        )
    }

    @Test("Round engine validates shared components even when signatures are skipped")
    func validateSkipSignaturesStillValidatesSharedComponents() {
        var engine = OpalFusion.Execution.RoundEngine(
            configuration: Self.configuration,
            genesisHash: [0xAA, 0xBB, 0xCC],
            joinPools: Self.joinPools,
            workflow: .init(
                buildPlayerCommit: { _ in Self.playerCommit },
                buildCovertComponentMessages: { _ in [Self.covertComponentMessage] },
                buildTransactionFinalizationProposal: { _ in
                    throw OpalFusion.Execution.WorkflowFailure.protocolValidationFailed(
                        "Shared component validation failed"
                    )
                },
                buildCovertSignatureMessages: { _ in [Self.signatureMessage] },
                buildMyProofsList: { _ in Self.myProofsList },
                buildBlames: { _ in Self.blames }
            )
        )
        let roundIdentifier = OpalFusion.Round.Identifier(rawValue: "aabb")
        let skipSharedComponents = OpalFusion.ProtocolModel.ShareCovertComponents(
            serializedComponents: Self.sharedComponents.serializedComponents,
            skipSignatures: true,
            sessionHash: Self.sharedComponents.sessionHash
        )

        Self.driveThroughStartRound(engine: &engine)
        _ = engine.apply(
            input: .participantReservationLoaded(Self.participantReservation),
            now: Self.instant(1_031)
        )
        _ = engine.apply(
            input: .primaryMessage(.blindSignatureResponses(Self.blindSignatureResponses)),
            now: Self.instant(1_032)
        )
        _ = engine.apply(
            input: .primaryMessage(.allCommitments(Self.allCommitments)),
            now: Self.instant(1_034)
        )
        _ = engine.apply(input: .clockAdvanced, now: Self.instant(1_035))

        let sharedEffects = engine.apply(
            input: .primaryMessage(.shareCovertComponents(skipSharedComponents)),
            now: Self.instant(1_040)
        )

        #expect(engine.clientState.round?.completionStatus == .protocolIncompatible)
        #expect(engine.session.lastError == .protocolIncompatible)
        #expect(
            sharedEffects == [
                .emitHostEvent(
                    roundIdentifier: roundIdentifier,
                    event: .init(
                        kind: .failure,
                        phase: .completed,
                        summary: "Shared component validation failed",
                        isTerminal: true
                    )
                )
            ]
        )
    }

    @Test("Round engine rejects duplicate skipped-signature results after blame begins")
    func validateSkipSignatureResultCannotOverwriteBlame() {
        var engine = Self.makeEngine()
        let roundIdentifier = OpalFusion.Round.Identifier(rawValue: "aabb")
        let skipSharedComponents = OpalFusion.ProtocolModel.ShareCovertComponents(
            serializedComponents: Self.sharedComponents.serializedComponents,
            skipSignatures: true,
            sessionHash: Self.sharedComponents.sessionHash
        )

        Self.driveThroughStartRound(engine: &engine)
        _ = engine.apply(
            input: .participantReservationLoaded(Self.participantReservation),
            now: Self.instant(1_031)
        )
        _ = engine.apply(
            input: .primaryMessage(.blindSignatureResponses(Self.blindSignatureResponses)),
            now: Self.instant(1_032)
        )
        _ = engine.apply(
            input: .primaryMessage(.allCommitments(Self.allCommitments)),
            now: Self.instant(1_034)
        )
        _ = engine.apply(input: .clockAdvanced, now: Self.instant(1_035))
        _ = engine.apply(
            input: .primaryMessage(.shareCovertComponents(skipSharedComponents)),
            now: Self.instant(1_040)
        )
        _ = engine.apply(
            input: .primaryMessage(.fusionResult(Self.failureResult)),
            now: Self.instant(1_041)
        )
        #expect(engine.clientState.round?.phase == .blame)
        #expect(engine.clientState.round?.completionStatus == nil)

        let lateResultEffects = engine.apply(
            input: .primaryMessage(.fusionResult(Self.successResult)),
            now: Self.instant(1_042)
        )

        #expect(engine.clientState.round?.completionStatus == .protocolIncompatible)
        #expect(engine.session.lastError == .protocolIncompatible)
        #expect(
            lateResultEffects == [
                .emitHostEvent(
                    roundIdentifier: roundIdentifier,
                    event: .init(
                        kind: .failure,
                        phase: .completed,
                        summary: "FusionResult arrived out of order",
                        isTerminal: true
                    )
                )
            ]
        )
    }

    @Test("Round engine rejects successful FusionResult after signatures were skipped")
    func validateSkippedSignaturesCannotCompleteSuccessfully() {
        var engine = Self.makeEngine()
        let roundIdentifier = OpalFusion.Round.Identifier(rawValue: "aabb")
        let skipSharedComponents = OpalFusion.ProtocolModel.ShareCovertComponents(
            serializedComponents: Self.sharedComponents.serializedComponents,
            skipSignatures: true,
            sessionHash: Self.sharedComponents.sessionHash
        )

        Self.driveThroughStartRound(engine: &engine)
        _ = engine.apply(
            input: .participantReservationLoaded(Self.participantReservation),
            now: Self.instant(1_031)
        )
        _ = engine.apply(
            input: .primaryMessage(.blindSignatureResponses(Self.blindSignatureResponses)),
            now: Self.instant(1_032)
        )
        _ = engine.apply(
            input: .primaryMessage(.allCommitments(Self.allCommitments)),
            now: Self.instant(1_034)
        )
        _ = engine.apply(input: .clockAdvanced, now: Self.instant(1_035))
        _ = engine.apply(
            input: .primaryMessage(.shareCovertComponents(skipSharedComponents)),
            now: Self.instant(1_040)
        )

        let resultEffects = engine.apply(
            input: .primaryMessage(.fusionResult(Self.successResult)),
            now: Self.instant(1_041)
        )

        #expect(engine.clientState.round?.completionStatus == .protocolIncompatible)
        #expect(engine.session.lastError == .protocolIncompatible)
        #expect(
            resultEffects == [
                .emitHostEvent(
                    roundIdentifier: roundIdentifier,
                    event: .init(
                        kind: .failure,
                        phase: .completed,
                        summary: "FusionResult reported success after signatures were skipped",
                        isTerminal: true
                    )
                )
            ]
        )
    }

    @Test("Round engine rejects shared components before local covert submission")
    func validateSharedComponentsBeforeCovertSubmissionFails() {
        var engine = Self.makeEngine()
        let roundIdentifier = OpalFusion.Round.Identifier(rawValue: "aabb")

        Self.driveThroughStartRound(engine: &engine)
        _ = engine.apply(
            input: .participantReservationLoaded(Self.participantReservation),
            now: Self.instant(1_031)
        )
        _ = engine.apply(
            input: .primaryMessage(.blindSignatureResponses(Self.blindSignatureResponses)),
            now: Self.instant(1_032)
        )
        _ = engine.apply(
            input: .primaryMessage(.allCommitments(Self.allCommitments)),
            now: Self.instant(1_034)
        )

        let sharedEffects = engine.apply(
            input: .primaryMessage(.shareCovertComponents(Self.sharedComponents)),
            now: Self.instant(1_034)
        )

        #expect(engine.clientState.round?.completionStatus == .protocolIncompatible)
        #expect(engine.session.lastError == .protocolIncompatible)
        #expect(
            sharedEffects == [
                .emitHostEvent(
                    roundIdentifier: roundIdentifier,
                    event: .init(
                        kind: .failure,
                        phase: .completed,
                        summary: "Shared components arrived out of order",
                        isTerminal: true
                    )
                )
            ]
        )
    }

    @Test("Round engine rejects covert acknowledgements before local covert submission")
    func validateCovertAcknowledgementBeforeSubmissionFails() {
        var engine = Self.makeEngine()
        let roundIdentifier = OpalFusion.Round.Identifier(rawValue: "aabb")

        Self.driveThroughStartRound(engine: &engine)
        _ = engine.apply(
            input: .participantReservationLoaded(Self.participantReservation),
            now: Self.instant(1_031)
        )
        _ = engine.apply(
            input: .primaryMessage(.blindSignatureResponses(Self.blindSignatureResponses)),
            now: Self.instant(1_032)
        )
        _ = engine.apply(
            input: .primaryMessage(.allCommitments(Self.allCommitments)),
            now: Self.instant(1_034)
        )

        let acknowledgementEffects = engine.apply(
            input: .covertResponse(.acknowledgement(.init())),
            now: Self.instant(1_034)
        )

        #expect(engine.clientState.round?.completionStatus == .protocolIncompatible)
        #expect(engine.session.lastError == .protocolIncompatible)
        #expect(
            acknowledgementEffects == [
                .emitHostEvent(
                    roundIdentifier: roundIdentifier,
                    event: .init(
                        kind: .failure,
                        phase: .completed,
                        summary: "Covert acknowledgement arrived out of order",
                        isTerminal: true
                    )
                )
            ]
        )
    }

    @Test("Round engine rejects late finalized transactions before signature extraction")
    func validateLateFinalizedTransactionDoesNotBuildSignatures() {
        var engine = OpalFusion.Execution.RoundEngine(
            configuration: Self.configuration,
            genesisHash: [0xAA, 0xBB, 0xCC],
            joinPools: Self.joinPools,
            workflow: .init(
                buildPlayerCommit: { _ in Self.playerCommit },
                buildCovertComponentMessages: { _ in [Self.covertComponentMessage] },
                buildTransactionFinalizationProposal: { _ in Self.transactionProposal },
                buildCovertSignatureMessages: { _ in
                    Issue.record("Signature messages must not be built after the signature deadline")
                    return [Self.signatureMessage]
                },
                buildMyProofsList: { _ in Self.myProofsList },
                buildBlames: { _ in Self.blames }
            )
        )
        let roundIdentifier = OpalFusion.Round.Identifier(rawValue: "aabb")

        Self.driveToSharedComponents(engine: &engine)

        let finalizedEffects = engine.apply(
            input: .finalizedTransactionLoaded(Self.finalizedTransaction),
            now: Self.instant(1_061)
        )

        #expect(engine.clientState.round?.completionStatus == .transportFailed)
        #expect(engine.session.lastError == .transportUnavailable)
        #expect(
            finalizedEffects == [
                .emitHostEvent(
                    roundIdentifier: roundIdentifier,
                    event: .init(
                        kind: .failure,
                        phase: .completed,
                        summary: "Signature deadline elapsed before submission",
                        isTerminal: true
                    )
                )
            ]
        )
    }

    @Test("Scripted round engine supports blame handling and restart continuation")
    func validateBlameAndRestartFlow() {
        var engine = Self.makeEngine()
        let roundIdentifier = OpalFusion.Round.Identifier(rawValue: "aabb")

        Self.driveToSharedComponents(engine: &engine)

        let finalizedEffects = engine.apply(
            input: .finalizedTransactionLoaded(Self.finalizedTransaction),
            now: Self.instant(1_050)
        )
        #expect(
            finalizedEffects == [
                .emitHostEvent(
                    roundIdentifier: roundIdentifier,
                    event: .init(
                        kind: .status,
                        phase: .assemblingTransaction,
                        summary: "Transaction finalized; waiting for signature window"
                    )
                ),
                .submitCovert(Self.signatureMessage),
                .emitHostEvent(
                    roundIdentifier: roundIdentifier,
                    event: .init(
                        kind: .status,
                        phase: .assemblingTransaction,
                        summary: "Submitting covert transaction signatures"
                    )
                )
            ]
        )

        let failureEffects = engine.apply(
            input: .primaryMessage(.fusionResult(Self.failureResult)),
            now: Self.instant(1_055)
        )
        #expect(
            failureEffects == [
                .sendPrimary(.myProofsList(Self.myProofsList)),
                .emitHostEvent(
                    roundIdentifier: roundIdentifier,
                    event: .init(
                        kind: .warning,
                        phase: .blame,
                        summary: "Round result requires blame handling"
                    )
                )
            ]
        )
        #expect(engine.clientState.round?.phase == .blame)
        #expect(engine.clientState.round?.completionStatus == nil)

        let blameEffects = engine.apply(
            input: .primaryMessage(.theirProofsList(Self.theirProofsList)),
            now: Self.instant(1_056)
        )
        #expect(
            blameEffects == [
                .sendPrimary(.blames(Self.blames)),
                .emitHostEvent(
                    roundIdentifier: roundIdentifier,
                    event: .init(
                        kind: .warning,
                        phase: .blame,
                        summary: "Submitting blame proofs and awaiting restart"
                    )
                )
            ]
        )
        #expect(engine.round?.substate == .awaitingRestart)

        let restartEffects = engine.apply(
            input: .primaryMessage(.restartRound(.init())),
            now: Self.instant(1_060)
        )
        #expect(
            restartEffects == [
                .emitHostEvent(
                    roundIdentifier: roundIdentifier,
                    event: .init(
                        kind: .status,
                        phase: .connecting,
                        summary: "Restarting round after blame handling"
                    )
                )
            ]
        )
        #expect(engine.round == nil)
        #expect(engine.clientState.round == nil)
        #expect(engine.clientState.isConnected == true)
        #expect(engine.session.restartCount == 1)
        #expect(engine.session.latestServerHello == Self.serverHello)
    }

    @Test("Round engine maps unresolved blame handling to a distinct terminal outcome")
    func validateUnresolvedBlameTerminalOutcome() {
        var engine = Self.makeEngine()
        let roundIdentifier = OpalFusion.Round.Identifier(rawValue: "aabb")

        Self.driveToSignatureSubmission(engine: &engine)
        _ = engine.apply(
            input: .primaryMessage(.fusionResult(Self.failureResult)),
            now: Self.instant(1_055)
        )
        _ = engine.apply(
            input: .primaryMessage(.theirProofsList(Self.theirProofsList)),
            now: Self.instant(1_056)
        )

        let timeoutEffects = engine.apply(
            input: .clockAdvanced,
            now: Self.instant(1_116)
        )

        #expect(engine.session.lastError == .blameRequired)
        #expect(engine.session.lastErrorSummary == "Blame handling did not complete")
        #expect(engine.clientState.round?.completionStatus == .blameRequired)
        #expect(
            timeoutEffects == [
                .emitHostEvent(
                    roundIdentifier: roundIdentifier,
                    event: .init(
                        kind: .failure,
                        phase: .completed,
                        summary: "Blame handling did not complete",
                        isTerminal: true
                    )
                )
            ]
        )
    }

    @Test("Round engine preserves a pre-round server rejection over later transport failure noise")
    func validateServerFailurePrecedenceOverTransportFailure() {
        var engine = Self.makeEngine()
        _ = engine.apply(
            input: .primaryConnected,
            now: Self.instant(995)
        )
        _ = engine.apply(
            input: .primaryMessage(.serverHello(Self.serverHello)),
            now: Self.instant(996)
        )

        let rejectionSummary = "Coordinator rejected JoinPools"
        let rejectionEffects = engine.apply(
            input: .primaryMessage(
                .serverFailure(.init(message: rejectionSummary))
            ),
            now: Self.instant(997)
        )
        #expect(
            rejectionEffects == [
                .emitHostEvent(
                    roundIdentifier: nil,
                    event: .init(
                        kind: .failure,
                        phase: .connecting,
                        summary: rejectionSummary
                    )
                )
            ]
        )
        #expect(engine.session.lastError == .coordinatorRejected)
        #expect(engine.session.lastErrorSummary == rejectionSummary)
        #expect(engine.clientState.isConnected == false)

        let transportEffects = engine.apply(
            input: .primaryTransportFailed(
                summary: "Primary read failed"
            ),
            now: Self.instant(998)
        )
        #expect(transportEffects.isEmpty)
        #expect(engine.session.lastError == .coordinatorRejected)
        #expect(engine.session.lastErrorSummary == rejectionSummary)
        #expect(engine.clientState.isConnected == false)
    }

    @Test("Round engine rejects impossible ServerHello excess fee ranges")
    func validateServerHelloExcessFeeRange() {
        var engine = Self.makeEngine()
        _ = engine.apply(
            input: .primaryConnected,
            now: Self.instant(995)
        )

        let effects = engine.apply(
            input: .primaryMessage(
                .serverHello(
                    .init(
                        tiers: Self.serverHello.tiers,
                        numberOfComponents: Self.serverHello.numberOfComponents,
                        componentFeeRateSatoshisPerKb: Self.serverHello.componentFeeRateSatoshisPerKb,
                        minimumExcessFeeSatoshis: 501,
                        maximumExcessFeeSatoshis: 500,
                        donationAddress: Self.serverHello.donationAddress
                    )
                )
            ),
            now: Self.instant(996)
        )

        #expect(engine.session.lastError == .protocolIncompatible)
        #expect(engine.session.latestServerHello == nil)
        #expect(engine.round == nil)
        #expect(
            effects == [
                .emitHostEvent(
                    roundIdentifier: nil,
                    event: .init(
                        kind: .failure,
                        phase: .connecting,
                        summary: "ServerHello excess fee range was invalid"
                    )
                )
            ]
        )
    }

    @Test("Round engine rejects ServerHello messages without components")
    func validateServerHelloComponentCount() {
        var engine = Self.makeEngine()
        _ = engine.apply(
            input: .primaryConnected,
            now: Self.instant(995)
        )

        let effects = engine.apply(
            input: .primaryMessage(
                .serverHello(
                    .init(
                        tiers: Self.serverHello.tiers,
                        numberOfComponents: 0,
                        componentFeeRateSatoshisPerKb: Self.serverHello.componentFeeRateSatoshisPerKb,
                        minimumExcessFeeSatoshis: Self.serverHello.minimumExcessFeeSatoshis,
                        maximumExcessFeeSatoshis: Self.serverHello.maximumExcessFeeSatoshis,
                        donationAddress: Self.serverHello.donationAddress
                    )
                )
            ),
            now: Self.instant(996)
        )

        #expect(engine.session.lastError == .protocolIncompatible)
        #expect(engine.session.latestServerHello == nil)
        #expect(engine.round == nil)
        #expect(
            effects == [
                .emitHostEvent(
                    roundIdentifier: nil,
                    event: .init(
                        kind: .failure,
                        phase: .connecting,
                        summary: "ServerHello component count was invalid"
                    )
                )
            ]
        )
    }

    @Test("Round engine owns timing semantics and validates server clock skew")
    func validateTimingOwnership() {
        var happyEngine = Self.makeEngine()
        Self.driveThroughStartRound(engine: &happyEngine)

        guard let deadlines = happyEngine.round?.deadlines else {
            Issue.record("Expected round deadlines after StartRound")
            return
        }

        #expect(deadlines.fusionBeginAt == Self.instant(1_000))
        #expect(deadlines.warmupTarget == Self.instant(1_030))
        #expect(deadlines.warmupDeadline == Self.instant(1_033))
        #expect(deadlines.roundStartAt == Self.instant(1_030))
        #expect(deadlines.commitmentsDeadline == Self.instant(1_033))
        #expect(deadlines.covertComponentsStart == Self.instant(1_035))
        #expect(deadlines.covertComponentsDeadline == Self.instant(1_045))
        #expect(deadlines.signaturesStart == Self.instant(1_050))
        #expect(deadlines.signaturesDeadline == Self.instant(1_060))
        #expect(deadlines.conclusionTimeout == Self.instant(1_065))
        #expect(deadlines.closeStart == Self.instant(1_075))
        #expect(deadlines.blameCloseStart == Self.instant(1_110))
        #expect(deadlines.blameVerifyDeadline == Self.instant(1_115))

        var skewedEngine = Self.makeEngine()
        _ = skewedEngine.apply(input: .primaryConnected, now: Self.instant(995))
        _ = skewedEngine.apply(
            input: .primaryMessage(.serverHello(Self.serverHello)),
            now: Self.instant(996)
        )
        let skewEffects = skewedEngine.apply(
            input: .primaryMessage(
                .fusionBegin(
                    .init(
                        tier: 10_000,
                        covertDomain: "covert.example.org",
                        covertPort: 7_447,
                        covertSsl: true,
                        serverTimeUnixSeconds: 1_010
                    )
                )
            ),
            now: Self.instant(1_000)
        )
        #expect(skewedEngine.session.lastError == .protocolIncompatible)
        #expect(skewedEngine.round == nil)
        #expect(
            skewEffects == [
                .emitHostEvent(
                    roundIdentifier: nil,
                    event: .init(
                        kind: .failure,
                        phase: .connecting,
                        summary: "FusionBegin server time exceeded the allowed clock skew"
                    )
                )
            ]
        )

        var timeoutEngine = Self.makeEngine()
        Self.driveThroughStartRound(engine: &timeoutEngine)
        let lateReservationEffects = timeoutEngine.apply(
            input: .participantReservationLoaded(Self.participantReservation),
            now: Self.instant(1_034)
        )
        #expect(timeoutEngine.clientState.round?.phase == .completed)
        #expect(timeoutEngine.clientState.round?.completionStatus == .transportFailed)
        #expect(
            lateReservationEffects == [
                .emitHostEvent(
                    roundIdentifier: OpalFusion.Round.Identifier(rawValue: "aabb"),
                    event: .init(
                        kind: .failure,
                        phase: .completed,
                        summary: "Commitment deadline elapsed before PlayerCommit submission",
                        isTerminal: true
                    )
                )
            ]
        )
    }

    @Test("Round engine lets the default conclusion timeout win before close-start cleanup")
    func validateDefaultConclusionTimeoutPrecedesCloseStartCleanup() {
        var engine = Self.makeEngine()
        Self.driveToSignatureSubmission(engine: &engine)

        let effects = engine.apply(
            input: .clockAdvanced,
            now: Self.instant(1_075)
        )

        #expect(engine.round?.substate == .terminal)
        #expect(
            effects == [
                .emitHostEvent(
                    roundIdentifier: Self.roundIdentifier,
                    event: .init(
                        kind: .failure,
                        phase: .completed,
                        summary: "Round conclusion timeout elapsed",
                        isTerminal: true
                    )
                )
            ]
        )
    }

    @Test("Round engine emits one covert reset at close-start while the round remains active")
    func validateCloseStartCovertResetIsOneShot() {
        var engine = Self.makeEngine(baseline: Self.closeStartReachableBaseline)
        Self.driveToSignatureSubmission(engine: &engine)

        let effects = engine.apply(
            input: .clockAdvanced,
            now: Self.instant(1_075)
        )

        #expect(effects == [.resetCovertTransport])
        #expect(engine.round?.substate == .submittingSignatures)
        #expect(engine.clientState.round?.phase == .assemblingTransaction)
        #expect(
            engine.apply(
                input: .clockAdvanced,
                now: Self.instant(1_076)
            )
                .isEmpty
        )
    }

    @Test("Round engine does not emit close-start covert reset during blame restart handling")
    func validateCloseStartCovertResetIsSkippedDuringBlameRestart() {
        var engine = Self.makeEngine(baseline: Self.closeStartReachableBaseline)
        Self.driveToSignatureSubmission(engine: &engine)
        _ = engine.apply(
            input: .primaryMessage(.fusionResult(Self.failureResult)),
            now: Self.instant(1_055)
        )
        _ = engine.apply(
            input: .primaryMessage(.theirProofsList(Self.theirProofsList)),
            now: Self.instant(1_056)
        )

        #expect(engine.round?.substate == .awaitingRestart)
        #expect(
            engine.apply(
                input: .clockAdvanced,
                now: Self.instant(1_075)
            )
                .isEmpty
        )
    }

    @Test("Round engine propagates the official covert spare count")
    func validateCovertSpareCountPropagation() {
        var engine = Self.makeEngine()
        _ = engine.apply(input: .primaryConnected, now: Self.instant(995))
        _ = engine.apply(
            input: .primaryMessage(.serverHello(Self.serverHello)),
            now: Self.instant(996)
        )

        let effects = engine.apply(
            input: .primaryMessage(.fusionBegin(Self.fusionBegin)),
            now: Self.instant(1_000)
        )

        guard case let .prepareCovert(context) = effects.first else {
            Issue.record("Expected FusionBegin to prepare a covert endpoint")
            return
        }
        #expect(context.spareConnectionCount == 6)
        #expect(
            context.spareConnectionCount
                == OpalFusion.Transport.BaselineConfiguration.electronCash443.covertTiming.spareConnectionCount
        )
    }

    @Test("Round engine enforces the official warmup slop boundary")
    func validateWarmupSlopBoundary() {
        var boundaryEngine = Self.makeEngine()
        _ = boundaryEngine.apply(input: .primaryConnected, now: Self.instant(995))
        _ = boundaryEngine.apply(
            input: .primaryMessage(.serverHello(Self.serverHello)),
            now: Self.instant(996)
        )
        _ = boundaryEngine.apply(
            input: .primaryMessage(.fusionBegin(Self.fusionBegin)),
            now: Self.instant(1_000)
        )

        #expect(
            boundaryEngine.apply(
                input: .clockAdvanced,
                now: Self.instant(1_033)
            ).isEmpty
        )
        let acceptedEffects = boundaryEngine.apply(
            input: .primaryMessage(.startRound(Self.startRound)),
            now: Self.instant(1_033)
        )
        #expect(boundaryEngine.clientState.round?.phase == .registeringInputs)
        #expect(acceptedEffects.first == .requestParticipantReservation(context: Self.participantReservationContext))

        var timeoutEngine = Self.makeEngine()
        _ = timeoutEngine.apply(input: .primaryConnected, now: Self.instant(995))
        _ = timeoutEngine.apply(
            input: .primaryMessage(.serverHello(Self.serverHello)),
            now: Self.instant(996)
        )
        _ = timeoutEngine.apply(
            input: .primaryMessage(.fusionBegin(Self.fusionBegin)),
            now: Self.instant(1_000)
        )

        let timeoutEffects = timeoutEngine.apply(
            input: .clockAdvanced,
            now: Self.instant(1_034)
        )
        #expect(timeoutEngine.session.lastError == .transportUnavailable)
        #expect(timeoutEngine.round?.substate == .terminal)
        #expect(timeoutEngine.clientState.round == nil)
        #expect(
            timeoutEffects == [
                .emitHostEvent(
                    roundIdentifier: nil,
                    event: .init(
                        kind: .failure,
                        phase: .completed,
                        summary: "Warmup expired before StartRound arrived",
                        isTerminal: true
                    )
                )
            ]
        )
    }

    @Test("Round engine times out pending participant reservation at commitment deadline")
    func validatePendingReservationTimesOutAtCommitmentDeadline() {
        var engine = Self.makeEngine()
        Self.driveThroughStartRound(engine: &engine)

        let timeoutEffects = engine.apply(
            input: .clockAdvanced,
            now: Self.instant(1_034)
        )

        #expect(engine.clientState.round?.phase == .completed)
        #expect(engine.clientState.round?.completionStatus == .transportFailed)
        #expect(
            timeoutEffects == [
                .emitHostEvent(
                    roundIdentifier: OpalFusion.Round.Identifier(rawValue: "aabb"),
                    event: .init(
                        kind: .failure,
                        phase: .completed,
                        summary: "Commitment deadline elapsed before PlayerCommit submission",
                        isTerminal: true
                    )
                )
            ]
        )
    }

    @Test("Round engine preserves covert component timeout after PlayerCommit")
    func validateCovertComponentTimeoutAfterPlayerCommit() {
        var timeoutEngine = Self.makeEngine()
        Self.driveThroughStartRound(engine: &timeoutEngine)
        _ = timeoutEngine.apply(
            input: .participantReservationLoaded(Self.participantReservation),
            now: Self.instant(1_031)
        )
        let timeoutEffects = timeoutEngine.apply(
            input: .clockAdvanced,
            now: Self.instant(1_046)
        )
        #expect(timeoutEngine.clientState.round?.phase == .completed)
        #expect(timeoutEngine.clientState.round?.completionStatus == .transportFailed)
        #expect(
            timeoutEffects == [
                .emitHostEvent(
                    roundIdentifier: OpalFusion.Round.Identifier(rawValue: "aabb"),
                    event: .init(
                        kind: .failure,
                        phase: .completed,
                        summary: "Round expired before covert component submission completed",
                        isTerminal: true
                    )
                )
            ]
        )
    }

    @Test("Round engine rejects FusionBegin tiers that were not joined")
    func validateFusionBeginTierMustBeJoined() {
        var engine = Self.makeEngine()
        _ = engine.apply(input: .primaryConnected, now: Self.instant(995))
        _ = engine.apply(
            input: .primaryMessage(.serverHello(Self.serverHello)),
            now: Self.instant(996)
        )

        let effects = engine.apply(
            input: .primaryMessage(
                .fusionBegin(
                    .init(
                        tier: 20_000,
                        covertDomain: Self.fusionBegin.covertDomain,
                        covertPort: Self.fusionBegin.covertPort,
                        covertSsl: Self.fusionBegin.covertSsl,
                        serverTimeUnixSeconds: Self.fusionBegin.serverTimeUnixSeconds
                    )
                )
            ),
            now: Self.instant(1_000)
        )

        #expect(engine.session.lastError == .protocolIncompatible)
        #expect(engine.round == nil)
        #expect(
            effects == [
                .emitHostEvent(
                    roundIdentifier: nil,
                    event: .init(
                        kind: .failure,
                        phase: .connecting,
                        summary: "FusionBegin tier was not requested"
                    )
                )
            ]
        )
    }

    @Test("Round engine rejects FusionBegin tiers absent from ServerHello")
    func validateFusionBeginTierMustBeAdvertised() {
        var engine = Self.makeEngine()
        _ = engine.apply(input: .primaryConnected, now: Self.instant(995))
        _ = engine.apply(
            input: .primaryMessage(
                .serverHello(
                    .init(
                        tiers: [20_000],
                        numberOfComponents: Self.serverHello.numberOfComponents,
                        componentFeeRateSatoshisPerKb: Self.serverHello.componentFeeRateSatoshisPerKb,
                        minimumExcessFeeSatoshis: Self.serverHello.minimumExcessFeeSatoshis,
                        maximumExcessFeeSatoshis: Self.serverHello.maximumExcessFeeSatoshis,
                        donationAddress: Self.serverHello.donationAddress
                    )
                )
            ),
            now: Self.instant(996)
        )

        let effects = engine.apply(
            input: .primaryMessage(.fusionBegin(Self.fusionBegin)),
            now: Self.instant(1_000)
        )

        #expect(engine.session.lastError == .protocolIncompatible)
        #expect(engine.round == nil)
        #expect(
            effects == [
                .emitHostEvent(
                    roundIdentifier: nil,
                    event: .init(
                        kind: .failure,
                        phase: .connecting,
                        summary: "FusionBegin tier was not advertised by ServerHello"
                    )
                )
            ]
        )
    }

    @Test("Round engine rejects FusionBegin covert ports outside the supported range")
    func validateFusionBeginCovertPortRange() {
        var engine = Self.makeEngine()
        _ = engine.apply(input: .primaryConnected, now: Self.instant(995))
        _ = engine.apply(
            input: .primaryMessage(.serverHello(Self.serverHello)),
            now: Self.instant(996)
        )

        let effects = engine.apply(
            input: .primaryMessage(
                .fusionBegin(
                    .init(
                        tier: Self.fusionBegin.tier,
                        covertDomain: Self.fusionBegin.covertDomain,
                        covertPort: 0,
                        covertSsl: Self.fusionBegin.covertSsl,
                        serverTimeUnixSeconds: Self.fusionBegin.serverTimeUnixSeconds
                    )
                )
            ),
            now: Self.instant(1_000)
        )

        #expect(engine.session.lastError == .protocolIncompatible)
        #expect(engine.round == nil)
        #expect(
            effects == [
                .emitHostEvent(
                    roundIdentifier: nil,
                    event: .init(
                        kind: .failure,
                        phase: .connecting,
                        summary: "FusionBegin covert port was outside the supported range"
                    )
                )
            ]
        )
    }

    @Test("Round engine rejects invalid FusionBegin covert domains")
    func validateFusionBeginCovertDomain() {
        var engine = Self.makeEngine()
        _ = engine.apply(input: .primaryConnected, now: Self.instant(995))
        _ = engine.apply(
            input: .primaryMessage(.serverHello(Self.serverHello)),
            now: Self.instant(996)
        )

        let effects = engine.apply(
            input: .primaryMessage(
                .fusionBegin(
                    .init(
                        tier: Self.fusionBegin.tier,
                        covertDomain: "https://covert.example.org",
                        covertPort: Self.fusionBegin.covertPort,
                        covertSsl: Self.fusionBegin.covertSsl,
                        serverTimeUnixSeconds: Self.fusionBegin.serverTimeUnixSeconds
                    )
                )
            ),
            now: Self.instant(1_000)
        )

        #expect(engine.session.lastError == .protocolIncompatible)
        #expect(engine.round == nil)
        #expect(
            effects == [
                .emitHostEvent(
                    roundIdentifier: nil,
                    event: .init(
                        kind: .failure,
                        phase: .connecting,
                        summary: "FusionBegin covert domain was invalid"
                    )
                )
            ]
        )
    }

    @Test("Round engine rejects malformed FusionBegin covert DNS labels")
    func validateFusionBeginMalformedCovertDNSLabel() {
        var engine = Self.makeEngine()
        _ = engine.apply(input: .primaryConnected, now: Self.instant(995))
        _ = engine.apply(
            input: .primaryMessage(.serverHello(Self.serverHello)),
            now: Self.instant(996)
        )

        let effects = engine.apply(
            input: .primaryMessage(
                .fusionBegin(
                    .init(
                        tier: Self.fusionBegin.tier,
                        covertDomain: "-covert.example.org",
                        covertPort: Self.fusionBegin.covertPort,
                        covertSsl: Self.fusionBegin.covertSsl,
                        serverTimeUnixSeconds: Self.fusionBegin.serverTimeUnixSeconds
                    )
                )
            ),
            now: Self.instant(1_000)
        )

        #expect(engine.session.lastError == .protocolIncompatible)
        #expect(engine.round == nil)
        #expect(
            effects == [
                .emitHostEvent(
                    roundIdentifier: nil,
                    event: .init(
                        kind: .failure,
                        phase: .connecting,
                        summary: "FusionBegin covert domain was invalid"
                    )
                )
            ]
        )
    }

    @Test("Round engine rejects unrepresentable FusionBegin server times without trapping")
    func validateFusionBeginServerTimeRange() {
        var engine = Self.makeEngine()
        _ = engine.apply(input: .primaryConnected, now: Self.instant(995))
        _ = engine.apply(
            input: .primaryMessage(.serverHello(Self.serverHello)),
            now: Self.instant(996)
        )

        let effects = engine.apply(
            input: .primaryMessage(
                .fusionBegin(
                    .init(
                        tier: Self.fusionBegin.tier,
                        covertDomain: Self.fusionBegin.covertDomain,
                        covertPort: Self.fusionBegin.covertPort,
                        covertSsl: Self.fusionBegin.covertSsl,
                        serverTimeUnixSeconds: UInt64.max
                    )
                )
            ),
            now: Self.instant(1_000)
        )

        #expect(engine.session.lastError == .protocolIncompatible)
        #expect(engine.round == nil)
        #expect(
            effects == [
                .emitHostEvent(
                    roundIdentifier: nil,
                    event: .init(
                        kind: .failure,
                        phase: .connecting,
                        summary: "FusionBegin server time exceeded the allowed clock skew"
                    )
                )
            ]
        )
    }

    @Test("Round engine rejects extreme clock skew distances without trapping")
    func validateFusionBeginExtremeClockSkewDistance() {
        var engine = Self.makeEngine()
        _ = engine.apply(
            input: .primaryConnected,
            now: .init(millisecondsSinceUnixEpoch: Int64.min)
        )
        _ = engine.apply(
            input: .primaryMessage(.serverHello(Self.serverHello)),
            now: .init(millisecondsSinceUnixEpoch: Int64.min)
        )

        let effects = engine.apply(
            input: .primaryMessage(
                .fusionBegin(
                    .init(
                        tier: Self.fusionBegin.tier,
                        covertDomain: Self.fusionBegin.covertDomain,
                        covertPort: Self.fusionBegin.covertPort,
                        covertSsl: Self.fusionBegin.covertSsl,
                        serverTimeUnixSeconds: UInt64(Int64.max / 1_000)
                    )
                )
            ),
            now: .init(millisecondsSinceUnixEpoch: Int64.min)
        )

        #expect(engine.session.lastError == .protocolIncompatible)
        #expect(engine.round == nil)
        #expect(
            effects == [
                .emitHostEvent(
                    roundIdentifier: nil,
                    event: .init(
                        kind: .failure,
                        phase: .connecting,
                        summary: "FusionBegin server time exceeded the allowed clock skew"
                    )
                )
            ]
        )
    }

    @Test("Round engine rejects StartRound blind nonce count mismatches")
    func validateStartRoundBlindNonceCount() {
        var engine = Self.makeEngine()
        _ = engine.apply(input: .primaryConnected, now: Self.instant(995))
        _ = engine.apply(
            input: .primaryMessage(.serverHello(Self.serverHello)),
            now: Self.instant(996)
        )
        _ = engine.apply(
            input: .primaryMessage(.fusionBegin(Self.fusionBegin)),
            now: Self.instant(1_000)
        )

        let effects = engine.apply(
            input: .primaryMessage(
                .startRound(
                    .init(
                        roundPublicKey: Self.startRound.roundPublicKey,
                        blindNoncePoints: [[0x01, 0x02]],
                        serverTimeUnixSeconds: Self.startRound.serverTimeUnixSeconds
                    )
                )
            ),
            now: Self.instant(1_030)
        )

        #expect(engine.session.lastError == .protocolIncompatible)
        #expect(engine.round?.substate == .terminal)
        #expect(engine.round?.completionStatus == .protocolIncompatible)
        #expect(engine.clientState.round == nil)
        #expect(
            effects == [
                .emitHostEvent(
                    roundIdentifier: nil,
                    event: .init(
                        kind: .failure,
                        phase: .completed,
                        summary: "StartRound blind nonce count did not match ServerHello component count",
                        isTerminal: true
                    )
                )
            ]
        )
    }

    @Test("Round engine rejects StartRound messages without a round public key")
    func validateStartRoundRoundPublicKeyPresence() {
        var engine = Self.makeEngine()
        _ = engine.apply(input: .primaryConnected, now: Self.instant(995))
        _ = engine.apply(
            input: .primaryMessage(.serverHello(Self.serverHello)),
            now: Self.instant(996)
        )
        _ = engine.apply(
            input: .primaryMessage(.fusionBegin(Self.fusionBegin)),
            now: Self.instant(1_000)
        )

        let effects = engine.apply(
            input: .primaryMessage(
                .startRound(
                    .init(
                        roundPublicKey: [],
                        blindNoncePoints: Self.startRound.blindNoncePoints,
                        serverTimeUnixSeconds: Self.startRound.serverTimeUnixSeconds
                    )
                )
            ),
            now: Self.instant(1_030)
        )

        #expect(engine.session.lastError == .protocolIncompatible)
        #expect(engine.round?.substate == .terminal)
        #expect(engine.round?.completionStatus == .protocolIncompatible)
        #expect(engine.clientState.round == nil)
        #expect(
            effects == [
                .emitHostEvent(
                    roundIdentifier: nil,
                    event: .init(
                        kind: .failure,
                        phase: .completed,
                        summary: "StartRound round public key was missing",
                        isTerminal: true
                    )
                )
            ]
        )
    }

    @Test("Round engine rejects StartRound messages with missing blind nonce points")
    func validateStartRoundBlindNoncePointPresence() {
        var engine = Self.makeEngine()
        _ = engine.apply(input: .primaryConnected, now: Self.instant(995))
        _ = engine.apply(
            input: .primaryMessage(.serverHello(Self.serverHello)),
            now: Self.instant(996)
        )
        _ = engine.apply(
            input: .primaryMessage(.fusionBegin(Self.fusionBegin)),
            now: Self.instant(1_000)
        )

        var blindNoncePoints = Self.startRound.blindNoncePoints
        blindNoncePoints[1] = []
        let effects = engine.apply(
            input: .primaryMessage(
                .startRound(
                    .init(
                        roundPublicKey: Self.startRound.roundPublicKey,
                        blindNoncePoints: blindNoncePoints,
                        serverTimeUnixSeconds: Self.startRound.serverTimeUnixSeconds
                    )
                )
            ),
            now: Self.instant(1_030)
        )

        #expect(engine.session.lastError == .protocolIncompatible)
        #expect(engine.round?.substate == .terminal)
        #expect(engine.round?.completionStatus == .protocolIncompatible)
        #expect(engine.clientState.round == nil)
        #expect(
            effects == [
                .emitHostEvent(
                    roundIdentifier: nil,
                    event: .init(
                        kind: .failure,
                        phase: .completed,
                        summary: "StartRound blind nonce point was missing",
                        isTerminal: true
                    )
                )
            ]
        )
    }

    @Test("Round engine clears warmup round after pre-StartRound covert failure")
    func validateWarmupCovertFailureClearsRound() {
        var engine = Self.makeEngine()
        _ = engine.apply(input: .primaryConnected, now: Self.instant(995))
        _ = engine.apply(
            input: .primaryMessage(.serverHello(Self.serverHello)),
            now: Self.instant(996)
        )
        _ = engine.apply(
            input: .primaryMessage(.fusionBegin(Self.fusionBegin)),
            now: Self.instant(1_000)
        )

        let failureEffects = engine.apply(
            input: .covertTransportFailed(summary: "Covert endpoint preparation failed"),
            now: Self.instant(1_001)
        )
        #expect(engine.round == nil)
        #expect(engine.session.lastError == .transportUnavailable)
        #expect(
            failureEffects == [
                .emitHostEvent(
                    roundIdentifier: nil,
                    event: .init(
                        kind: .failure,
                        phase: .connecting,
                        summary: "Covert endpoint preparation failed"
                    )
                )
            ]
        )

        let staleStartRoundEffects = engine.apply(
            input: .primaryMessage(.startRound(Self.startRound)),
            now: Self.instant(1_030)
        )
        #expect(staleStartRoundEffects.isEmpty)
        #expect(engine.clientState.round == nil)
    }

    @Test("Round engine ignores primary messages after terminal completion")
    func validateTerminalRoundIgnoresLatePrimaryMessages() {
        var engine = Self.makeEngine()
        Self.driveToSignatureSubmission(engine: &engine)

        _ = engine.apply(
            input: .primaryMessage(.fusionResult(Self.successResult)),
            now: Self.instant(1_061)
        )
        #expect(engine.clientState.round?.completionStatus == .success)

        let lateEffects = engine.apply(
            input: .primaryMessage(
                .serverFailure(.init(message: "late failure"))
            ),
            now: Self.instant(1_062)
        )

        #expect(lateEffects.isEmpty)
        #expect(engine.clientState.round?.completionStatus == .success)
        #expect(engine.session.lastError == nil)
    }

    @Test("Round engine preserves terminal success after clean primary disconnect")
    func validateTerminalRoundKeepsSuccessAfterPrimaryDisconnect() {
        var engine = Self.makeEngine()
        Self.driveToSignatureSubmission(engine: &engine)

        _ = engine.apply(
            input: .primaryMessage(.fusionResult(Self.successResult)),
            now: Self.instant(1_061)
        )
        #expect(engine.clientState.round?.completionStatus == .success)

        let disconnectEffects = engine.apply(
            input: .primaryDisconnected,
            now: Self.instant(1_062)
        )

        #expect(disconnectEffects.isEmpty)
        #expect(engine.clientState.isConnected == false)
        #expect(engine.clientState.round?.completionStatus == .success)
        #expect(engine.session.lastError == nil)
    }

    @Test("Round engine preserves terminal success after primary transport failure noise")
    func validateTerminalRoundKeepsSuccessAfterPrimaryTransportFailure() {
        var engine = Self.makeEngine()
        Self.driveToSignatureSubmission(engine: &engine)

        _ = engine.apply(
            input: .primaryMessage(.fusionResult(Self.successResult)),
            now: Self.instant(1_061)
        )
        #expect(engine.clientState.round?.completionStatus == .success)

        let failureEffects = engine.apply(
            input: .primaryTransportFailed(summary: "Primary read failed after result"),
            now: Self.instant(1_062)
        )

        #expect(failureEffects.isEmpty)
        #expect(engine.clientState.isConnected == false)
        #expect(engine.clientState.round?.completionStatus == .success)
        #expect(engine.session.lastError == nil)
    }

    @Test("Round engine preserves terminal success after covert transport failure noise")
    func validateTerminalRoundKeepsSuccessAfterCovertTransportFailure() {
        var engine = Self.makeEngine()
        Self.driveToSignatureSubmission(engine: &engine)

        _ = engine.apply(
            input: .primaryMessage(.fusionResult(Self.successResult)),
            now: Self.instant(1_061)
        )
        #expect(engine.clientState.round?.completionStatus == .success)

        let failureEffects = engine.apply(
            input: .covertTransportFailed(summary: "Covert request failed after result"),
            now: Self.instant(1_062)
        )

        #expect(failureEffects.isEmpty)
        #expect(engine.clientState.round?.completionStatus == .success)
        #expect(engine.session.lastError == nil)
    }

    @Test("Round engine preserves terminal success after covert server failure noise")
    func validateTerminalRoundKeepsSuccessAfterCovertServerFailure() {
        var engine = Self.makeEngine()
        Self.driveToSignatureSubmission(engine: &engine)

        _ = engine.apply(
            input: .primaryMessage(.fusionResult(Self.successResult)),
            now: Self.instant(1_061)
        )
        #expect(engine.clientState.round?.completionStatus == .success)

        let failureEffects = engine.apply(
            input: .covertResponse(
                .serverFailure(.init(message: "late covert failure"))
            ),
            now: Self.instant(1_062)
        )

        #expect(failureEffects.isEmpty)
        #expect(engine.clientState.round?.completionStatus == .success)
        #expect(engine.session.lastError == nil)
    }

    @Test("Round engine preserves terminal success after transaction finalization rejection noise")
    func validateTerminalRoundKeepsSuccessAfterTransactionFinalizationRejection() {
        var engine = Self.makeEngine()
        Self.driveToSignatureSubmission(engine: &engine)

        _ = engine.apply(
            input: .primaryMessage(.fusionResult(Self.successResult)),
            now: Self.instant(1_061)
        )
        #expect(engine.clientState.round?.completionStatus == .success)

        let rejectionEffects = engine.apply(
            input: .transactionFinalizationRejected(
                .hostPolicyRejected(summary: "Late host policy rejection")
            ),
            now: Self.instant(1_062)
        )

        #expect(rejectionEffects.isEmpty)
        #expect(engine.clientState.round?.completionStatus == .success)
        #expect(engine.session.lastError == nil)
    }

    @Test("Round engine maps transaction assembly failures to not implemented")
    func validateTransactionAssemblyFailureMapping() {
        var engine = Self.makeEngine()
        Self.driveToSharedComponents(engine: &engine)
        let summary = "Assembler could not produce a finalized transaction"

        let effects = engine.apply(
            input: .transactionFinalizationRejected(
                .transactionAssemblyFailed(summary: summary)
            ),
            now: Self.instant(1_042)
        )

        #expect(
            effects == [
                .emitHostEvent(
                    roundIdentifier: Self.roundIdentifier,
                    event: .init(
                        kind: .failure,
                        phase: .completed,
                        summary: summary,
                        isTerminal: true
                    )
                )
            ]
        )
        #expect(engine.session.lastError == .notImplemented)
        #expect(engine.session.lastErrorSummary == summary)
        #expect(engine.clientState.round?.completionStatus == .hostRejected)
    }

    @Test("Round engine maps host policy finalization failures to host rejected")
    func validateHostPolicyFinalizationFailureMapping() {
        var engine = Self.makeEngine()
        Self.driveToSharedComponents(engine: &engine)
        let summary = "Host policy rejected coordinator input order"

        let effects = engine.apply(
            input: .transactionFinalizationRejected(
                .hostPolicyRejected(summary: summary)
            ),
            now: Self.instant(1_042)
        )

        #expect(
            effects == [
                .emitHostEvent(
                    roundIdentifier: Self.roundIdentifier,
                    event: .init(
                        kind: .failure,
                        phase: .completed,
                        summary: summary,
                        isTerminal: true
                    )
                )
            ]
        )
        #expect(engine.session.lastError == .hostRejected)
        #expect(engine.session.lastErrorSummary == summary)
        #expect(engine.clientState.round?.completionStatus == .hostRejected)
    }

    @Test("Round engine preserves terminal success after participant reservation rejection noise")
    func validateTerminalRoundKeepsSuccessAfterParticipantReservationRejection() {
        var engine = Self.makeEngine()
        Self.driveToSignatureSubmission(engine: &engine)

        _ = engine.apply(
            input: .primaryMessage(.fusionResult(Self.successResult)),
            now: Self.instant(1_061)
        )
        #expect(engine.clientState.round?.completionStatus == .success)

        let rejectionEffects = engine.apply(
            input: .participantReservationRejected,
            now: Self.instant(1_062)
        )

        #expect(rejectionEffects.isEmpty)
        #expect(engine.clientState.round?.completionStatus == .success)
        #expect(engine.session.lastError == nil)
    }

    @Test("Round engine preserves terminal success after participant reservation noise")
    func validateTerminalRoundKeepsSuccessAfterParticipantReservation() {
        var engine = Self.makeEngine()
        Self.driveToSignatureSubmission(engine: &engine)

        _ = engine.apply(
            input: .primaryMessage(.fusionResult(Self.successResult)),
            now: Self.instant(1_061)
        )
        #expect(engine.clientState.round?.completionStatus == .success)

        let loadedEffects = engine.apply(
            input: .participantReservationLoaded(Self.participantReservation),
            now: Self.instant(1_062)
        )

        #expect(loadedEffects.isEmpty)
        #expect(engine.clientState.round?.completionStatus == .success)
        #expect(engine.session.lastError == nil)
    }

    @Test("Round engine preserves terminal success after finalized transaction noise")
    func validateTerminalRoundKeepsSuccessAfterFinalizedTransaction() {
        var engine = Self.makeEngine()
        Self.driveToSignatureSubmission(engine: &engine)

        _ = engine.apply(
            input: .primaryMessage(.fusionResult(Self.successResult)),
            now: Self.instant(1_061)
        )
        #expect(engine.clientState.round?.completionStatus == .success)

        let loadedEffects = engine.apply(
            input: .finalizedTransactionLoaded(Self.finalizedTransaction),
            now: Self.instant(1_062)
        )

        #expect(loadedEffects.isEmpty)
        #expect(engine.clientState.round?.completionStatus == .success)
        #expect(engine.session.lastError == nil)
    }

    @Test("Round engine preserves terminal success after protocol rejection noise")
    func validateTerminalRoundKeepsSuccessAfterProtocolRejection() {
        var engine = Self.makeEngine()
        Self.driveToSignatureSubmission(engine: &engine)

        _ = engine.apply(
            input: .primaryMessage(.fusionResult(Self.successResult)),
            now: Self.instant(1_061)
        )
        #expect(engine.clientState.round?.completionStatus == .success)

        let rejectionEffects = engine.apply(
            input: .protocolRejected(summary: "Trailing primary bytes were malformed"),
            now: Self.instant(1_062)
        )

        #expect(rejectionEffects.isEmpty)
        #expect(engine.clientState.round?.completionStatus == .success)
        #expect(engine.session.lastError == nil)
    }
}

private extension RoundEngineScriptedValidator {
    static var roundIdentifier: OpalFusion.Round.Identifier {
        .init(rawValue: "aabb")
    }

    static var configuration: OpalFusion.Client.Configuration {
        .init(
            coordinatorHost: "fusion.example.org",
            coordinatorPort: 8_787,
            covertChannel: .init(
                entryPath: "/fusion",
                maxPayloadBytes: 32_768,
                requestTimeoutMilliseconds: 15_000
            )
        )
    }

    static var closeStartReachableBaseline: OpalFusion.Transport.BaselineConfiguration {
        let baseline = OpalFusion.Transport.BaselineConfiguration.electronCash443
        return .init(
            protocolIdentity: baseline.protocolIdentity,
            framing: baseline.framing,
            covertTiming: baseline.covertTiming,
            roundTiming: .init(
                maximumClockDiscrepancy: baseline.roundTiming.maximumClockDiscrepancy,
                warmupDuration: baseline.roundTiming.warmupDuration,
                warmupSlop: baseline.roundTiming.warmupSlop,
                commitmentsDeadlineFromRoundStart: baseline.roundTiming.commitmentsDeadlineFromRoundStart,
                covertComponentsStartFromRoundStart: baseline.roundTiming.covertComponentsStartFromRoundStart,
                covertComponentsDeadlineFromRoundStart: baseline.roundTiming.covertComponentsDeadlineFromRoundStart,
                signaturesStartFromRoundStart: baseline.roundTiming.signaturesStartFromRoundStart,
                signaturesDeadlineFromRoundStart: baseline.roundTiming.signaturesDeadlineFromRoundStart,
                conclusionTimeoutFromRoundStart: .seconds(90),
                closeStartFromRoundStart: baseline.roundTiming.closeStartFromRoundStart,
                blameCloseStartFromRoundStart: baseline.roundTiming.blameCloseStartFromRoundStart,
                standardTimeout: baseline.roundTiming.standardTimeout,
                blameVerifyDuration: baseline.roundTiming.blameVerifyDuration
            )
        )
    }

    static var joinPools: OpalFusion.ProtocolModel.JoinPools {
        .init(
            tiers: [10_000],
            tags: [
                .init(
                    identifier: [0x01, 0x02, 0x03],
                    limit: 1,
                    noIp: true
                )
            ]
        )
    }

    static var clientHello: OpalFusion.ProtocolModel.ClientHello {
        .init(
            versionBytes: OpalFusion.Transport.BaselineConfiguration.electronCash443.protocolIdentity.versionBytes,
            genesisHash: [0xAA, 0xBB, 0xCC]
        )
    }

    static var serverHello: OpalFusion.ProtocolModel.ServerHello {
        .init(
            tiers: [10_000],
            numberOfComponents: 4,
            componentFeeRateSatoshisPerKb: 1_000,
            minimumExcessFeeSatoshis: 200,
            maximumExcessFeeSatoshis: 500,
            donationAddress: "bitcoincash:qexample"
        )
    }

    static var fusionBegin: OpalFusion.ProtocolModel.FusionBegin {
        .init(
            tier: 10_000,
            covertDomain: "covert.example.org",
            covertPort: 7_447,
            covertSsl: true,
            serverTimeUnixSeconds: 1_000
        )
    }

    static var startRound: OpalFusion.ProtocolModel.StartRound {
        .init(
            roundPublicKey: [0xAA, 0xBB],
            blindNoncePoints: [[0x01, 0x02], [0x03, 0x04], [0x05, 0x06], [0x07, 0x08]],
            serverTimeUnixSeconds: 1_030
        )
    }

    static var participantReservationContext: OpalFusion.Host.ParticipantReservationContext {
        .init(
            roundIdentifier: roundIdentifier,
            tierSatoshis: fusionBegin.tier,
            numberOfComponents: serverHello.numberOfComponents,
            componentFeeRateSatoshisPerKb: serverHello.componentFeeRateSatoshisPerKb,
            minimumExcessFeeSatoshis: serverHello.minimumExcessFeeSatoshis,
            maximumExcessFeeSatoshis: serverHello.maximumExcessFeeSatoshis
        )
    }

    static var participantInput: OpalFusion.Host.ParticipantInput {
        .init(
            outpointTransactionHashBytes: [0x10, 0x11],
            outpointIndex: 0,
            amountSatoshis: 50_000,
            lockingScriptBytes: [0x51],
            publicKey: [0x02, 0x10, 0x11]
        )
    }

    static var participantOutput: OpalFusion.Host.ParticipantOutput {
        .init(
            lockingScriptBytes: [0x76, 0xA9, 0x14, 0x01, 0x88, 0xAC],
            amountSatoshis: 49_000
        )
    }

    static var participantReservation: OpalFusion.Host.ParticipantReservation {
        .init(
            inputs: [participantInput],
            outputs: [participantOutput]
        )
    }

    static var initialCommitment: OpalFusion.Commitment.InitialCommitment {
        .init(
            saltedComponentHash: [0x21],
            amountCommitment: [0x22],
            communicationPublicKey: [0x23]
        )
    }

    static var playerCommit: OpalFusion.ProtocolModel.PlayerCommit {
        .init(
            initialCommitments: [initialCommitment],
            excessFeeSatoshis: 250,
            pedersenTotalNonce: [0x24],
            randomNumberCommitment: [0x25],
            blindSignatureRequests: [.init(scalar: [0x26])]
        )
    }

    static var blindSignatureResponses: OpalFusion.ProtocolModel.BlindSignatureResponses {
        .init(
            responses: [.init(scalar: [0x27])]
        )
    }

    static var allCommitments: OpalFusion.ProtocolModel.AllCommitments {
        .init(
            initialCommitments: [initialCommitment]
        )
    }

    static var covertComponentMessage: OpalFusion.ProtocolModel.CovertMessage {
        .component(
            .init(
                roundPublicKey: [0xAA, 0xBB],
                signature: [0x30],
                serializedComponent: [0x31]
            )
        )
    }

    static var covertEndpointContext: OpalFusion.Runtime.CovertEndpointContext {
        .init(
            roundIdentifier: nil,
            host: fusionBegin.covertDomain,
            port: fusionBegin.covertPort,
            requiresTLS: fusionBegin.covertSsl,
            entryPath: configuration.covertChannel.entryPath,
            maxPayloadBytes: configuration.covertChannel.maxPayloadBytes,
            requestTimeoutMilliseconds: configuration.covertChannel.requestTimeoutMilliseconds,
            connectTimeout: OpalFusion.Transport.BaselineConfiguration.electronCash443.covertTiming.connectTimeout,
            connectWindow: OpalFusion.Transport.BaselineConfiguration.electronCash443.covertTiming.connectWindow,
            submitTimeout: OpalFusion.Transport.BaselineConfiguration.electronCash443.covertTiming.submitTimeout,
            submitWindow: OpalFusion.Transport.BaselineConfiguration.electronCash443.covertTiming.submitWindow,
            spareConnectionCount: OpalFusion.Transport.BaselineConfiguration.electronCash443.covertTiming.spareConnectionCount
        )
    }

    static var sharedComponents: OpalFusion.ProtocolModel.ShareCovertComponents {
        .init(
            serializedComponents: [[0x40]],
            skipSignatures: false,
            sessionHash: [0x41]
        )
    }

    static var transactionProposal: OpalFusion.Host.TransactionFinalizationProposal {
        .init(
            unsignedTransactionBytes: [0x50],
            sessionHash: [0x41],
            expectedInputCount: 1,
            expectedOutputCount: 2,
            participantCount: nil
        )
    }

    static var finalizedTransaction: OpalFusion.Host.FinalizedTransaction {
        .init(transactionBytes: [0x60])
    }

    static var signatureMessage: OpalFusion.ProtocolModel.CovertMessage {
        .transactionSignature(
            .init(
                roundPublicKey: [0xAA, 0xBB],
                inputIndex: 0,
                transactionSignature: [0x61]
            )
        )
    }

    static var successResult: OpalFusion.ProtocolModel.FusionResult {
        .init(
            isSuccess: true,
            transactionSignatures: [[0x70]],
            badComponentIndices: []
        )
    }

    static var failureResult: OpalFusion.ProtocolModel.FusionResult {
        .init(
            isSuccess: false,
            transactionSignatures: [],
            badComponentIndices: [0]
        )
    }

    static var myProofsList: OpalFusion.ProtocolModel.MyProofsList {
        .init(
            encryptedProofs: [[0x80]],
            randomNumber: [0x81]
        )
    }

    static var theirProofsList: OpalFusion.ProtocolModel.TheirProofsList {
        .init(
            proofs: [
                .init(
                    encryptedProof: [0x82],
                    sourceCommitmentIndex: 0,
                    destinationKeyIndex: 0
                )
            ]
        )
    }

    static var blames: OpalFusion.ProtocolModel.Blames {
        .init(
            blames: [
                .init(
                    proofIndex: 0,
                    decrypter: .sessionKey([0x83]),
                    requiresBlockchainLookup: false,
                    reason: "invalid component"
                )
            ]
        )
    }

    static func makeEngine(
        baseline: OpalFusion.Transport.BaselineConfiguration = .electronCash443
    ) -> OpalFusion.Execution.RoundEngine {
        .init(
            configuration: configuration,
            genesisHash: [0xAA, 0xBB, 0xCC],
            joinPools: joinPools,
            workflow: .init(
                buildPlayerCommit: { _ in playerCommit },
                buildCovertComponentMessages: { _ in [covertComponentMessage] },
                buildTransactionFinalizationProposal: { _ in transactionProposal },
                buildCovertSignatureMessages: { _ in [signatureMessage] },
                buildMyProofsList: { _ in myProofsList },
                buildBlames: { _ in blames }
            ),
            baseline: baseline
        )
    }

    static func instant(_ unixSeconds: UInt64) -> OpalFusion.Execution.Instant {
        .init(unixSeconds: unixSeconds)
    }

    static func driveThroughStartRound(
        engine: inout OpalFusion.Execution.RoundEngine
    ) {
        _ = engine.apply(input: .primaryConnected, now: instant(995))
        _ = engine.apply(input: .primaryMessage(.serverHello(serverHello)), now: instant(996))
        _ = engine.apply(input: .primaryMessage(.fusionBegin(fusionBegin)), now: instant(1_000))
        _ = engine.apply(input: .primaryMessage(.startRound(startRound)), now: instant(1_030))
    }

    static func driveToSharedComponents(
        engine: inout OpalFusion.Execution.RoundEngine
    ) {
        driveThroughStartRound(engine: &engine)
        _ = engine.apply(
            input: .participantReservationLoaded(participantReservation),
            now: instant(1_031)
        )
        _ = engine.apply(
            input: .primaryMessage(.blindSignatureResponses(blindSignatureResponses)),
            now: instant(1_032)
        )
        _ = engine.apply(
            input: .primaryMessage(.allCommitments(allCommitments)),
            now: instant(1_034)
        )
        _ = engine.apply(input: .clockAdvanced, now: instant(1_035))
        _ = engine.apply(
            input: .primaryMessage(.shareCovertComponents(sharedComponents)),
            now: instant(1_040)
        )
    }

    static func driveToSignatureSubmission(
        engine: inout OpalFusion.Execution.RoundEngine
    ) {
        driveToSharedComponents(engine: &engine)
        _ = engine.apply(
            input: .finalizedTransactionLoaded(finalizedTransaction),
            now: instant(1_042)
        )
        _ = engine.apply(input: .clockAdvanced, now: instant(1_050))
    }
}

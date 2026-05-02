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
                .requestParticipantReservation(roundIdentifier: roundIdentifier),
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
        #expect(engine.clientState.isConnected == true)

        let transportEffects = engine.apply(
            input: .primaryTransportFailed(
                summary: "Primary read failed: primaryConnectionCancelled"
            ),
            now: Self.instant(998)
        )
        #expect(transportEffects.isEmpty)
        #expect(engine.session.lastError == .coordinatorRejected)
        #expect(engine.session.lastErrorSummary == rejectionSummary)
        #expect(engine.clientState.isConnected == false)
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
            input: .transactionFinalizationRejected,
            now: Self.instant(1_062)
        )

        #expect(rejectionEffects.isEmpty)
        #expect(engine.clientState.round?.completionStatus == .success)
        #expect(engine.session.lastError == nil)
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
            blindNoncePoints: [[0x01, 0x02]],
            serverTimeUnixSeconds: 1_030
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

    static func makeEngine() -> OpalFusion.Execution.RoundEngine {
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
            )
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

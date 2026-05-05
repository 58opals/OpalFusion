// PrimaryRuntimeSessionValidator.swift

@testable import OpalFusion
import Testing

struct PrimaryRuntimeSessionValidator {
    @Test("Primary runtime writes framed ClientHello and JoinPools during handshake")
    func validateHandshakeFlow() throws {
        var session = PrimaryRuntimeTestFixtures.makeSession()

        let connectEffects = session.apply(
            input: .connected,
            now: PrimaryRuntimeTestFixtures.instant(995)
        )
        #expect(connectEffects.count == 2)
        #expect(
            try PrimaryRuntimeTestFixtures.extractWriteMessage(from: connectEffects[0])
                == .clientHello(PrimaryRuntimeTestFixtures.clientHello)
        )
        #expect(
            connectEffects[1] == .emitHostEvent(
                roundIdentifier: nil,
                event: .init(
                    kind: .status,
                    phase: .connecting,
                    summary: "Primary channel connected; sending ClientHello"
                )
            )
        )

        let helloEffects = session.apply(
            input: .receivedPrimaryBytes(
                try PrimaryRuntimeTestFixtures.encodeServerFrame(
                    .serverHello(PrimaryRuntimeTestFixtures.serverHello)
                )
            ),
            now: PrimaryRuntimeTestFixtures.instant(996)
        )
        #expect(helloEffects.count == 2)
        #expect(
            try PrimaryRuntimeTestFixtures.extractWriteMessage(from: helloEffects[0])
                == .joinPools(PrimaryRuntimeTestFixtures.joinPools)
        )
        #expect(
            helloEffects[1] == .emitHostEvent(
                roundIdentifier: nil,
                event: .init(
                    kind: .status,
                    phase: .connecting,
                    summary: "ServerHello received; joining eligible pools"
                )
            )
        )
        #expect(session.clientState.isConnected)
        #expect(session.clientState.round == nil)
    }

    @Test("Primary runtime triggers covert preparation during FusionBegin warmup")
    func validateWarmupPreparation() throws {
        var session = PrimaryRuntimeTestFixtures.makeSession()
        _ = session.apply(input: .connected, now: PrimaryRuntimeTestFixtures.instant(995))
        _ = session.apply(
            input: .receivedPrimaryBytes(
                try PrimaryRuntimeTestFixtures.encodeServerFrame(
                    .serverHello(PrimaryRuntimeTestFixtures.serverHello)
                )
            ),
            now: PrimaryRuntimeTestFixtures.instant(996)
        )

        let effects = session.apply(
            input: .receivedPrimaryBytes(
                try PrimaryRuntimeTestFixtures.encodeServerFrame(
                    .fusionBegin(PrimaryRuntimeTestFixtures.fusionBegin)
                )
            ),
            now: PrimaryRuntimeTestFixtures.instant(1_000)
        )

        #expect(
            effects == [
                .prepareCovertEndpoint(
                    plan: PrimaryRuntimeTestFixtures.expectedPreparationPlan(startedAt: 1_000)
                ),
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
        #expect(session.covertSession.substate == .preparing)
        #expect(session.covertSession.endpointContext == PrimaryRuntimeTestFixtures.covertEndpointContext)
    }

    @Test("Primary runtime keeps ServerHello context when the primary channel disconnects before FusionBegin")
    func validateDisconnectAfterServerHelloBeforeFusionBegin() throws {
        var session = PrimaryRuntimeTestFixtures.makeSession()
        _ = session.apply(input: .connected, now: PrimaryRuntimeTestFixtures.instant(995))
        _ = session.apply(
            input: .receivedPrimaryBytes(
                try PrimaryRuntimeTestFixtures.encodeServerFrame(
                    .serverHello(PrimaryRuntimeTestFixtures.serverHello)
                )
            ),
            now: PrimaryRuntimeTestFixtures.instant(996)
        )

        let effects = session.apply(
            input: .disconnected,
            now: PrimaryRuntimeTestFixtures.instant(997)
        )

        #expect(
            effects == [
                .emitHostEvent(
                    roundIdentifier: nil,
                    event: .init(
                        kind: .failure,
                        phase: .connecting,
                        summary: "Primary channel disconnected"
                    )
                )
            ]
        )
        #expect(session.engine.session.latestServerHello == PrimaryRuntimeTestFixtures.serverHello)
        #expect(session.clientState.round == nil)
        #expect(session.lastError == .transportUnavailable)
        #expect(session.lastErrorSummary == "Primary channel disconnected")
    }

    @Test("Primary runtime drives framed StartRound input collection and PlayerCommit submission")
    func validateStartRoundAndCommitFlow() throws {
        var session = PrimaryRuntimeTestFixtures.makeSession()
        try PrimaryRuntimeTestFixtures.driveThroughWarmup(session: &session)

        let requestEffects = session.apply(
            input: .receivedPrimaryBytes(
                try PrimaryRuntimeTestFixtures.encodeServerFrame(
                    .startRound(PrimaryRuntimeTestFixtures.startRound)
                )
            ),
            now: PrimaryRuntimeTestFixtures.instant(1_030)
        )

        #expect(
            requestEffects == [
                .requestParticipantReservation(
                    roundIdentifier: PrimaryRuntimeTestFixtures.roundIdentifier
                ),
                .emitHostEvent(
                    roundIdentifier: PrimaryRuntimeTestFixtures.roundIdentifier,
                    event: .init(
                        kind: .status,
                        phase: .registeringInputs,
                        summary: "StartRound received; collecting reserved inputs and outputs"
                    )
                )
            ]
        )
        #expect(
            session.clientState.round == .init(
                identifier: PrimaryRuntimeTestFixtures.roundIdentifier,
                phase: .registeringInputs
            )
        )

        let commitEffects = session.apply(
            input: .participantReservationLoaded(
                PrimaryRuntimeTestFixtures.participantReservation
            ),
            now: PrimaryRuntimeTestFixtures.instant(1_031)
        )
        #expect(commitEffects.count == 2)
        #expect(
            try PrimaryRuntimeTestFixtures.extractWriteMessage(from: commitEffects[0])
                == .playerCommit(PrimaryRuntimeTestFixtures.playerCommit)
        )
        #expect(
            commitEffects[1] == .emitHostEvent(
                roundIdentifier: PrimaryRuntimeTestFixtures.roundIdentifier,
                event: .init(
                    kind: .status,
                    phase: .awaitingBlindSignatures,
                    summary: "Submitting player commitments and blind requests"
                )
            )
        )
        #expect(session.clientState.round?.phase == .awaitingBlindSignatures)
    }

    @Test("Primary runtime handles fragmented inbound frames without losing state projection")
    func validateFragmentedInboundFlow() throws {
        var session = PrimaryRuntimeTestFixtures.makeSession()
        _ = session.apply(input: .connected, now: PrimaryRuntimeTestFixtures.instant(995))

        let serverHelloFrame = try PrimaryRuntimeTestFixtures.encodeServerFrame(
            .serverHello(PrimaryRuntimeTestFixtures.serverHello)
        )
        let serverHelloSplit = serverHelloFrame.count / 2
        #expect(
            session.apply(
                input: .receivedPrimaryBytes(Array(serverHelloFrame[..<serverHelloSplit])),
                now: PrimaryRuntimeTestFixtures.instant(996)
            )
                .isEmpty
        )
        let helloEffects = session.apply(
            input: .receivedPrimaryBytes(Array(serverHelloFrame[serverHelloSplit...])),
            now: PrimaryRuntimeTestFixtures.instant(996)
        )
        #expect(
            try PrimaryRuntimeTestFixtures.extractWriteMessage(from: helloEffects[0])
                == .joinPools(PrimaryRuntimeTestFixtures.joinPools)
        )

        _ = session.apply(
            input: .receivedPrimaryBytes(
                try PrimaryRuntimeTestFixtures.encodeServerFrame(
                    .fusionBegin(PrimaryRuntimeTestFixtures.fusionBegin)
                )
            ),
            now: PrimaryRuntimeTestFixtures.instant(1_000)
        )

        let startRoundFrame = try PrimaryRuntimeTestFixtures.encodeServerFrame(
            .startRound(PrimaryRuntimeTestFixtures.startRound)
        )
        let firstCut = startRoundFrame.count / 3
        let secondCut = (startRoundFrame.count * 2) / 3

        #expect(
            session.apply(
                input: .receivedPrimaryBytes(Array(startRoundFrame[..<firstCut])),
                now: PrimaryRuntimeTestFixtures.instant(1_030)
            )
                .isEmpty
        )
        #expect(session.clientState.round == nil)
        #expect(
            session.apply(
                input: .receivedPrimaryBytes(Array(startRoundFrame[firstCut..<secondCut])),
                now: PrimaryRuntimeTestFixtures.instant(1_030)
            )
                .isEmpty
        )
        #expect(session.clientState.round == nil)

        let startRoundEffects = session.apply(
            input: .receivedPrimaryBytes(Array(startRoundFrame[secondCut...])),
            now: PrimaryRuntimeTestFixtures.instant(1_030)
        )
        #expect(
            startRoundEffects == [
                .requestParticipantReservation(
                    roundIdentifier: PrimaryRuntimeTestFixtures.roundIdentifier
                ),
                .emitHostEvent(
                    roundIdentifier: PrimaryRuntimeTestFixtures.roundIdentifier,
                    event: .init(
                        kind: .status,
                        phase: .registeringInputs,
                        summary: "StartRound received; collecting reserved inputs and outputs"
                    )
                )
            ]
        )
        #expect(
            session.clientState.round == .init(
                identifier: PrimaryRuntimeTestFixtures.roundIdentifier,
                phase: .registeringInputs
            )
        )
    }

    @Test("Primary runtime turns covert submission into a scripted covert request")
    func validateCovertSubmissionRequest() throws {
        var session = PrimaryRuntimeTestFixtures.makeSession()
        try PrimaryRuntimeTestFixtures.driveToAwaitingCovertSubmission(session: &session)
        PrimaryRuntimeTestFixtures.markCovertPrepared(session: &session)

        let effects = session.apply(
            input: .clockAdvanced,
            now: PrimaryRuntimeTestFixtures.instant(1_035)
        )

        let request = try PrimaryRuntimeTestFixtures.extractCovertRequest(from: effects[0])
        #expect(
            effects == [
                .performCovertRequest(
                    request: try PrimaryRuntimeTestFixtures.expectedRequest(
                        for: PrimaryRuntimeTestFixtures.covertComponentMessage,
                        startedAt: 1_035
                    )
                ),
                .emitHostEvent(
                    roundIdentifier: PrimaryRuntimeTestFixtures.roundIdentifier,
                    event: .init(
                        kind: .status,
                        phase: .awaitingCommitments,
                        summary: "Submitting covert components"
                    )
                )
            ]
        )
        #expect(
            try PrimaryRuntimeTestFixtures.extractCovertMessage(from: request)
                == PrimaryRuntimeTestFixtures.covertComponentMessage
        )
        #expect(session.covertSession.outstandingRequest == request)
    }

    @Test("Primary runtime advances after scripted covert acknowledgements")
    func validateCovertAcknowledgementAdvancement() throws {
        var session = PrimaryRuntimeTestFixtures.makeSession()
        try PrimaryRuntimeTestFixtures.driveToAwaitingCovertSubmission(session: &session)
        PrimaryRuntimeTestFixtures.markCovertPrepared(session: &session)
        _ = session.apply(
            input: .clockAdvanced,
            now: PrimaryRuntimeTestFixtures.instant(1_035)
        )

        let effects = session.apply(
            input: .receivedCovertResponseBytes(
                try PrimaryRuntimeTestFixtures.encodeCovertResponsePayload(
                    PrimaryRuntimeTestFixtures.acknowledgement
                )
            ),
            now: PrimaryRuntimeTestFixtures.instant(1_036)
        )

        #expect(effects.isEmpty)
        #expect(session.engine.round?.substate == .awaitingSharedComponents)
        #expect(session.covertSession.outstandingRequest == nil)
    }

    @Test("Primary runtime clears covert state on restart while keeping the primary session alive")
    func validateRestartClearsCovertState() throws {
        var session = PrimaryRuntimeTestFixtures.makeSession()
        try PrimaryRuntimeTestFixtures.driveToAwaitingRestart(session: &session)

        let restartEffects = session.apply(
            input: .receivedPrimaryBytes(
                try PrimaryRuntimeTestFixtures.encodeServerFrame(
                    .restartRound(.init())
                )
            ),
            now: PrimaryRuntimeTestFixtures.instant(1_060)
        )

        #expect(
            restartEffects == [
                .emitHostEvent(
                    roundIdentifier: PrimaryRuntimeTestFixtures.roundIdentifier,
                    event: .init(
                        kind: .status,
                        phase: .connecting,
                        summary: "Restarting round after blame handling"
                    )
                )
            ]
        )
        #expect(session.clientState.isConnected)
        #expect(session.clientState.round == nil)
        #expect(session.covertSession.substate == .idle)
        #expect(session.covertSession.endpointContext == nil)
        #expect(session.covertSession.queuedMessages.isEmpty)
        #expect(session.covertSession.outstandingRequest == nil)
    }

    @Test("Primary runtime maps host rejection to the existing coarse public failure surface")
    func validateHostRejectionProjection() throws {
        var session = PrimaryRuntimeTestFixtures.makeSession()
        try PrimaryRuntimeTestFixtures.driveThroughStartRound(session: &session)

        let effects = session.apply(
            input: .participantReservationRejected,
            now: PrimaryRuntimeTestFixtures.instant(1_031)
        )

        #expect(
            effects == [
                .emitHostEvent(
                    roundIdentifier: PrimaryRuntimeTestFixtures.roundIdentifier,
                    event: .init(
                        kind: .failure,
                        phase: .completed,
                        summary: "Host rejected participant reservation",
                        isTerminal: true
                    )
                )
            ]
        )
        #expect(session.clientState.round?.phase == .completed)
        #expect(session.clientState.round?.completionStatus == .hostRejected)
        #expect(session.lastError == .hostRejected)
    }

    @Test("Primary runtime maps unsupported execution materialization to not implemented")
    func validateUnsupportedExecutionMaterializationProjection() throws {
        let unsupportedSummary = "OpalCrypto-backed execution materialization is not wired yet"
        let workflow = OpalFusion.Execution.WorkflowContext(
            buildPlayerCommit: { _ in
                throw OpalFusion.Execution.WorkflowFailure.unsupportedExecution(unsupportedSummary)
            },
            buildCovertComponentMessages: { _ in
                throw OpalFusion.Execution.WorkflowFailure.unsupportedExecution(unsupportedSummary)
            },
            buildTransactionFinalizationProposal: { _ in
                throw OpalFusion.Execution.WorkflowFailure.unsupportedExecution(unsupportedSummary)
            },
            buildCovertSignatureMessages: { _ in
                throw OpalFusion.Execution.WorkflowFailure.unsupportedExecution(unsupportedSummary)
            },
            buildMyProofsList: { _ in
                throw OpalFusion.Execution.WorkflowFailure.unsupportedExecution(unsupportedSummary)
            },
            buildBlames: { _ in
                throw OpalFusion.Execution.WorkflowFailure.unsupportedExecution(unsupportedSummary)
            }
        )
        var session = OpalFusion.Runtime.PrimaryRuntimeSession(
            configuration: PrimaryRuntimeTestFixtures.configuration,
            genesisHash: PrimaryRuntimeTestFixtures.clientHello.genesisHash,
            joinPools: PrimaryRuntimeTestFixtures.joinPools,
            workflow: workflow,
            baseline: PrimaryRuntimeTestFixtures.baseline
        )
        try PrimaryRuntimeTestFixtures.driveThroughWarmup(session: &session)
        _ = session.apply(
            input: .receivedPrimaryBytes(
                try PrimaryRuntimeTestFixtures.encodeServerFrame(
                    .startRound(PrimaryRuntimeTestFixtures.startRound)
                )
            ),
            now: PrimaryRuntimeTestFixtures.instant(1_030)
        )

        let effects = session.apply(
            input: .participantReservationLoaded(
                PrimaryRuntimeTestFixtures.participantReservation
            ),
            now: PrimaryRuntimeTestFixtures.instant(1_031)
        )

        #expect(
            effects == [
                .emitHostEvent(
                    roundIdentifier: PrimaryRuntimeTestFixtures.roundIdentifier,
                    event: .init(
                        kind: .failure,
                        phase: .completed,
                        summary: unsupportedSummary,
                        isTerminal: true
                    )
                )
            ]
        )
        #expect(session.lastError == .notImplemented)
        #expect(session.lastErrorSummary == unsupportedSummary)
        #expect(
            session.clientState.round == .init(
                identifier: PrimaryRuntimeTestFixtures.roundIdentifier,
                completionStatus: .hostRejected
            )
        )
    }

    @Test("Primary runtime fails unsupported finalized transactions when the host transaction is loaded")
    func validateUnsupportedFinalizedTransactionFailsEarly() throws {
        let unsupportedSummary = OpalFusion.Execution.ProtocolPrimitives.supportedUnlockingScriptSummary
        let workflow = OpalFusion.Execution.WorkflowContext(
            buildPlayerCommit: { _ in PrimaryRuntimeTestFixtures.playerCommit },
            buildCovertComponentMessages: { _ in [PrimaryRuntimeTestFixtures.covertComponentMessage] },
            buildTransactionFinalizationProposal: { _ in PrimaryRuntimeTestFixtures.transactionProposal },
            buildCovertSignatureMessages: { _ in
                throw OpalFusion.Execution.WorkflowFailure.unsupportedExecution(unsupportedSummary)
            },
            buildMyProofsList: { _ in PrimaryRuntimeTestFixtures.myProofsList },
            buildBlames: { _ in PrimaryRuntimeTestFixtures.blames }
        )
        var session = OpalFusion.Runtime.PrimaryRuntimeSession(
            configuration: PrimaryRuntimeTestFixtures.configuration,
            genesisHash: PrimaryRuntimeTestFixtures.clientHello.genesisHash,
            joinPools: PrimaryRuntimeTestFixtures.joinPools,
            workflow: workflow,
            baseline: PrimaryRuntimeTestFixtures.baseline
        )
        try PrimaryRuntimeTestFixtures.driveToAwaitingSharedComponents(session: &session)
        _ = session.apply(
            input: .receivedPrimaryBytes(
                try PrimaryRuntimeTestFixtures.encodeServerFrame(
                    .shareCovertComponents(PrimaryRuntimeTestFixtures.sharedComponents)
                )
            ),
            now: PrimaryRuntimeTestFixtures.instant(1_040)
        )

        let effects = session.apply(
            input: .finalizedTransactionLoaded(PrimaryRuntimeTestFixtures.finalizedTransaction),
            now: PrimaryRuntimeTestFixtures.instant(1_042)
        )

        #expect(
            effects == [
                .emitHostEvent(
                    roundIdentifier: PrimaryRuntimeTestFixtures.roundIdentifier,
                    event: .init(
                        kind: .failure,
                        phase: .completed,
                        summary: unsupportedSummary,
                        isTerminal: true
                    )
                )
            ]
        )
        #expect(session.lastError == .notImplemented)
        #expect(session.lastErrorSummary == unsupportedSummary)
        #expect(session.clientState.round?.completionStatus == .hostRejected)
    }

    @Test("Primary runtime maps malformed primary payloads to protocol incompatibility")
    func validateMalformedPayloadProjection() throws {
        var session = PrimaryRuntimeTestFixtures.makeSession()
        _ = session.apply(input: .connected, now: PrimaryRuntimeTestFixtures.instant(995))

        let malformedFrame = try OpalFusion.Wire.PrimaryFrameEncoder(
            configuration: PrimaryRuntimeTestFixtures.baseline.framing
        )
        .encode(payload: [0x08])

        let effects = session.apply(
            input: .receivedPrimaryBytes(malformedFrame),
            now: PrimaryRuntimeTestFixtures.instant(996)
        )

        #expect(effects.count == 1)
        guard case let .emitHostEvent(roundIdentifier, event) = effects[0] else {
            Issue.record("Expected host event after malformed payload rejection")
            return
        }
        #expect(roundIdentifier == nil)
        #expect(event.kind == .failure)
        #expect(event.phase == .connecting)
        #expect(event.summary == "Primary wire decode failed")
        #expect(event.isTerminal == false)
        #expect(session.lastError == .protocolIncompatible)
        #expect(session.lastErrorSummary == "Primary wire decode failed")
        #expect(session.clientState.round == nil)
    }

    @Test("Primary runtime maps malformed covert response bytes to protocol incompatibility")
    func validateMalformedCovertResponseProjection() throws {
        var session = PrimaryRuntimeTestFixtures.makeSession()
        try PrimaryRuntimeTestFixtures.driveToAwaitingCovertSubmission(session: &session)
        PrimaryRuntimeTestFixtures.markCovertPrepared(session: &session)
        _ = session.apply(
            input: .clockAdvanced,
            now: PrimaryRuntimeTestFixtures.instant(1_035)
        )

        let effects = session.apply(
            input: .receivedCovertResponseBytes([0x08]),
            now: PrimaryRuntimeTestFixtures.instant(1_036)
        )

        #expect(effects.count == 1)
        guard case let .emitHostEvent(roundIdentifier, event) = effects[0] else {
            Issue.record("Expected host event after malformed covert response rejection")
            return
        }
        #expect(roundIdentifier == PrimaryRuntimeTestFixtures.roundIdentifier)
        #expect(event.kind == .failure)
        #expect(event.phase == .completed)
        #expect(event.summary == "Covert response decode failed")
        #expect(event.isTerminal)
        #expect(session.lastError == .protocolIncompatible)
        #expect(session.lastErrorSummary == "Covert response decode failed")
        #expect(session.clientState.round?.completionStatus == .protocolIncompatible)
    }

    @Test("Primary runtime maps covert request failures to transport failure")
    func validateCovertRequestFailureProjection() throws {
        var session = PrimaryRuntimeTestFixtures.makeSession()
        try PrimaryRuntimeTestFixtures.driveToAwaitingCovertSubmission(session: &session)
        PrimaryRuntimeTestFixtures.markCovertPrepared(session: &session)
        _ = session.apply(
            input: .clockAdvanced,
            now: PrimaryRuntimeTestFixtures.instant(1_035)
        )

        let effects = session.apply(
            input: .covertRequestFailed(summary: "Covert request failed"),
            now: PrimaryRuntimeTestFixtures.instant(1_036)
        )

        #expect(
            effects == [
                .emitHostEvent(
                    roundIdentifier: PrimaryRuntimeTestFixtures.roundIdentifier,
                    event: .init(
                        kind: .failure,
                        phase: .completed,
                        summary: "Covert request failed",
                        isTerminal: true
                    )
                )
            ]
        )
        #expect(session.lastError == .transportUnavailable)
        #expect(session.lastErrorSummary == "Covert request failed")
        #expect(session.clientState.round?.completionStatus == .transportFailed)
        #expect(session.covertSession.substate == .idle)
    }
}

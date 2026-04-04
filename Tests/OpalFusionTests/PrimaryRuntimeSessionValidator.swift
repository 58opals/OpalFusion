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
                .requestHostInputs(roundIdentifier: PrimaryRuntimeTestFixtures.roundIdentifier),
                .emitHostEvent(
                    roundIdentifier: PrimaryRuntimeTestFixtures.roundIdentifier,
                    event: .init(
                        kind: .status,
                        phase: .registeringInputs,
                        summary: "StartRound received; collecting reserved inputs"
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
            input: .hostInputsLoaded([PrimaryRuntimeTestFixtures.participantInput]),
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
                .requestHostInputs(roundIdentifier: PrimaryRuntimeTestFixtures.roundIdentifier),
                .emitHostEvent(
                    roundIdentifier: PrimaryRuntimeTestFixtures.roundIdentifier,
                    event: .init(
                        kind: .status,
                        phase: .registeringInputs,
                        summary: "StartRound received; collecting reserved inputs"
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

    @Test("Primary runtime surfaces deferred covert messages without executing them")
    func validateDeferredCovertSubmission() throws {
        var session = PrimaryRuntimeTestFixtures.makeSession()
        try PrimaryRuntimeTestFixtures.driveToAwaitingCovertSubmission(session: &session)

        let effects = session.apply(
            input: .clockAdvanced,
            now: PrimaryRuntimeTestFixtures.instant(1_035)
        )

        #expect(
            effects == [
                .deferCovertMessage(PrimaryRuntimeTestFixtures.covertComponentMessage),
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
        #expect(session.deferredCovertMessages == [PrimaryRuntimeTestFixtures.covertComponentMessage])
    }

    @Test("Primary runtime maps host rejection to the existing coarse public failure surface")
    func validateHostRejectionProjection() throws {
        var session = PrimaryRuntimeTestFixtures.makeSession()
        try PrimaryRuntimeTestFixtures.driveThroughStartRound(session: &session)

        let effects = session.apply(
            input: .hostInputsRejected,
            now: PrimaryRuntimeTestFixtures.instant(1_031)
        )

        #expect(
            effects == [
                .emitHostEvent(
                    roundIdentifier: PrimaryRuntimeTestFixtures.roundIdentifier,
                    event: .init(
                        kind: .failure,
                        phase: .completed,
                        summary: "Host rejected reserved inputs",
                        isTerminal: true
                    )
                )
            ]
        )
        #expect(session.clientState.round?.phase == .completed)
        #expect(session.clientState.round?.completionStatus == .hostRejected)
        #expect(session.lastError == .hostRejected)
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
        #expect(event.summary.hasPrefix("Primary wire decode failed:"))
        #expect(event.isTerminal == false)
        #expect(session.lastError == .protocolIncompatible)
        #expect(session.clientState.round == nil)
    }
}

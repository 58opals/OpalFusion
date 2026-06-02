// PrimaryRuntimeSessionValidator+ValidationGroup5.swift

@testable import OpalFusion
import Testing

extension PrimaryRuntimeSessionValidator {
    @Test("Primary runtime maps host policy finalization failures")
    func validateHostPolicyFinalizationFailureMapping() throws {
        var session = PrimaryRuntimeTestFixtures.makeSession()
        try PrimaryRuntimeTestFixtures.driveToAwaitingSharedComponents(session: &session)
        _ = session.apply(
            input: .receivedPrimaryBytes(
                try PrimaryRuntimeTestFixtures.encodeServerFrame(
                    .shareCovertComponents(PrimaryRuntimeTestFixtures.sharedComponents)
                )
            ),
            now: PrimaryRuntimeTestFixtures.instant(1_040)
        )
        let summary = "Host policy rejected coordinator input order"

        let effects = session.apply(
            input: .transactionFinalizationRejected(
                .hostPolicyRejected(summary: summary)
            ),
            now: PrimaryRuntimeTestFixtures.instant(1_042)
        )

        #expect(
            effects == [
                .emitHostEvent(
                    roundIdentifier: PrimaryRuntimeTestFixtures.roundIdentifier,
                    event: .init(
                        kind: .failure,
                        phase: .completed,
                        summary: summary,
                        isTerminal: true
                    )
                )
            ]
        )
        #expect(session.lastError == .hostRejected)
        #expect(session.lastErrorSummary == summary)
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
        let effect = try #require(effects.first)
        guard case let .emitHostEvent(roundIdentifier, event) = effect else {
            try #require(Bool(false), "Expected host event after malformed payload rejection")
            return
        }
        #expect(roundIdentifier == nil)
        #expect(event.kind == .failure)
        #expect(event.phase == .connecting)
        #expect(event.summary == "Primary wire decode failed")
        #expect(event.isTerminal == false)
        #expect(session.lastError == .protocolIncompatible)
        #expect(session.lastErrorSummary == "Primary wire decode failed")
        #expect(session.clientState.isConnected == false)
        #expect(session.clientState.round == nil)
    }

    @Test("Primary runtime fails a malformed trailing frame in the same inbound chunk")
    func validateMalformedTrailingFrameProjection() throws {
        var session = PrimaryRuntimeTestFixtures.makeSession()
        _ = session.apply(input: .connected, now: PrimaryRuntimeTestFixtures.instant(995))

        let serverHelloFrame = try PrimaryRuntimeTestFixtures.encodeServerFrame(
            .serverHello(PrimaryRuntimeTestFixtures.serverHello)
        )
        let invalidMagic = Array(
            repeating: UInt8(0xFF),
            count: PrimaryRuntimeTestFixtures.baseline.framing.magicBytes.count
        )
        let trailingMalformedFrame = invalidMagic + [0x00, 0x00, 0x00, 0x01, 0x42]

        let effects = session.apply(
            input: .receivedPrimaryBytes(serverHelloFrame + trailingMalformedFrame),
            now: PrimaryRuntimeTestFixtures.instant(996)
        )

        #expect(effects.count == 1)
        let effect = try #require(effects.first)
        guard case let .emitHostEvent(roundIdentifier, event) = effect else {
            try #require(Bool(false), "Expected host event after trailing malformed frame rejection")
            return
        }
        #expect(roundIdentifier == nil)
        #expect(event.kind == .failure)
        #expect(event.phase == .connecting)
        #expect(event.summary == "Primary wire decode failed")
        #expect(session.lastError == .protocolIncompatible)
        #expect(session.lastErrorSummary == "Primary wire decode failed")
        #expect(session.clientState.isConnected == false)
        #expect(session.clientState.round == nil)
    }

    @Test("Primary runtime drops earlier effects when a later frame in the same chunk fails")
    func validateLaterFrameFailureSuppressesEarlierChunkEffects() throws {
        var session = PrimaryRuntimeTestFixtures.makeSession()
        try PrimaryRuntimeTestFixtures.driveThroughWarmup(session: &session)
        let startRoundFrame = try PrimaryRuntimeTestFixtures.encodeServerFrame(
            .startRound(PrimaryRuntimeTestFixtures.startRound)
        )
        let blindResponsesFrame = try PrimaryRuntimeTestFixtures.encodeServerFrame(
            .blindSignatureResponses(PrimaryRuntimeTestFixtures.blindSignatureResponses)
        )

        let effects = session.apply(
            input: .receivedPrimaryBytes(startRoundFrame + blindResponsesFrame),
            now: PrimaryRuntimeTestFixtures.instant(1_030)
        )

        #expect(effects.count == 1)
        let effect = try #require(effects.first)
        guard case let .emitHostEvent(roundIdentifier, event) = effect else {
            try #require(Bool(false), "Expected host event after out-of-order frame rejection")
            return
        }
        #expect(roundIdentifier == PrimaryRuntimeTestFixtures.roundIdentifier)
        #expect(event.kind == .failure)
        #expect(event.phase == .completed)
        #expect(event.summary == "Blind signature responses arrived out of order")
        #expect(event.isTerminal)
        #expect(session.lastError == .protocolIncompatible)
        #expect(session.lastErrorSummary == "Blind signature responses arrived out of order")
        #expect(session.clientState.round?.completionStatus == .protocolIncompatible)
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
        let effect = try #require(effects.first)
        guard case let .emitHostEvent(roundIdentifier, event) = effect else {
            try #require(Bool(false), "Expected host event after malformed covert response rejection")
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
}

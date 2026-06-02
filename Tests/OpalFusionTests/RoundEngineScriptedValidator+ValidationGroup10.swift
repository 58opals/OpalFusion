// RoundEngineScriptedValidator+ValidationGroup10.swift

@testable import OpalFusion
import Testing

extension RoundEngineScriptedValidator {
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
}

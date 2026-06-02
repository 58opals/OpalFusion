// RoundEngineScriptedValidator+ValidationGroup9.swift

@testable import OpalFusion
import Testing

extension RoundEngineScriptedValidator {
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
}

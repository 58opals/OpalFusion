// RoundEngineScriptedValidator+ValidationGroup6.swift

@testable import OpalFusion
import Testing

extension RoundEngineScriptedValidator {
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
}

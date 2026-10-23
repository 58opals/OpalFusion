// RoundEngineScriptedValidator+ValidationGroup6.swift

@testable import CashFusionEngine
@testable import OpalFusionCore
import Testing

extension RoundEngineScriptedValidator {
    @Test("Round engine preserves a pre-round server rejection over later transport failure noise")
    func validateServerFailurePrecedenceOverTransportFailure() {
        for location in 0 ..< 3 {
            var engine = Self.makeEngine()
            if location == 0 {
                _ = engine.apply(input: .primaryConnected, now: Self.instant(995))
                _ = engine.apply(
                    input: .primaryMessage(.serverHello(Self.serverHello)),
                    now: Self.instant(996)
                )
            } else {
                Self.driveThroughStartRound(engine: &engine)
            }
            let rejection = OpalFusion.ProtocolModel.ServerFailure(
                message: "Coordinator rejected JoinPools; public-fixture-canary"
            )
            let input: OpalFusion.Execution.RoundEngine.Input = location == 2
                ? .covertResponse(.serverFailure(rejection))
                : .primaryMessage(.serverFailure(rejection))
            let rejectionEffects = engine.apply(input: input, now: Self.instant(1_031))
            #expect(engine.session.lastError == .coordinatorRejected)
            #expect(engine.clientState.isConnected == false)
            #expect(engine.session.lastErrorSummary == "Coordinator rejected the current flow")
            #expect(
                rejectionEffects == [
                    .emitHostEvent(
                        roundIdentifier: location == 0 ? nil : Self.roundIdentifier,
                        event: .init(
                            kind: .failure,
                            phase: location == 0 ? .connecting : .completed,
                            summary: "Coordinator rejected the current flow",
                            isTerminal: location != 0
                        )
                    )
                ]
            )
            if location != 0 {
                #expect(engine.clientState.round?.completionStatus == .coordinatorRejected)
            }
            let transportEffects = engine.apply(
                input: .primaryTransportFailed(summary: "Primary read failed"),
                now: Self.instant(1_032)
            )
            #expect(transportEffects.isEmpty)
            #expect(engine.session.lastError == .coordinatorRejected)
            #expect(engine.session.lastErrorSummary == "Coordinator rejected the current flow")
            #expect(engine.clientState.isConnected == false)
        }
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

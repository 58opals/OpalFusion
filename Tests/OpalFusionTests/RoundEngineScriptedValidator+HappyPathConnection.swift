// RoundEngineScriptedValidator+HappyPathConnection.swift

@testable import OpalFusion
import Testing

extension RoundEngineScriptedValidator {
    func assertHappyPathConnectionAndWarmup(
        engine: inout OpalFusion.Execution.RoundEngine,
        roundIdentifier: OpalFusion.Round.Identifier
    ) {
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
    }
}

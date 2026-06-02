// RoundEngineScriptedValidator+ValidationGroup17.swift

@testable import OpalFusion
import Testing

extension RoundEngineScriptedValidator {
    @Test("Round engine rejects shared components without a round identifier instead of trapping")
    func validateSharedComponentsWithoutRoundIdentifierFailsExplicitly() {
        var engine = Self.makeEngine()
        var round = OpalFusion.Execution.RoundContext(
            fusionBegin: Self.fusionBegin,
            serverHello: Self.serverHello,
            deadlines: .fromFusionBegin(
                Self.fusionBegin,
                timing: OpalFusion.Transport.BaselineConfiguration.electronCash443.roundTiming
            )
        )
        round.substate = .awaitingSharedComponents
        engine.round = round

        let effects = engine.apply(
            input: .primaryMessage(.shareCovertComponents(Self.sharedComponents)),
            now: Self.instant(1_040)
        )

        #expect(engine.clientState.round == nil)
        #expect(engine.session.lastError == .protocolIncompatible)
        #expect(engine.session.lastErrorSummary == "Shared components arrived before round identifier")
        #expect(
            effects == [
                .emitHostEvent(
                    roundIdentifier: nil,
                    event: .init(
                        kind: .failure,
                        phase: .completed,
                        summary: "Shared components arrived before round identifier",
                        isTerminal: true
                    )
                )
            ]
        )
    }
}

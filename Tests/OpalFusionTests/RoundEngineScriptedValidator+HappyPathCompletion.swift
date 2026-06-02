// RoundEngineScriptedValidator+HappyPathCompletion.swift

@testable import OpalFusion
import Testing

extension RoundEngineScriptedValidator {
    func assertHappyPathTransactionAndResult(
        engine: inout OpalFusion.Execution.RoundEngine,
        roundIdentifier: OpalFusion.Round.Identifier
    ) {
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
}

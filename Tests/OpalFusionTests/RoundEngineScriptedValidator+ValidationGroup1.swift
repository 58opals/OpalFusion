// RoundEngineScriptedValidator+ValidationGroup1.swift

@testable import OpalFusion
import Testing

extension RoundEngineScriptedValidator {
    @Test("Scripted round engine drives a happy-path round to success")
    func validateHappyPathRoundEngine() {
        var engine = Self.makeEngine()
        let roundIdentifier = OpalFusion.Round.Identifier(rawValue: "aabb")

        assertHappyPathConnectionAndWarmup(
            engine: &engine,
            roundIdentifier: roundIdentifier
        )
        assertHappyPathCommitmentSubmission(
            engine: &engine,
            roundIdentifier: roundIdentifier
        )
        assertHappyPathTransactionAndResult(
            engine: &engine,
            roundIdentifier: roundIdentifier
        )
    }
}

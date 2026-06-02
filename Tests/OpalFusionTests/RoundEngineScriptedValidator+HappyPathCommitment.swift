// RoundEngineScriptedValidator+HappyPathCommitment.swift

@testable import OpalFusion
import Testing

extension RoundEngineScriptedValidator {
    func assertHappyPathCommitmentSubmission(
        engine: inout OpalFusion.Execution.RoundEngine,
        roundIdentifier: OpalFusion.Round.Identifier
    ) {
        let commitEffects = engine.apply(
            input: .participantReservationLoaded(Self.participantReservation),
            now: Self.instant(1_031)
        )
        #expect(
            commitEffects == [
                .sendPrimary(.playerCommit(Self.playerCommit)),
                .emitHostEvent(
                    roundIdentifier: roundIdentifier,
                    event: .init(
                        kind: .status,
                        phase: .awaitingBlindSignatures,
                        summary: "Submitting player commitments and blind requests"
                    )
                )
            ]
        )
        #expect(engine.clientState.round?.phase == .awaitingBlindSignatures)

        let blindEffects = engine.apply(
            input: .primaryMessage(.blindSignatureResponses(Self.blindSignatureResponses)),
            now: Self.instant(1_032)
        )
        #expect(
            blindEffects == [
                .emitHostEvent(
                    roundIdentifier: roundIdentifier,
                    event: .init(
                        kind: .status,
                        phase: .awaitingCommitments,
                        summary: "Blind signature responses received"
                    )
                )
            ]
        )

        let commitmentEffects = engine.apply(
            input: .primaryMessage(.allCommitments(Self.allCommitments)),
            now: Self.instant(1_034)
        )
        #expect(
            commitmentEffects == [
                .emitHostEvent(
                    roundIdentifier: roundIdentifier,
                    event: .init(
                        kind: .status,
                        phase: .awaitingCommitments,
                        summary: "All commitments received; waiting for covert submit window"
                    )
                )
            ]
        )
        #expect(engine.clientState.round?.phase == .awaitingCommitments)

        let covertEffects = engine.apply(
            input: .clockAdvanced,
            now: Self.instant(1_035)
        )
        #expect(
            covertEffects == [
                .submitCovert(Self.covertComponentMessage),
                .emitHostEvent(
                    roundIdentifier: roundIdentifier,
                    event: .init(
                        kind: .status,
                        phase: .awaitingCommitments,
                        summary: "Submitting covert components"
                    )
                )
            ]
        )
    }
}

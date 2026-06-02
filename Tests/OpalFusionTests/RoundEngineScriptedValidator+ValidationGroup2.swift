// RoundEngineScriptedValidator+ValidationGroup2.swift

@testable import OpalFusion
import Testing

extension RoundEngineScriptedValidator {
    @Test("Round engine rejects mismatched blind signature response counts at receipt")
    func validateBlindSignatureResponseCountMismatch() {
        var engine = Self.makeEngine()
        Self.driveThroughStartRound(engine: &engine)
        _ = engine.apply(
            input: .participantReservationLoaded(Self.participantReservation),
            now: Self.instant(1_031)
        )

        let effects = engine.apply(
            input: .primaryMessage(
                .blindSignatureResponses(
                    .init(
                        responses: Self.blindSignatureResponses.responses + [
                            .init(scalar: [0x28])
                        ]
                    )
                )
            ),
            now: Self.instant(1_032)
        )

        #expect(engine.session.lastError == .protocolIncompatible)
        #expect(engine.round?.completionStatus == .protocolIncompatible)
        #expect(
            effects == [
                .emitHostEvent(
                    roundIdentifier: Self.roundIdentifier,
                    event: .init(
                        kind: .failure,
                        phase: .completed,
                        summary: "Blind signature response count did not match PlayerCommit request count",
                        isTerminal: true
                    )
                )
            ]
        )
    }

    @Test("Round engine rejects AllCommitments that omit local commitments")
    func validateAllCommitmentsMustIncludeLocalCommitments() {
        var engine = Self.makeEngine()
        Self.driveThroughStartRound(engine: &engine)
        _ = engine.apply(
            input: .participantReservationLoaded(Self.participantReservation),
            now: Self.instant(1_031)
        )
        _ = engine.apply(
            input: .primaryMessage(.blindSignatureResponses(Self.blindSignatureResponses)),
            now: Self.instant(1_032)
        )

        let effects = engine.apply(
            input: .primaryMessage(.allCommitments(.init(initialCommitments: []))),
            now: Self.instant(1_034)
        )

        #expect(engine.session.lastError == .protocolIncompatible)
        #expect(engine.round?.completionStatus == .protocolIncompatible)
        #expect(
            effects == [
                .emitHostEvent(
                    roundIdentifier: Self.roundIdentifier,
                    event: .init(
                        kind: .failure,
                        phase: .completed,
                        summary: "AllCommitments omitted a local commitment",
                        isTerminal: true
                    )
                )
            ]
        )
    }

    @Test("Round engine rejects duplicate AllCommitments at receipt")
    func validateAllCommitmentsRejectsDuplicates() {
        var engine = Self.makeEngine()
        Self.driveThroughStartRound(engine: &engine)
        _ = engine.apply(
            input: .participantReservationLoaded(Self.participantReservation),
            now: Self.instant(1_031)
        )
        _ = engine.apply(
            input: .primaryMessage(.blindSignatureResponses(Self.blindSignatureResponses)),
            now: Self.instant(1_032)
        )

        let effects = engine.apply(
            input: .primaryMessage(
                .allCommitments(
                    .init(
                        initialCommitments: [
                            Self.initialCommitment,
                            Self.initialCommitment
                        ]
                    )
                )
            ),
            now: Self.instant(1_034)
        )

        #expect(engine.session.lastError == .protocolIncompatible)
        #expect(engine.round?.completionStatus == .protocolIncompatible)
        #expect(
            effects == [
                .emitHostEvent(
                    roundIdentifier: Self.roundIdentifier,
                    event: .init(
                        kind: .failure,
                        phase: .completed,
                        summary: "AllCommitments contained duplicate commitments",
                        isTerminal: true
                    )
                )
            ]
        )
    }
}

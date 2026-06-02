// RoundEngineScriptedValidator+ValidationGroup12.swift

@testable import OpalFusion
import Testing

extension RoundEngineScriptedValidator {
    @Test("Round engine preserves terminal success after covert server failure noise")
    func validateTerminalRoundKeepsSuccessAfterCovertServerFailure() {
        var engine = Self.makeEngine()
        Self.driveToSignatureSubmission(engine: &engine)

        _ = engine.apply(
            input: .primaryMessage(.fusionResult(Self.successResult)),
            now: Self.instant(1_061)
        )
        #expect(engine.clientState.round?.completionStatus == .success)

        let failureEffects = engine.apply(
            input: .covertResponse(
                .serverFailure(.init(message: "late covert failure"))
            ),
            now: Self.instant(1_062)
        )

        #expect(failureEffects.isEmpty)
        #expect(engine.clientState.round?.completionStatus == .success)
        #expect(engine.session.lastError == nil)
    }

    @Test("Round engine preserves terminal success after transaction finalization rejection noise")
    func validateTerminalRoundKeepsSuccessAfterTransactionFinalizationRejection() {
        var engine = Self.makeEngine()
        Self.driveToSignatureSubmission(engine: &engine)

        _ = engine.apply(
            input: .primaryMessage(.fusionResult(Self.successResult)),
            now: Self.instant(1_061)
        )
        #expect(engine.clientState.round?.completionStatus == .success)

        let rejectionEffects = engine.apply(
            input: .transactionFinalizationRejected(
                .hostPolicyRejected(summary: "Late host policy rejection")
            ),
            now: Self.instant(1_062)
        )

        #expect(rejectionEffects.isEmpty)
        #expect(engine.clientState.round?.completionStatus == .success)
        #expect(engine.session.lastError == nil)
    }

    @Test("Round engine maps transaction assembly failures to not implemented")
    func validateTransactionAssemblyFailureMapping() {
        var engine = Self.makeEngine()
        Self.driveToSharedComponents(engine: &engine)
        let summary = "Assembler could not produce a finalized transaction"

        let effects = engine.apply(
            input: .transactionFinalizationRejected(
                .transactionAssemblyFailed(summary: summary)
            ),
            now: Self.instant(1_042)
        )

        #expect(
            effects == [
                .emitHostEvent(
                    roundIdentifier: Self.roundIdentifier,
                    event: .init(
                        kind: .failure,
                        phase: .completed,
                        summary: summary,
                        isTerminal: true
                    )
                )
            ]
        )
        #expect(engine.session.lastError == .notImplemented)
        #expect(engine.session.lastErrorSummary == summary)
        #expect(engine.clientState.round?.completionStatus == .hostRejected)
    }

    @Test("Round engine maps host policy finalization failures to host rejected")
    func validateHostPolicyFinalizationFailureMapping() {
        var engine = Self.makeEngine()
        Self.driveToSharedComponents(engine: &engine)
        let summary = "Host policy rejected coordinator input order"

        let effects = engine.apply(
            input: .transactionFinalizationRejected(
                .hostPolicyRejected(summary: summary)
            ),
            now: Self.instant(1_042)
        )

        #expect(
            effects == [
                .emitHostEvent(
                    roundIdentifier: Self.roundIdentifier,
                    event: .init(
                        kind: .failure,
                        phase: .completed,
                        summary: summary,
                        isTerminal: true
                    )
                )
            ]
        )
        #expect(engine.session.lastError == .hostRejected)
        #expect(engine.session.lastErrorSummary == summary)
        #expect(engine.clientState.round?.completionStatus == .hostRejected)
    }

    @Test("Round engine preserves terminal success after participant reservation rejection noise")
    func validateTerminalRoundKeepsSuccessAfterParticipantReservationRejection() {
        var engine = Self.makeEngine()
        Self.driveToSignatureSubmission(engine: &engine)

        _ = engine.apply(
            input: .primaryMessage(.fusionResult(Self.successResult)),
            now: Self.instant(1_061)
        )
        #expect(engine.clientState.round?.completionStatus == .success)

        let rejectionEffects = engine.apply(
            input: .participantReservationRejected,
            now: Self.instant(1_062)
        )

        #expect(rejectionEffects.isEmpty)
        #expect(engine.clientState.round?.completionStatus == .success)
        #expect(engine.session.lastError == nil)
    }

    @Test("Round engine preserves terminal success after participant reservation noise")
    func validateTerminalRoundKeepsSuccessAfterParticipantReservation() {
        var engine = Self.makeEngine()
        Self.driveToSignatureSubmission(engine: &engine)

        _ = engine.apply(
            input: .primaryMessage(.fusionResult(Self.successResult)),
            now: Self.instant(1_061)
        )
        #expect(engine.clientState.round?.completionStatus == .success)

        let loadedEffects = engine.apply(
            input: .participantReservationLoaded(Self.participantReservation),
            now: Self.instant(1_062)
        )

        #expect(loadedEffects.isEmpty)
        #expect(engine.clientState.round?.completionStatus == .success)
        #expect(engine.session.lastError == nil)
    }

    @Test("Round engine preserves terminal success after finalized transaction noise")
    func validateTerminalRoundKeepsSuccessAfterFinalizedTransaction() {
        var engine = Self.makeEngine()
        Self.driveToSignatureSubmission(engine: &engine)

        _ = engine.apply(
            input: .primaryMessage(.fusionResult(Self.successResult)),
            now: Self.instant(1_061)
        )
        #expect(engine.clientState.round?.completionStatus == .success)

        let loadedEffects = engine.apply(
            input: .finalizedTransactionLoaded(Self.finalizedTransaction),
            now: Self.instant(1_062)
        )

        #expect(loadedEffects.isEmpty)
        #expect(engine.clientState.round?.completionStatus == .success)
        #expect(engine.session.lastError == nil)
    }

    @Test("Round engine preserves terminal success after protocol rejection noise")
    func validateTerminalRoundKeepsSuccessAfterProtocolRejection() {
        var engine = Self.makeEngine()
        Self.driveToSignatureSubmission(engine: &engine)

        _ = engine.apply(
            input: .primaryMessage(.fusionResult(Self.successResult)),
            now: Self.instant(1_061)
        )
        #expect(engine.clientState.round?.completionStatus == .success)

        let rejectionEffects = engine.apply(
            input: .protocolRejected(summary: "Trailing primary bytes were malformed"),
            now: Self.instant(1_062)
        )

        #expect(rejectionEffects.isEmpty)
        #expect(engine.clientState.round?.completionStatus == .success)
        #expect(engine.session.lastError == nil)
    }
}

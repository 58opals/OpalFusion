// RoundEngineScriptedValidator+ValidationGroup5.swift

@testable import OpalFusion
import Testing

extension RoundEngineScriptedValidator {
    @Test("Scripted round engine supports blame handling and restart continuation")
    func validateBlameAndRestartFlow() {
        var engine = Self.makeEngine()
        let roundIdentifier = OpalFusion.Round.Identifier(rawValue: "aabb")

        Self.driveToSharedComponents(engine: &engine)

        let finalizedEffects = engine.apply(
            input: .finalizedTransactionLoaded(Self.finalizedTransaction),
            now: Self.instant(1_050)
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
                ),
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

        let failureEffects = engine.apply(
            input: .primaryMessage(.fusionResult(Self.failureResult)),
            now: Self.instant(1_055)
        )
        #expect(
            failureEffects == [
                .sendPrimary(.myProofsList(Self.myProofsList)),
                .emitHostEvent(
                    roundIdentifier: roundIdentifier,
                    event: .init(
                        kind: .warning,
                        phase: .blame,
                        summary: "Round result requires blame handling"
                    )
                )
            ]
        )
        #expect(engine.clientState.round?.phase == .blame)
        #expect(engine.clientState.round?.completionStatus == nil)

        let blameEffects = engine.apply(
            input: .primaryMessage(.theirProofsList(Self.theirProofsList)),
            now: Self.instant(1_056)
        )
        #expect(
            blameEffects == [
                .sendPrimary(.blames(Self.blames)),
                .emitHostEvent(
                    roundIdentifier: roundIdentifier,
                    event: .init(
                        kind: .warning,
                        phase: .blame,
                        summary: "Submitting blame proofs and awaiting restart"
                    )
                )
            ]
        )
        #expect(engine.round?.substate == .awaitingRestart)

        let restartEffects = engine.apply(
            input: .primaryMessage(.restartRound(.init())),
            now: Self.instant(1_060)
        )
        #expect(
            restartEffects == [
                .emitHostEvent(
                    roundIdentifier: roundIdentifier,
                    event: .init(
                        kind: .status,
                        phase: .connecting,
                        summary: "Restarting round after blame handling"
                    )
                )
            ]
        )
        #expect(engine.round == nil)
        #expect(engine.clientState.round == nil)
        #expect(engine.clientState.isConnected == true)
        #expect(engine.session.restartCount == 1)
        #expect(engine.session.latestServerHello == Self.serverHello)
    }

    @Test("Round engine fails restart instead of overflowing the session restart count")
    func validateRestartCountOverflowFailsRound() {
        var engine = Self.makeEngine()
        let roundIdentifier = OpalFusion.Round.Identifier(rawValue: "aabb")

        Self.driveToSignatureSubmission(engine: &engine)
        _ = engine.apply(
            input: .primaryMessage(.fusionResult(Self.failureResult)),
            now: Self.instant(1_055)
        )
        _ = engine.apply(
            input: .primaryMessage(.theirProofsList(Self.theirProofsList)),
            now: Self.instant(1_056)
        )
        #expect(engine.round?.substate == .awaitingRestart)
        engine.session.restartCount = Int.max

        let restartEffects = engine.apply(
            input: .primaryMessage(.restartRound(.init())),
            now: Self.instant(1_060)
        )

        #expect(engine.session.restartCount == Int.max)
        #expect(engine.session.lastError == .protocolIncompatible)
        #expect(engine.session.lastErrorSummary == "Round restart count exceeded the supported range")
        #expect(engine.clientState.round?.completionStatus == .protocolIncompatible)
        #expect(
            restartEffects == [
                .emitHostEvent(
                    roundIdentifier: roundIdentifier,
                    event: .init(
                        kind: .failure,
                        phase: .completed,
                        summary: "Round restart count exceeded the supported range",
                        isTerminal: true
                    )
                )
            ]
        )
    }

    @Test("Round engine maps unresolved blame handling to a distinct terminal outcome")
    func validateUnresolvedBlameTerminalOutcome() {
        var engine = Self.makeEngine()
        let roundIdentifier = OpalFusion.Round.Identifier(rawValue: "aabb")

        Self.driveToSignatureSubmission(engine: &engine)
        _ = engine.apply(
            input: .primaryMessage(.fusionResult(Self.failureResult)),
            now: Self.instant(1_055)
        )
        _ = engine.apply(
            input: .primaryMessage(.theirProofsList(Self.theirProofsList)),
            now: Self.instant(1_056)
        )

        let timeoutEffects = engine.apply(
            input: .clockAdvanced,
            now: Self.instant(1_116)
        )

        #expect(engine.session.lastError == .blameRequired)
        #expect(engine.session.lastErrorSummary == "Blame handling did not complete")
        #expect(engine.clientState.round?.completionStatus == .blameRequired)
        #expect(
            timeoutEffects == [
                .emitHostEvent(
                    roundIdentifier: roundIdentifier,
                    event: .init(
                        kind: .failure,
                        phase: .completed,
                        summary: "Blame handling did not complete",
                        isTerminal: true
                    )
                )
            ]
        )
    }
}

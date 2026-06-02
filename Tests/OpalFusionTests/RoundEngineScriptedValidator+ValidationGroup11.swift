// RoundEngineScriptedValidator+ValidationGroup11.swift

@testable import OpalFusion
import Testing

extension RoundEngineScriptedValidator {
    @Test("Round engine rejects StartRound messages with missing blind nonce points")
    func validateStartRoundBlindNoncePointPresence() {
        var engine = Self.makeEngine()
        _ = engine.apply(input: .primaryConnected, now: Self.instant(995))
        _ = engine.apply(
            input: .primaryMessage(.serverHello(Self.serverHello)),
            now: Self.instant(996)
        )
        _ = engine.apply(
            input: .primaryMessage(.fusionBegin(Self.fusionBegin)),
            now: Self.instant(1_000)
        )

        var blindNoncePoints = Self.startRound.blindNoncePoints
        blindNoncePoints[1] = []
        let effects = engine.apply(
            input: .primaryMessage(
                .startRound(
                    .init(
                        roundPublicKey: Self.startRound.roundPublicKey,
                        blindNoncePoints: blindNoncePoints,
                        serverTimeUnixSeconds: Self.startRound.serverTimeUnixSeconds
                    )
                )
            ),
            now: Self.instant(1_030)
        )

        #expect(engine.session.lastError == .protocolIncompatible)
        #expect(engine.round?.substate == .terminal)
        #expect(engine.round?.completionStatus == .protocolIncompatible)
        #expect(engine.clientState.round == nil)
        #expect(
            effects == [
                .emitHostEvent(
                    roundIdentifier: nil,
                    event: .init(
                        kind: .failure,
                        phase: .completed,
                        summary: "StartRound blind nonce point was missing",
                        isTerminal: true
                    )
                )
            ]
        )
    }

    @Test("Round engine clears warmup round after pre-StartRound covert failure")
    func validateWarmupCovertFailureClearsRound() {
        var engine = Self.makeEngine()
        _ = engine.apply(input: .primaryConnected, now: Self.instant(995))
        _ = engine.apply(
            input: .primaryMessage(.serverHello(Self.serverHello)),
            now: Self.instant(996)
        )
        _ = engine.apply(
            input: .primaryMessage(.fusionBegin(Self.fusionBegin)),
            now: Self.instant(1_000)
        )

        let failureEffects = engine.apply(
            input: .covertTransportFailed(summary: "Covert endpoint preparation failed"),
            now: Self.instant(1_001)
        )
        #expect(engine.round == nil)
        #expect(engine.session.lastError == .transportUnavailable)
        #expect(
            failureEffects == [
                .emitHostEvent(
                    roundIdentifier: nil,
                    event: .init(
                        kind: .failure,
                        phase: .connecting,
                        summary: "Covert endpoint preparation failed"
                    )
                )
            ]
        )

        let staleStartRoundEffects = engine.apply(
            input: .primaryMessage(.startRound(Self.startRound)),
            now: Self.instant(1_030)
        )
        #expect(staleStartRoundEffects.isEmpty)
        #expect(engine.clientState.round == nil)
    }

    @Test("Round engine ignores primary messages after terminal completion")
    func validateTerminalRoundIgnoresLatePrimaryMessages() {
        var engine = Self.makeEngine()
        Self.driveToSignatureSubmission(engine: &engine)

        _ = engine.apply(
            input: .primaryMessage(.fusionResult(Self.successResult)),
            now: Self.instant(1_061)
        )
        #expect(engine.clientState.round?.completionStatus == .success)

        let lateEffects = engine.apply(
            input: .primaryMessage(
                .serverFailure(.init(message: "late failure"))
            ),
            now: Self.instant(1_062)
        )

        #expect(lateEffects.isEmpty)
        #expect(engine.clientState.round?.completionStatus == .success)
        #expect(engine.session.lastError == nil)
    }

    @Test("Round engine preserves terminal success after clean primary disconnect")
    func validateTerminalRoundKeepsSuccessAfterPrimaryDisconnect() {
        var engine = Self.makeEngine()
        Self.driveToSignatureSubmission(engine: &engine)

        _ = engine.apply(
            input: .primaryMessage(.fusionResult(Self.successResult)),
            now: Self.instant(1_061)
        )
        #expect(engine.clientState.round?.completionStatus == .success)

        let disconnectEffects = engine.apply(
            input: .primaryDisconnected,
            now: Self.instant(1_062)
        )

        #expect(disconnectEffects.isEmpty)
        #expect(engine.clientState.isConnected == false)
        #expect(engine.clientState.round?.completionStatus == .success)
        #expect(engine.session.lastError == nil)
    }

    @Test("Round engine preserves terminal success after primary transport failure noise")
    func validateTerminalRoundKeepsSuccessAfterPrimaryTransportFailure() {
        var engine = Self.makeEngine()
        Self.driveToSignatureSubmission(engine: &engine)

        _ = engine.apply(
            input: .primaryMessage(.fusionResult(Self.successResult)),
            now: Self.instant(1_061)
        )
        #expect(engine.clientState.round?.completionStatus == .success)

        let failureEffects = engine.apply(
            input: .primaryTransportFailed(summary: "Primary read failed after result"),
            now: Self.instant(1_062)
        )

        #expect(failureEffects.isEmpty)
        #expect(engine.clientState.isConnected == false)
        #expect(engine.clientState.round?.completionStatus == .success)
        #expect(engine.session.lastError == nil)
    }

    @Test("Round engine preserves terminal success after covert transport failure noise")
    func validateTerminalRoundKeepsSuccessAfterCovertTransportFailure() {
        var engine = Self.makeEngine()
        Self.driveToSignatureSubmission(engine: &engine)

        _ = engine.apply(
            input: .primaryMessage(.fusionResult(Self.successResult)),
            now: Self.instant(1_061)
        )
        #expect(engine.clientState.round?.completionStatus == .success)

        let failureEffects = engine.apply(
            input: .covertTransportFailed(summary: "Covert request failed after result"),
            now: Self.instant(1_062)
        )

        #expect(failureEffects.isEmpty)
        #expect(engine.clientState.round?.completionStatus == .success)
        #expect(engine.session.lastError == nil)
    }
}

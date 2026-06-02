// RoundEngineScriptedValidator+ValidationGroup8.swift

@testable import OpalFusion
import Testing

extension RoundEngineScriptedValidator {
    @Test("Round engine enforces the official warmup slop boundary")
    func validateWarmupSlopBoundary() {
        var boundaryEngine = Self.makeEngine()
        _ = boundaryEngine.apply(input: .primaryConnected, now: Self.instant(995))
        _ = boundaryEngine.apply(
            input: .primaryMessage(.serverHello(Self.serverHello)),
            now: Self.instant(996)
        )
        _ = boundaryEngine.apply(
            input: .primaryMessage(.fusionBegin(Self.fusionBegin)),
            now: Self.instant(1_000)
        )

        #expect(
            boundaryEngine.apply(
                input: .clockAdvanced,
                now: Self.instant(1_033)
            ).isEmpty
        )
        let acceptedEffects = boundaryEngine.apply(
            input: .primaryMessage(.startRound(Self.startRound)),
            now: Self.instant(1_033)
        )
        #expect(boundaryEngine.clientState.round?.phase == .registeringInputs)
        #expect(acceptedEffects.first == .requestParticipantReservation(context: Self.participantReservationContext))

        var timeoutEngine = Self.makeEngine()
        _ = timeoutEngine.apply(input: .primaryConnected, now: Self.instant(995))
        _ = timeoutEngine.apply(
            input: .primaryMessage(.serverHello(Self.serverHello)),
            now: Self.instant(996)
        )
        _ = timeoutEngine.apply(
            input: .primaryMessage(.fusionBegin(Self.fusionBegin)),
            now: Self.instant(1_000)
        )

        let timeoutEffects = timeoutEngine.apply(
            input: .clockAdvanced,
            now: Self.instant(1_034)
        )
        #expect(timeoutEngine.session.lastError == .transportUnavailable)
        #expect(timeoutEngine.round?.substate == .terminal)
        #expect(timeoutEngine.clientState.round == nil)
        #expect(
            timeoutEffects == [
                .emitHostEvent(
                    roundIdentifier: nil,
                    event: .init(
                        kind: .failure,
                        phase: .completed,
                        summary: "Warmup expired before StartRound arrived",
                        isTerminal: true
                    )
                )
            ]
        )
    }

    @Test("Round engine times out pending participant reservation at commitment deadline")
    func validatePendingReservationTimesOutAtCommitmentDeadline() {
        var engine = Self.makeEngine()
        Self.driveThroughStartRound(engine: &engine)

        let timeoutEffects = engine.apply(
            input: .clockAdvanced,
            now: Self.instant(1_034)
        )

        #expect(engine.clientState.round?.phase == .completed)
        #expect(engine.clientState.round?.completionStatus == .transportFailed)
        #expect(
            timeoutEffects == [
                .emitHostEvent(
                    roundIdentifier: OpalFusion.Round.Identifier(rawValue: "aabb"),
                    event: .init(
                        kind: .failure,
                        phase: .completed,
                        summary: "Commitment deadline elapsed before PlayerCommit submission",
                        isTerminal: true
                    )
                )
            ]
        )
    }

    @Test("Round engine preserves covert component timeout after PlayerCommit")
    func validateCovertComponentTimeoutAfterPlayerCommit() {
        var timeoutEngine = Self.makeEngine()
        Self.driveThroughStartRound(engine: &timeoutEngine)
        _ = timeoutEngine.apply(
            input: .participantReservationLoaded(Self.participantReservation),
            now: Self.instant(1_031)
        )
        let timeoutEffects = timeoutEngine.apply(
            input: .clockAdvanced,
            now: Self.instant(1_046)
        )
        #expect(timeoutEngine.clientState.round?.phase == .completed)
        #expect(timeoutEngine.clientState.round?.completionStatus == .transportFailed)
        #expect(
            timeoutEffects == [
                .emitHostEvent(
                    roundIdentifier: OpalFusion.Round.Identifier(rawValue: "aabb"),
                    event: .init(
                        kind: .failure,
                        phase: .completed,
                        summary: "Round expired before covert component submission completed",
                        isTerminal: true
                    )
                )
            ]
        )
    }

    @Test("Round engine rejects FusionBegin tiers that were not joined")
    func validateFusionBeginTierMustBeJoined() {
        var engine = Self.makeEngine()
        _ = engine.apply(input: .primaryConnected, now: Self.instant(995))
        _ = engine.apply(
            input: .primaryMessage(.serverHello(Self.serverHello)),
            now: Self.instant(996)
        )

        let effects = engine.apply(
            input: .primaryMessage(
                .fusionBegin(
                    .init(
                        tier: 20_000,
                        covertDomain: Self.fusionBegin.covertDomain,
                        covertPort: Self.fusionBegin.covertPort,
                        covertSsl: Self.fusionBegin.covertSsl,
                        serverTimeUnixSeconds: Self.fusionBegin.serverTimeUnixSeconds
                    )
                )
            ),
            now: Self.instant(1_000)
        )

        #expect(engine.session.lastError == .protocolIncompatible)
        #expect(engine.round == nil)
        #expect(
            effects == [
                .emitHostEvent(
                    roundIdentifier: nil,
                    event: .init(
                        kind: .failure,
                        phase: .connecting,
                        summary: "FusionBegin tier was not requested"
                    )
                )
            ]
        )
    }
}

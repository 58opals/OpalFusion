// RoundEngineScriptedValidator+ValidationGroup7.swift

@testable import OpalFusion
import Testing

extension RoundEngineScriptedValidator {
    @Test("Round engine owns timing semantics and validates server clock skew")
    func validateTimingOwnership() {
        var happyEngine = Self.makeEngine()
        Self.driveThroughStartRound(engine: &happyEngine)

        guard let deadlines = happyEngine.round?.deadlines else {
            Issue.record("Expected round deadlines after StartRound")
            return
        }

        #expect(deadlines.fusionBeginAt == Self.instant(1_000))
        #expect(deadlines.warmupTarget == Self.instant(1_030))
        #expect(deadlines.warmupDeadline == Self.instant(1_033))
        #expect(deadlines.roundStartAt == Self.instant(1_030))
        #expect(deadlines.commitmentsDeadline == Self.instant(1_033))
        #expect(deadlines.covertComponentsStart == Self.instant(1_035))
        #expect(deadlines.covertComponentsDeadline == Self.instant(1_045))
        #expect(deadlines.signaturesStart == Self.instant(1_050))
        #expect(deadlines.signaturesDeadline == Self.instant(1_060))
        #expect(deadlines.conclusionTimeout == Self.instant(1_065))
        #expect(deadlines.closeStart == Self.instant(1_075))
        #expect(deadlines.blameCloseStart == Self.instant(1_110))
        #expect(deadlines.blameVerifyDeadline == Self.instant(1_115))

        var skewedEngine = Self.makeEngine()
        _ = skewedEngine.apply(input: .primaryConnected, now: Self.instant(995))
        _ = skewedEngine.apply(
            input: .primaryMessage(.serverHello(Self.serverHello)),
            now: Self.instant(996)
        )
        let skewEffects = skewedEngine.apply(
            input: .primaryMessage(
                .fusionBegin(
                    .init(
                        tier: 10_000,
                        covertDomain: "covert.example.org",
                        covertPort: 7_447,
                        covertSsl: true,
                        serverTimeUnixSeconds: 1_010
                    )
                )
            ),
            now: Self.instant(1_000)
        )
        #expect(skewedEngine.session.lastError == .protocolIncompatible)
        #expect(skewedEngine.round == nil)
        #expect(
            skewEffects == [
                .emitHostEvent(
                    roundIdentifier: nil,
                    event: .init(
                        kind: .failure,
                        phase: .connecting,
                        summary: "FusionBegin server time exceeded the allowed clock skew"
                    )
                )
            ]
        )

        var timeoutEngine = Self.makeEngine()
        Self.driveThroughStartRound(engine: &timeoutEngine)
        let lateReservationEffects = timeoutEngine.apply(
            input: .participantReservationLoaded(Self.participantReservation),
            now: Self.instant(1_034)
        )
        #expect(timeoutEngine.clientState.round?.phase == .completed)
        #expect(timeoutEngine.clientState.round?.completionStatus == .transportFailed)
        #expect(
            lateReservationEffects == [
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

    @Test("Round engine lets the default conclusion timeout win before close-start cleanup")
    func validateDefaultConclusionTimeoutPrecedesCloseStartCleanup() {
        var engine = Self.makeEngine()
        Self.driveToSignatureSubmission(engine: &engine)

        let effects = engine.apply(
            input: .clockAdvanced,
            now: Self.instant(1_075)
        )

        #expect(engine.round?.substate == .terminal)
        #expect(
            effects == [
                .emitHostEvent(
                    roundIdentifier: Self.roundIdentifier,
                    event: .init(
                        kind: .failure,
                        phase: .completed,
                        summary: "Round conclusion timeout elapsed",
                        isTerminal: true
                    )
                )
            ]
        )
    }

    @Test("Round engine emits one covert reset at close-start while the round remains active")
    func validateCloseStartCovertResetIsOneShot() {
        var engine = Self.makeEngine(baseline: Self.closeStartReachableBaseline)
        Self.driveToSignatureSubmission(engine: &engine)

        let effects = engine.apply(
            input: .clockAdvanced,
            now: Self.instant(1_075)
        )

        #expect(effects == [.resetCovertTransport])
        #expect(engine.round?.substate == .submittingSignatures)
        #expect(engine.clientState.round?.phase == .assemblingTransaction)
        #expect(
            engine.apply(
                input: .clockAdvanced,
                now: Self.instant(1_076)
            )
                .isEmpty
        )
    }

    @Test("Round engine does not emit close-start covert reset during blame restart handling")
    func validateCloseStartCovertResetIsSkippedDuringBlameRestart() {
        var engine = Self.makeEngine(baseline: Self.closeStartReachableBaseline)
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
        #expect(
            engine.apply(
                input: .clockAdvanced,
                now: Self.instant(1_075)
            )
                .isEmpty
        )
    }

    @Test("Round engine propagates the official covert spare count")
    func validateCovertSpareCountPropagation() {
        var engine = Self.makeEngine()
        _ = engine.apply(input: .primaryConnected, now: Self.instant(995))
        _ = engine.apply(
            input: .primaryMessage(.serverHello(Self.serverHello)),
            now: Self.instant(996)
        )

        let effects = engine.apply(
            input: .primaryMessage(.fusionBegin(Self.fusionBegin)),
            now: Self.instant(1_000)
        )

        guard case let .prepareCovert(context) = effects.first else {
            Issue.record("Expected FusionBegin to prepare a covert endpoint")
            return
        }
        #expect(context.spareConnectionCount == 6)
        #expect(
            context.spareConnectionCount
                == OpalFusion.Transport.BaselineConfiguration.electronCash443.covertTiming.spareConnectionCount
        )
    }
}

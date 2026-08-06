// MosaicAttemptCoreValidator+ValidationGroup3.swift

@testable import OpalFusion
import Testing

extension MosaicAttemptCoreValidator {
    @Test("Mosaic timeout aborts every active phase and releases after reservation eligibility")
    func validateTimeoutInEveryPhase() throws {
        for phase in Attempt.Phase.allCases {
            var scenario = try Self.makeScenario(at: phase)
            let reservationRoster = Self.expectedReservationRoster(
                during: phase,
                roster: scenario.roster
            )
            let failure = Attempt.Failure.aborted(
                during: phase,
                reason: .timeout
            )
            let outcome = Attempt.Outcome.failed(failure)

            let effects = scenario.attempt.apply(input: .abort(.timeout))

            #expect(
                effects == Self.terminationEffects(
                    outcome: outcome,
                    reservationRoster: reservationRoster
                )
            )
            #expect(scenario.attempt.state == .terminal(outcome))
        }
    }

    @Test("Mosaic models equivocation and missing participants as terminal aborts")
    func validateExplicitAbortReasons() throws {
        let reasons: [Attempt.AbortReason] = [
            .equivocation,
            .missingRequiredParticipant,
        ]

        for reason in reasons {
            var scenario = try Self.makeScenario(at: .groupedCommitment)
            let failure = Attempt.Failure.aborted(
                during: .groupedCommitment,
                reason: reason
            )
            let outcome = Attempt.Outcome.failed(failure)

            let effects = scenario.attempt.apply(input: .abort(reason))

            #expect(
                effects == Self.terminationEffects(
                    outcome: outcome,
                    reservationRoster: scenario.roster
                )
            )
            #expect(scenario.attempt.state == .terminal(outcome))
        }
    }

    @Test("Mosaic cancellation is terminal in every phase")
    func validateCancellationInEveryPhase() throws {
        for phase in Attempt.Phase.allCases {
            var scenario = try Self.makeScenario(at: phase)
            let reservationRoster = Self.expectedReservationRoster(
                during: phase,
                roster: scenario.roster
            )
            let cancellation = Attempt.Cancellation.requested(during: phase)
            let outcome = Attempt.Outcome.cancelled(cancellation)

            let effects = scenario.attempt.apply(input: .cancel)

            #expect(
                effects == Self.terminationEffects(
                    outcome: outcome,
                    reservationRoster: reservationRoster
                )
            )
            #expect(scenario.attempt.state == .terminal(outcome))
        }
    }

    @Test("Mosaic rejects in-place retry before and after reservation eligibility")
    func validateInPlaceRetryFailure() throws {
        for phase in [Attempt.Phase.discovery, .transcriptAgreement] {
            var scenario = try Self.makeScenario(at: phase)
            let reservationRoster = Self.expectedReservationRoster(
                during: phase,
                roster: scenario.roster
            )
            let failure = Attempt.Failure.inPlaceRetryNotPermitted
            let outcome = Attempt.Outcome.failed(failure)

            let effects = scenario.attempt.apply(input: .retryRequested)

            #expect(
                effects == Self.terminationEffects(
                    outcome: outcome,
                    reservationRoster: reservationRoster
                )
            )
            #expect(scenario.attempt.state == .terminal(outcome))
        }
    }

    @Test("Mosaic preserves completed failed and cancelled outcomes after later input")
    func validateInputsAfterTerminationAreRejected() throws {
        var completedScenario = try Self.makeScenario(at: .bchSigning)
        _ = completedScenario.attempt.apply(
            input: .signedTransactionValidated(
                contributorSigners: completedScenario.roster.contributors
            )
        )

        var failedAttempt = Attempt()
        _ = failedAttempt.apply(input: .discoveryCompleted(candidateCount: 6))

        var cancelledAttempt = Attempt()
        _ = cancelledAttempt.apply(input: .cancel)

        for terminalAttempt in [
            completedScenario.attempt,
            failedAttempt,
            cancelledAttempt,
        ] {
            var attempt = terminalAttempt
            let originalState = attempt.state

            #expect(
                attempt.apply(
                    input: .discoveryCompleted(candidateCount: 7)
                ) == [.inputRejected(.inputAfterTermination)]
            )
            #expect(attempt.state == originalState)
            #expect(
                attempt.apply(input: .retryRequested)
                    == [.inputRejected(.inputAfterTermination)]
            )
            #expect(attempt.state == originalState)
        }
    }

    @Test("Mosaic retry requires a distinct attempt instance")
    func validateFreshAttemptRequiredForRetry() {
        var originalAttempt = Attempt()
        _ = originalAttempt.apply(input: .retryRequested)
        let freshAttempt = Attempt()

        #expect(
            originalAttempt.state
                == .terminal(.failed(.inPlaceRetryNotPermitted))
        )
        #expect(freshAttempt.state == .discovery)
    }
}

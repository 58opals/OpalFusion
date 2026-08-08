// MosaicAttemptCoreValidator+ValidationGroup2.swift

@testable import OpalFusion
import Testing

extension MosaicAttemptCoreValidator {
    @Test("Mosaic attempt rejects discovery counts outside the roster bounds")
    func validateDiscoveryCandidateCountFailures() {
        for candidateCount in [6, 10] {
            var attempt = Attempt()
            let failure = Attempt.Failure.invalidCandidateCount(
                actual: candidateCount
            )
            let outcome = Attempt.Outcome.failed(failure)

            let effects = attempt.apply(
                input: .discoveryCompleted(candidateCount: candidateCount)
            )

            #expect(
                effects == Self.terminationEffects(
                    outcome: outcome,
                    reservationRoster: nil
                )
            )
            #expect(attempt.state == .terminal(outcome))
        }
    }

    @Test("Mosaic attempt rejects incomplete and duplicate control rosters")
    func validateControlRosterFailures() throws {
        let baseScenario = try Self.makeScenario(at: .controlRosterAgreement)

        var incompleteAttempt = baseScenario.attempt
        let incomplete = Array(baseScenario.roster.controlIdentities.dropLast())
        let countFailure = Attempt.Failure.controlIdentityCountMismatch(
            expected: baseScenario.roster.candidateCount,
            actual: incomplete.count
        )
        #expect(
            incompleteAttempt.apply(
                input: .controlRosterValidated(incomplete)
            ) == [.attemptTerminated(.failed(countFailure))]
        )
        #expect(incompleteAttempt.state == .terminal(.failed(countFailure)))

        var duplicateAttempt = baseScenario.attempt
        var duplicateIdentities = baseScenario.roster.controlIdentities
        duplicateIdentities[6] = duplicateIdentities[0]
        let duplicateFailure = Attempt.Failure.duplicateControlIdentity(
            duplicateIdentities[0]
        )
        #expect(
            duplicateAttempt.apply(
                input: .controlRosterValidated(duplicateIdentities)
            ) == [.attemptTerminated(.failed(duplicateFailure))]
        )
        #expect(duplicateAttempt.state == .terminal(.failed(duplicateFailure)))
    }

    @Test("Mosaic attempt rejects selected roles that do not match the control roster")
    func validateSelectedRoleIdentityFailure() throws {
        var scenario = try Self.makeScenario(at: .roleSelection)
        var mismatchedMembers = scenario.roster.members
        mismatchedMembers[6] = .init(
            controlIdentity: Self.controlIdentity(0xFE),
            role: .contributor
        )
        let mismatchedRoster = try Attempt.Roster(members: mismatchedMembers)
        let failure = Attempt.Failure.selectedRolesDoNotMatchControlRoster

        let effects = scenario.attempt.apply(
            input: .rolesSelected(mismatchedRoster)
        )

        #expect(effects == [.attemptTerminated(.failed(failure))])
        #expect(scenario.attempt.state == .terminal(.failed(failure)))
    }

    @Test("Mosaic manifest agreement requires every roster member exactly once")
    func validateManifestUnanimityFailures() throws {
        let roster = try Self.makeRoster()
        let complete = Self.manifestSignatureValidations(for: roster)
        let missing = Array(complete.dropLast())
        var duplicate = complete
        duplicate[6] = duplicate[0]
        var unknown = complete
        unknown[6] = MosaicManifestSignatureFixtures
            .manifestSignatureValidation(
                signer: Self.controlIdentity(0xFE),
                binding: Self.manifestA
            )

        let expectedFailures: [Attempt.ManifestAgreement.ValidationError] = [
            .missingSigners([roster.controlIdentities[6]]),
            .duplicateSigner(roster.controlIdentities[0]),
            .unknownSigner(Self.controlIdentity(0xFE)),
        ]

        for (validatedSignatures, validationError) in zip(
            [missing, duplicate, unknown],
            expectedFailures
        ) {
            var scenario = try Self.makeScenario(at: .manifestAgreement)
            let failure = Attempt.Failure.invalidManifestAgreement(
                validationError
            )

            let effects = scenario.attempt.apply(
                input: .manifestSignaturesValidated(validatedSignatures)
            )

            #expect(effects == [.attemptTerminated(.failed(failure))])
            #expect(scenario.attempt.state == .terminal(.failed(failure)))
        }
    }

    @Test("Mosaic manifest agreement rejects differing manifest bindings")
    func validateManifestDisagreementFailure() throws {
        var scenario = try Self.makeScenario(at: .manifestAgreement)
        var validatedSignatures = Self.manifestSignatureValidations(
            for: scenario.roster
        )
        validatedSignatures[6] = MosaicManifestSignatureFixtures
            .manifestSignatureValidation(
                signer: validatedSignatures[6].signer,
                binding: Self.manifestB
            )
        let failure = Attempt.Failure.invalidManifestAgreement(
            .bindingDisagreement
        )

        let effects = scenario.attempt.apply(
            input: .manifestSignaturesValidated(validatedSignatures)
        )

        #expect(effects == [.attemptTerminated(.failed(failure))])
        #expect(scenario.attempt.state == .terminal(.failed(failure)))
    }

    @Test("Mosaic contributor phases reject missing duplicate and unknown contributors")
    func validateContributorSetFailures() throws {
        let phases: [Attempt.Phase] = [
            .walletReservation,
            .groupedCommitment,
            .anonymousComponentSubmission,
            .bchSigning,
        ]

        for phase in phases {
            let baseScenario = try Self.makeScenario(at: phase)
            let complete = baseScenario.roster.contributors
            let missing = Array(complete.dropLast())
            var duplicate = complete
            duplicate[duplicate.count - 1] = duplicate[0]
            var unknown = complete
            unknown[unknown.count - 1] = Self.controlIdentity(0xFE)

            for contributors in [missing, duplicate, unknown] {
                var scenario = try Self.makeScenario(at: phase)
                let failure = Attempt.Failure.contributorSetMismatch(
                    during: phase
                )
                let outcome = Attempt.Outcome.failed(failure)

                let effects = scenario.attempt.apply(
                    input: Self.contributorInput(
                        for: phase,
                        contributors: contributors
                    )
                )

                #expect(
                    effects == Self.terminationEffects(
                        outcome: outcome,
                        reservationRoster: scenario.roster
                    )
                )
                #expect(scenario.attempt.state == .terminal(outcome))
            }
        }
    }

    @Test("Mosaic rejects conductor participation in every contributor-only phase")
    func validateConductorContributionFailures() throws {
        let contributorPhases: [Attempt.Phase] = [
            .walletReservation,
            .groupedCommitment,
            .anonymousComponentSubmission,
            .bchSigning,
        ]

        for phase in contributorPhases {
            var scenario = try Self.makeScenario(at: phase)
            let contributors = [scenario.roster.conductor]
                + Array(scenario.roster.contributors.dropLast())
            let failure = Attempt.Failure.conductorUsedContributorInput(
                during: phase
            )
            let outcome = Attempt.Outcome.failed(failure)

            let effects = scenario.attempt.apply(
                input: Self.contributorInput(
                    for: phase,
                    contributors: Array(contributors)
                )
            )

            #expect(
                effects == Self.terminationEffects(
                    outcome: outcome,
                    reservationRoster: scenario.roster
                )
            )
            #expect(scenario.attempt.state == .terminal(outcome))
        }

        var transcriptScenario = try Self.makeScenario(at: .transcriptAgreement)
        var acknowledgements = Self.transcriptAcknowledgements(
            for: transcriptScenario.roster
        )
        acknowledgements[acknowledgements.count - 1] = .init(
            contributor: transcriptScenario.roster.conductor,
            transcriptRoot: Self.transcriptRootA
        )
        let transcriptFailure = Attempt.Failure.conductorUsedContributorInput(
            during: .transcriptAgreement
        )
        let transcriptOutcome = Attempt.Outcome.failed(transcriptFailure)

        let transcriptEffects = transcriptScenario.attempt.apply(
            input: .transcriptAgreementValidated(acknowledgements)
        )

        #expect(
            transcriptEffects == Self.terminationEffects(
                outcome: transcriptOutcome,
                reservationRoster: transcriptScenario.roster
            )
        )
        #expect(
            transcriptScenario.attempt.state == .terminal(transcriptOutcome)
        )
    }

    @Test("Mosaic transcript agreement requires every contributor exactly once")
    func validateTranscriptUnanimityFailures() throws {
        let roster = try Self.makeRoster()
        let complete = Self.transcriptAcknowledgements(for: roster)
        let missing = Array(complete.dropLast())
        var duplicate = complete
        duplicate[duplicate.count - 1] = duplicate[0]
        var unknown = complete
        unknown[unknown.count - 1] = .init(
            contributor: Self.controlIdentity(0xFE),
            transcriptRoot: Self.transcriptRootA
        )

        for acknowledgements in [missing, duplicate, unknown] {
            var scenario = try Self.makeScenario(at: .transcriptAgreement)
            let failure = Attempt.Failure.transcriptAgreementNotUnanimous
            let outcome = Attempt.Outcome.failed(failure)

            let effects = scenario.attempt.apply(
                input: .transcriptAgreementValidated(acknowledgements)
            )

            #expect(
                effects == Self.terminationEffects(
                    outcome: outcome,
                    reservationRoster: scenario.roster
                )
            )
            #expect(scenario.attempt.state == .terminal(outcome))
        }
    }

    @Test("Mosaic transcript agreement rejects differing transcript roots")
    func validateTranscriptRootDisagreementFailure() throws {
        var scenario = try Self.makeScenario(at: .transcriptAgreement)
        var acknowledgements = Self.transcriptAcknowledgements(
            for: scenario.roster
        )
        let lastIndex = acknowledgements.count - 1
        acknowledgements[lastIndex] = .init(
            contributor: acknowledgements[lastIndex].contributor,
            transcriptRoot: Self.transcriptRootB
        )
        let failure = Attempt.Failure.transcriptRootDisagreement
        let outcome = Attempt.Outcome.failed(failure)

        let effects = scenario.attempt.apply(
            input: .transcriptAgreementValidated(acknowledgements)
        )

        #expect(
            effects == Self.terminationEffects(
                outcome: outcome,
                reservationRoster: scenario.roster
            )
        )
        #expect(scenario.attempt.state == .terminal(outcome))
    }

    @Test("Mosaic phase skipping and rollback terminate the attempt")
    func validateInvalidTransitionFailures() throws {
        var skippedAttempt = Attempt()
        let skippingFailure = Attempt.Failure.invalidTransition(
            from: .discovery,
            received: .candidateSetAgreementValidated
        )
        #expect(
            skippedAttempt.apply(
                input: .candidateSetAgreementValidated
            ) == [.attemptTerminated(.failed(skippingFailure))]
        )
        #expect(skippedAttempt.state == .terminal(.failed(skippingFailure)))

        var rollbackScenario = try Self.makeScenario(at: .manifestAgreement)
        let rollbackFailure = Attempt.Failure.invalidTransition(
            from: .manifestAgreement,
            received: .discoveryCompleted
        )
        #expect(
            rollbackScenario.attempt.apply(
                input: .discoveryCompleted(candidateCount: 7)
            ) == [.attemptTerminated(.failed(rollbackFailure))]
        )
        #expect(
            rollbackScenario.attempt.state == .terminal(.failed(rollbackFailure))
        )

        var reservedRollbackScenario = try Self.makeScenario(
            at: .groupedCommitment
        )
        let reservedRollbackFailure = Attempt.Failure.invalidTransition(
            from: .groupedCommitment,
            received: .rolesSelected
        )
        let reservedRollbackOutcome = Attempt.Outcome.failed(
            reservedRollbackFailure
        )
        #expect(
            reservedRollbackScenario.attempt.apply(
                input: .rolesSelected(reservedRollbackScenario.roster)
            ) == Self.terminationEffects(
                outcome: reservedRollbackOutcome,
                reservationRoster: reservedRollbackScenario.roster
            )
        )
        #expect(
            reservedRollbackScenario.attempt.state
                == .terminal(reservedRollbackOutcome)
        )
    }
}

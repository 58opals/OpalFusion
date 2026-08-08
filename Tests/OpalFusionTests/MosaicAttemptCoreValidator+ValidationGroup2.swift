// MosaicAttemptCoreValidator+ValidationGroup2.swift

@testable import OpalFusion
import Testing

extension MosaicAttemptCoreValidator {
    @Test("Mosaic attempt rejects discovery counts outside the roster bounds")
    func validateDiscoveryCandidateCountFailures() {
        for candidateCount in [6, 10] {
            var attempt = Attempt(configuration: Self.configuration)
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

    @Test("Mosaic attempt rejects a control roster that conflicts with discovery")
    func validateControlRosterCountFailure() throws {
        let baseScenario = try Self.makeScenario(at: .controlRosterAgreement)
        let mismatchedElection = try Self.makeElection(candidateCount: 8)
        let countFailure = Attempt.Failure.controlIdentityCountMismatch(
            expected: baseScenario.roster.candidateCount,
            actual: mismatchedElection.controlRoster.candidateCount
        )
        var attempt = baseScenario.attempt

        #expect(
            attempt.apply(
                input: .controlRosterValidated(
                    mismatchedElection.controlRoster
                )
            ) == [.attemptTerminated(.failed(countFailure))]
        )
        #expect(attempt.state == .terminal(.failed(countFailure)))
    }

    @Test("Mosaic attempt rejects role-election validation before the commitment barrier")
    func validateRoleElectionPhaseSkip() throws {
        var scenario = try Self.makeScenario(at: .roleSelection)
        let failure = Attempt.Failure.invalidTransition(
            from: .roleSelection,
            received: .roleElectionValidated
        )

        let effects = scenario.attempt.apply(
            input: .roleElectionValidated(scenario.election.validation)
        )

        #expect(effects == [.attemptTerminated(.failed(failure))])
        #expect(scenario.attempt.state == .terminal(.failed(failure)))
    }

    @Test("Mosaic rejects phase skipping and rollback across every active phase")
    func validateMonotonicPhaseBoundary() throws {
        for phase in Attempt.Phase.allCases where phase != .bchSigning {
            var scenario = try Self.makeScenario(at: phase)
            let failure = Attempt.Failure.invalidTransition(
                from: phase,
                received: .signedTransactionValidated
            )
            let outcome = Attempt.Outcome.failed(failure)

            let effects = scenario.attempt.apply(
                input: .signedTransactionValidated(
                    contributorSigners: scenario.roster.contributors
                )
            )

            #expect(
                effects == Self.terminationEffects(
                    outcome: outcome,
                    reservationRoster: Self.expectedReservationRoster(
                        during: phase,
                        roster: scenario.roster
                    )
                )
            )
            #expect(scenario.attempt.state == .terminal(outcome))
        }

        for phase in Attempt.Phase.allCases where phase != .discovery {
            var scenario = try Self.makeScenario(at: phase)
            let failure = Attempt.Failure.invalidTransition(
                from: phase,
                received: .discoveryCompleted
            )
            let outcome = Attempt.Outcome.failed(failure)

            let effects = scenario.attempt.apply(
                input: .discoveryCompleted(
                    candidateCount: scenario.roster.candidateCount
                )
            )

            #expect(
                effects == Self.terminationEffects(
                    outcome: outcome,
                    reservationRoster: Self.expectedReservationRoster(
                        during: phase,
                        roster: scenario.roster
                    )
                )
            )
            #expect(scenario.attempt.state == .terminal(outcome))
        }
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
                    input: try Self.contributorInput(
                        for: phase,
                        contributors: contributors,
                        roster: scenario.roster
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
                input: try Self.contributorInput(
                    for: phase,
                    contributors: Array(contributors),
                    roster: scenario.roster
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
        acknowledgements[acknowledgements.count - 1] = Self.transcriptAcknowledgement(
            contributor: transcriptScenario.roster.conductor
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

    @Test("Mosaic aggregate validation failures release once and terminate")
    func validateAggregateConstructionFailures() throws {
        var commitmentScenario = try Self.makeScenario(at: .groupedCommitment)
        let oversizedCommitmentSet = try MosaicUnsignedTransactionTranscriptFixtures
            .makeCommitmentSet(
                contributorCount: commitmentScenario.roster.contributors.count + 1
            )
        let commitmentFailure = Attempt.Failure.invalidCommitmentSet(
            .invalidMemberCount(expected: 138, actual: 161)
        )
        let commitmentOutcome = Attempt.Outcome.failed(commitmentFailure)

        let commitmentEffects = commitmentScenario.attempt.apply(
            input: .groupedCommitmentSetReceived(oversizedCommitmentSet)
        )

        #expect(
            commitmentEffects == Self.terminationEffects(
                outcome: commitmentOutcome,
                reservationRoster: commitmentScenario.roster
            )
        )
        #expect(commitmentScenario.attempt.state == .terminal(commitmentOutcome))

        var componentScenario = try Self.makeScenario(
            at: .anonymousComponentSubmission
        )
        let invalidComponents = try componentScenario.transactionPreparation
            .componentSet.components.map { component in
                guard case let .input(input) = component.payload else {
                    return component
                }
                return try OpalFusion.Mosaic.OpalV0.Component(
                    saltCommitment: component.saltCommitment,
                    payload: .input(
                        try .init(
                            previousTransactionHash: input.previousTransactionHash,
                            outputIndex: input.outputIndex,
                            amountSatoshis: input.amountSatoshis - 1
                        )
                    )
                )
            }
        let invalidComponentSet = try OpalFusion.Mosaic.OpalV0.ComponentSet(
            components: invalidComponents
        )
        let componentFailure = Attempt.Failure.invalidUnsignedTransactionTranscript(
            .feeMismatch(expected: 185, actual: 184)
        )
        let componentOutcome = Attempt.Outcome.failed(componentFailure)

        let componentEffects = componentScenario.attempt.apply(
            input: .anonymousComponentSetReceived(invalidComponentSet)
        )

        #expect(
            componentEffects == Self.terminationEffects(
                outcome: componentOutcome,
                reservationRoster: componentScenario.roster
            )
        )
        #expect(componentEffects.allSatisfy { effect in
            switch effect {
            case .transcriptInclusionValidationRequired, .bchSigningEligible:
                false
            default:
                true
            }
        })
        #expect(componentScenario.attempt.state == .terminal(componentOutcome))
    }

    @Test("Mosaic transcript agreement requires every contributor exactly once")
    func validateTranscriptUnanimityFailures() throws {
        let roster = try Self.makeElection().result.roster
        let complete = Self.transcriptAcknowledgements(for: roster)
        let missing = Array(complete.dropLast())
        var duplicate = complete
        duplicate[duplicate.count - 1] = duplicate[0]
        var unknown = complete
        unknown[unknown.count - 1] = Self.transcriptAcknowledgement(
            contributor: Self.controlIdentity(0xFE)
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
        acknowledgements[lastIndex] = Self.transcriptAcknowledgement(
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

    @Test("Mosaic transcript agreement rejects a valid signature for another round")
    func validateTranscriptRoundMismatchFailure() throws {
        var scenario = try Self.makeScenario(at: .transcriptAgreement)
        var acknowledgements = Self.transcriptAcknowledgements(
            for: scenario.roster
        )
        let lastIndex = acknowledgements.count - 1
        acknowledgements[lastIndex] = Self.transcriptAcknowledgement(
            contributor: acknowledgements[lastIndex].contributor,
            manifest: Self.manifestB
        )
        let failure = Attempt.Failure.transcriptRoundIdentifierMismatch
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

    @Test(
        "Mosaic transcript agreement rejects mixed and all-wrong profiles",
        arguments: [false, true]
    )
    func validateTranscriptProfileMismatchFailure(
        allAcknowledgementsUseWrongProfile: Bool
    ) throws {
        var scenario = try Self.makeScenario(at: .transcriptAgreement)
        var acknowledgements = Self.transcriptAcknowledgements(
            for: scenario.roster
        )
        if allAcknowledgementsUseWrongProfile {
            acknowledgements = scenario.roster.contributors.map {
                Self.transcriptAcknowledgement(
                    contributor: $0,
                    profile: .draft1
                )
            }
        } else {
            let lastIndex = acknowledgements.count - 1
            acknowledgements[lastIndex] = Self.transcriptAcknowledgement(
                contributor: acknowledgements[lastIndex].contributor,
                profile: .draft1
            )
        }
        let failure = Attempt.Failure.transcriptAcknowledgementProfileMismatch
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
        #expect(effects.allSatisfy { effect in
            if case .bchSigningEligible = effect {
                return false
            }
            return true
        })
        #expect(scenario.attempt.state == .terminal(outcome))
    }

    @Test("Mosaic transcript agreement is insensitive to acknowledgement order")
    func acceptPermutedTranscriptAcknowledgements() throws {
        var scenario = try Self.makeScenario(at: .transcriptAgreement)
        let acknowledgements = Self.transcriptAcknowledgements(
            for: scenario.roster,
            transcriptRoot:
                scenario.transactionPreparation.transcript.transcriptRoot
        ).reversed()

        let effects = scenario.attempt.apply(
            input: .transcriptAgreementValidated(Array(acknowledgements))
        )

        #expect(
            effects == [
                .bchSigningEligible(
                    contributors: scenario.roster.contributors,
                    transcript: scenario.transactionPreparation.transcript
                )
            ]
        )
    }

    @Test("Mosaic rejects a unanimous root that differs from its local transcript")
    func rejectUnanimousForeignTranscriptRoot() throws {
        var scenario = try Self.makeScenario(at: .transcriptAgreement)
        let acknowledgements = Self.transcriptAcknowledgements(
            for: scenario.roster,
            transcriptRoot: Self.transcriptRootA
        )
        let failure = Attempt.Failure.transcriptRootMismatch(
            expected: scenario.transactionPreparation.transcript.transcriptRoot,
            received: Self.transcriptRootA
        )
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
        #expect(effects.allSatisfy { effect in
            if case .bchSigningEligible = effect {
                return false
            }
            return true
        })
        #expect(scenario.attempt.state == .terminal(outcome))
    }

    @Test("Mosaic phase skipping and rollback terminate the attempt")
    func validateInvalidTransitionFailures() throws {
        var skippedAttempt = Attempt(configuration: Self.configuration)
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
            received: .roleElectionValidated
        )
        let reservedRollbackOutcome = Attempt.Outcome.failed(
            reservedRollbackFailure
        )
        #expect(
            reservedRollbackScenario.attempt.apply(
                input: .roleElectionValidated(
                    reservedRollbackScenario.election.validation
                )
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

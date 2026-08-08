// MosaicSemanticValidator+ValidationGroup2.swift

@testable import OpalFusion
import Testing

extension MosaicSemanticValidator {
    @Test("Wrong attempt and generation inputs are rejected without state mutation")
    func validateAttemptAndGenerationGuards() throws {
        var simulator = try Self.makeSimulator()
        let contributor = simulator.roster.contributors[0]
        let originalState = Self.findLocalAttempt(
            for: contributor,
            in: simulator
        ).state
        let manifestFact = Attempt.Input.manifestSignaturesValidated(
            Self.makeManifestSignatureValidations(
                roster: simulator.roster,
                manifest: Self.manifestA
            )
        )
        let wrongAttemptIdentifier = LocalAttempt.AttemptIdentifier(
            validatedBytes: [0xFE]
        )
        let wrongAttemptInput = LocalAttempt.Input(
            attemptIdentifier: wrongAttemptIdentifier,
            generationIdentifier: simulator.generationIdentifier,
            attemptInput: manifestFact
        )

        #expect(
            simulator.deliver(input: wrongAttemptInput, to: contributor)
                == [
                    .inputRejected(
                        .attemptIdentifierMismatch(
                            expected: simulator.attemptIdentifier,
                            received: wrongAttemptIdentifier
                        )
                    )
                ]
        )
        #expect(
            Self.findLocalAttempt(for: contributor, in: simulator).state
                == originalState
        )

        let wrongGenerationIdentifier = LocalAttempt.GenerationIdentifier(
            opaqueBytes: [0xFD]
        )
        let wrongGenerationInput = LocalAttempt.Input(
            attemptIdentifier: simulator.attemptIdentifier,
            generationIdentifier: wrongGenerationIdentifier,
            attemptInput: manifestFact
        )
        #expect(
            simulator.deliver(input: wrongGenerationInput, to: contributor)
                == [
                    .inputRejected(
                        .generationIdentifierMismatch(
                            expected: simulator.generationIdentifier,
                            received: wrongGenerationIdentifier
                        )
                    )
                ]
        )
        #expect(
            Self.findLocalAttempt(for: contributor, in: simulator).state
                == originalState
        )
        #expect(
            !Self.findLocalAttempt(
                for: contributor,
                in: simulator
            ).hasReservationEligibility
        )

        let correctEffects = simulator.deliver(
            attemptInput: manifestFact,
            to: [contributor]
        )
        #expect(
            Self.countReservationEligibility(
                in: correctEffects[contributor] ?? []
            ) == 1
        )
    }

    @Test("Future-phase delivery terminates each peer without granting wallet authority")
    func validateReorderedFutureFactFailure() throws {
        var simulator = try Self.makeSimulator()
        _ = simulator.broadcast(
            attemptInput: .walletReservationsPrepared(
                contributors: simulator.roster.contributors
            )
        )
        let failure = Attempt.Failure.invalidTransition(
            from: .manifestAgreement,
            received: .walletReservationsPrepared
        )

        for member in simulator.roster.members {
            let localAttempt = Self.findLocalAttempt(
                for: member.controlIdentity,
                in: simulator
            )
            let effects = simulator.effectJournal[member.controlIdentity] ?? []
            #expect(localAttempt.state == .terminal(.failed(failure)))
            #expect(Self.countContributorAuthorityEffects(in: effects) == 0)
        }
    }

    @Test("Omitted delivery leaves peers split until timeout terminates every local engine")
    func validateOmissionAndTimeoutPropagation() throws {
        var simulator = try Self.makeSimulator(candidateCount: 9)
        _ = simulator.broadcast(
            attemptInput: .manifestSignaturesValidated(
                Self.makeManifestSignatureValidations(
                    roster: simulator.roster,
                    manifest: Self.manifestA
                )
            )
        )
        let omittedContributor = try #require(
            simulator.roster.contributors.last
        )
        let advancedRecipients = simulator.roster.controlIdentities.filter {
            $0 != omittedContributor
        }
        _ = simulator.deliver(
            attemptInput: .walletReservationsPrepared(
                contributors: simulator.roster.contributors
            ),
            to: advancedRecipients
        )
        _ = simulator.deliver(
            attemptInput: .groupedCommitmentSetReceived(
                try MosaicUnsignedTransactionTranscriptFixtures
                    .makeCommitmentSet(
                        contributorCount: simulator.roster.contributors.count
                    )
            ),
            to: advancedRecipients
        )

        #expect(
            Self.findLocalAttempt(for: omittedContributor, in: simulator).state
                == .walletReservation(
                    roster: simulator.roster,
                    manifest: Self.manifestA
                )
        )
        _ = simulator.broadcast(attemptInput: .abort(.timeout))

        for member in simulator.roster.members {
            let localAttempt = Self.findLocalAttempt(
                for: member.controlIdentity,
                in: simulator
            )
            guard case let .terminal(.failed(.aborted(_, reason))) = localAttempt.state else {
                Issue.record("Expected every omitted or advanced peer to terminate on timeout")
                continue
            }
            #expect(reason == .timeout)

            let effects = simulator.effectJournal[member.controlIdentity] ?? []
            if member.role == .contributor {
                #expect(Self.countReservationEligibility(in: effects) == 1)
                #expect(Self.countReleaseRequirements(in: effects) == 1)
                #expect(Self.countCommitRequirements(in: effects) == 0)
            } else {
                #expect(Self.countContributorAuthorityEffects(in: effects) == 0)
            }
        }
    }
}

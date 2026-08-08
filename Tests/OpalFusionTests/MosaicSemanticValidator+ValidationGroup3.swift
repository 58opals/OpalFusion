// MosaicSemanticValidator+ValidationGroup3.swift

@testable import OpalFusion
import Testing

extension MosaicSemanticValidator {
    @Test("Relay partition propagates validated equivocation aborts to every peer")
    func validatePartitionAndEquivocationPropagation() throws {
        var simulator = try Self.makeSimulator(candidateCount: 8)
        _ = simulator.broadcast(
            attemptInput: .manifestSignaturesValidated(
                Self.makeManifestSignatureValidations(
                    roster: simulator.roster,
                    manifest: Self.manifestA
                )
            )
        )
        let partitionBoundary = simulator.roster.candidateCount / 2
        let firstPartition = Array(
            simulator.roster.controlIdentities[..<partitionBoundary]
        )
        _ = simulator.deliver(
            attemptInput: .walletReservationsPrepared(
                contributors: simulator.roster.contributors
            ),
            to: firstPartition
        )
        _ = simulator.deliver(
            attemptInput: .groupedCommitmentSetReceived(
                try MosaicUnsignedTransactionTranscriptFixtures
                    .makeCommitmentSet(
                        contributorCount: simulator.roster.contributors.count
                    )
            ),
            to: firstPartition
        )

        _ = simulator.broadcast(attemptInput: .abort(.equivocation))

        for member in simulator.roster.members {
            let localAttempt = Self.findLocalAttempt(
                for: member.controlIdentity,
                in: simulator
            )
            guard case let .terminal(.failed(.aborted(_, reason))) = localAttempt.state else {
                Issue.record("Expected each partitioned peer to terminate on equivocation")
                continue
            }
            #expect(reason == .equivocation)

            let effects = simulator.effectJournal[member.controlIdentity] ?? []
            if member.role == .contributor {
                #expect(Self.countReservationEligibility(in: effects) == 1)
                #expect(Self.countReleaseRequirements(in: effects) == 1)
            } else {
                #expect(Self.countContributorAuthorityEffects(in: effects) == 0)
            }
        }
    }

    @Test("Cancellation after eligibility releases contributors and never grants conductor authority")
    func validateCancellationPropagation() throws {
        var simulator = try Self.makeSimulator()
        _ = simulator.broadcast(
            attemptInput: .manifestSignaturesValidated(
                Self.makeManifestSignatureValidations(
                    roster: simulator.roster,
                    manifest: Self.manifestA
                )
            )
        )
        _ = simulator.broadcast(
            attemptInput: .walletReservationsPrepared(
                contributors: simulator.roster.contributors
            )
        )
        _ = simulator.broadcast(
            attemptInput: .groupedCommitmentSetReceived(
                try MosaicUnsignedTransactionTranscriptFixtures
                    .makeCommitmentSet(
                        contributorCount: simulator.roster.contributors.count
                    )
            )
        )
        let preparation = try MosaicUnsignedTransactionTranscriptFixtures.prepare(
            roster: simulator.roster,
            manifest: Self.manifestA
        )
        _ = simulator.broadcast(
            attemptInput: .anonymousComponentSetReceived(
                preparation.componentSet
            )
        )
        _ = try simulator.validateTranscriptInclusion(preparation.transcript)
        _ = simulator.broadcast(
            attemptInput: .transcriptAgreementValidated(
                Self.makeTranscriptAcknowledgements(
                    roster: simulator.roster,
                    transcriptRoot: preparation.transcript.transcriptRoot
                )
            )
        )

        _ = simulator.broadcast(attemptInput: .cancel)

        let cancellation = Attempt.Cancellation.requested(
            during: .bchSigning
        )
        for member in simulator.roster.members {
            let localAttempt = Self.findLocalAttempt(
                for: member.controlIdentity,
                in: simulator
            )
            let effects = simulator.effectJournal[member.controlIdentity] ?? []
            #expect(localAttempt.state == .terminal(.cancelled(cancellation)))

            if member.role == .contributor {
                #expect(Self.countReservationEligibility(in: effects) == 1)
                #expect(Self.countPreSignRequirements(in: effects) == 1)
                #expect(Self.countSigningEligibility(in: effects) == 1)
                #expect(Self.countReleaseRequirements(in: effects) == 1)
            } else {
                #expect(Self.countContributorAuthorityEffects(in: effects) == 0)
            }
        }
    }

    @Test("Retry requires fresh identities generation and material in a distinct instance")
    func validateFreshRetryInstance() throws {
        var originalSimulator = try Self.makeSimulator()
        _ = originalSimulator.broadcast(
            attemptInput: .manifestSignaturesValidated(
                Self.makeManifestSignatureValidations(
                    roster: originalSimulator.roster,
                    manifest: Self.manifestA
                )
            )
        )
        _ = originalSimulator.broadcast(attemptInput: .retryRequested)

        for member in originalSimulator.roster.members {
            let localAttempt = Self.findLocalAttempt(
                for: member.controlIdentity,
                in: originalSimulator
            )
            let effects = originalSimulator.effectJournal[member.controlIdentity] ?? []
            #expect(
                localAttempt.state
                    == .terminal(.failed(.inPlaceRetryNotPermitted))
            )
            if member.role == .contributor {
                #expect(Self.countReservationEligibility(in: effects) == 1)
                #expect(Self.countReleaseRequirements(in: effects) == 1)
                #expect(Self.countCommitRequirements(in: effects) == 0)
            } else {
                #expect(Self.countContributorAuthorityEffects(in: effects) == 0)
            }
        }

        var retrySimulator = try Self.makeSimulator(
            attemptByte: 0x12,
            generationByte: 0x22,
            identityOffset: 0x40,
            materialOffset: 0x70
        )
        #expect(retrySimulator.attemptIdentifier != originalSimulator.attemptIdentifier)
        #expect(retrySimulator.generationIdentifier != originalSimulator.generationIdentifier)
        #expect(
            Set(retrySimulator.roster.controlIdentities).isDisjoint(
                with: Set(originalSimulator.roster.controlIdentities)
            )
        )
        #expect(
            retrySimulator.roleElection.controlRosterDigest
                != originalSimulator.roleElection.controlRosterDigest
        )
        #expect(
            Set(retrySimulator.localAttempts.map(\.materialIdentifier)).isDisjoint(
                with: Set(originalSimulator.localAttempts.map(\.materialIdentifier))
            )
        )

        try Self.complete(
            simulator: &retrySimulator,
            manifest: Self.manifestB
        )
        for member in retrySimulator.roster.members {
            let localAttempt = Self.findLocalAttempt(
                for: member.controlIdentity,
                in: retrySimulator
            )
            let effects = retrySimulator.effectJournal[member.controlIdentity] ?? []
            #expect(localAttempt.state == .terminal(.completed))
            if member.role == .contributor {
                #expect(Self.countCommitRequirements(in: effects) == 1)
                #expect(Self.countReleaseRequirements(in: effects) == 0)
            } else {
                #expect(Self.countContributorAuthorityEffects(in: effects) == 0)
            }
        }
    }
}

// MosaicAttemptCoreValidator+ValidationGroup1.swift

@testable import OpalFusion
import Testing

extension MosaicAttemptCoreValidator {
    @Test("Mosaic roster accepts one conductor and six through eight contributors")
    func validateRosterBounds() throws {
        for candidateCount in 7 ... 9 {
            let roster = try Self.makeRoster(candidateCount: candidateCount)

            #expect(roster.candidateCount == candidateCount)
            #expect(roster.contributors.count == candidateCount - 1)
            #expect(roster.controlIdentities.count == candidateCount)
            #expect(Set(roster.controlIdentities).count == candidateCount)
            #expect(!roster.contributors.contains(roster.conductor))
        }
    }

    @Test("Mosaic roster rejects candidate counts outside seven through nine")
    func validateRosterCandidateCountFailures() {
        for candidateCount in [6, 10] {
            #expect(
                throws: Attempt.Roster.ValidationError.invalidCandidateCount(
                    actual: candidateCount
                )
            ) {
                _ = try Attempt.Roster(
                    members: Self.makeMembers(candidateCount: candidateCount)
                )
            }
        }
    }

    @Test("Mosaic roster rejects zero or multiple conductors")
    func validateRosterRoleCountFailures() {
        #expect(
            throws: Attempt.Roster.ValidationError.invalidRoleCounts(
                conductors: 0,
                contributors: 7
            )
        ) {
            _ = try Attempt.Roster(
                members: Self.makeMembers(
                    candidateCount: 7,
                    conductorIndexes: []
                )
            )
        }

        #expect(
            throws: Attempt.Roster.ValidationError.invalidRoleCounts(
                conductors: 2,
                contributors: 5
            )
        ) {
            _ = try Attempt.Roster(
                members: Self.makeMembers(
                    candidateCount: 7,
                    conductorIndexes: [0, 1]
                )
            )
        }
    }

    @Test("Mosaic roster rejects duplicate one-time control identities")
    func validateRosterDuplicateControlIdentityFailure() {
        var members = Self.makeMembers(candidateCount: 7)
        members[6] = .init(
            controlIdentity: members[0].controlIdentity,
            role: .contributor
        )
        let duplicate = members[0].controlIdentity

        #expect(
            throws: Attempt.Roster.ValidationError.duplicateControlIdentity(
                duplicate
            )
        ) {
            _ = try Attempt.Roster(members: members)
        }
    }

    @Test("Mosaic attempt follows the complete happy path and emits only bounded effects")
    func validateHappyPath() throws {
        var attempt = Attempt()
        let roster = try Self.makeRoster()

        #expect(attempt.state == .discovery)

        #expect(
            attempt.apply(input: .discoveryCompleted(candidateCount: 7)).isEmpty
        )
        #expect(attempt.state == .candidateSetAgreement(candidateCount: 7))

        #expect(
            attempt.apply(input: .candidateSetAgreementValidated).isEmpty
        )
        #expect(attempt.state == .controlRosterAgreement(candidateCount: 7))

        #expect(
            attempt.apply(
                input: .controlRosterValidated(roster.controlIdentities)
            ).isEmpty
        )
        #expect(
            attempt.state == .roleSelection(
                controlIdentities: roster.controlIdentities
            )
        )

        #expect(attempt.apply(input: .rolesSelected(roster)).isEmpty)
        #expect(attempt.state == .manifestAgreement(roster: roster))

        let reservationEffects = attempt.apply(
            input: .manifestSignaturesValidated(
                Self.manifestSignatureValidations(for: roster)
            )
        )
        #expect(
            reservationEffects == [
                .walletReservationEligible(
                    contributors: roster.contributors,
                    manifest: Self.manifestA
                )
            ]
        )
        #expect(
            attempt.state == .walletReservation(
                roster: roster,
                manifest: Self.manifestA
            )
        )

        #expect(
            attempt.apply(
                input: .walletReservationsPrepared(
                    contributors: roster.contributors
                )
            ).isEmpty
        )
        #expect(
            attempt.state == .groupedCommitment(
                roster: roster,
                manifest: Self.manifestA
            )
        )

        #expect(
            attempt.apply(
                input: .groupedCommitmentsValidated(
                    contributors: roster.contributors
                )
            ).isEmpty
        )
        #expect(
            attempt.state == .anonymousComponentSubmission(
                roster: roster,
                manifest: Self.manifestA
            )
        )

        #expect(
            attempt.apply(
                input: .anonymousComponentsValidated(
                    contributors: roster.contributors
                )
            ).isEmpty
        )
        #expect(
            attempt.state == .transcriptAgreement(
                roster: roster,
                manifest: Self.manifestA
            )
        )

        let signingEffects = attempt.apply(
            input: .transcriptAgreementValidated(
                Self.transcriptAcknowledgements(for: roster)
            )
        )
        #expect(
            signingEffects == [
                .bchSigningEligible(
                    contributors: roster.contributors,
                    transcriptRoot: Self.transcriptRootA
                )
            ]
        )
        #expect(
            attempt.state == .bchSigning(
                roster: roster,
                manifest: Self.manifestA,
                transcriptRoot: Self.transcriptRootA
            )
        )

        let completionEffects = attempt.apply(
            input: .signedTransactionValidated(
                contributorSigners: roster.contributors
            )
        )
        #expect(completionEffects == [.attemptTerminated(.completed)])
        #expect(attempt.state == .terminal(.completed))
    }
}

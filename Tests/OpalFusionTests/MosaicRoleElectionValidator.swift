// MosaicRoleElectionValidator.swift

import Testing
@testable import OpalFusion

@Suite("Mosaic validated role-seed integration")
struct MosaicRoleElectionValidator {
    typealias Attempt = OpalFusion.Mosaic.Attempt

    @Test("Validate and normalize a complete one-time control roster")
    func validateControlRoster() throws {
        let identities = controlIdentities(count: 7)
        let digest = Array(repeating: UInt8(0xA1), count: 32)
        let binding = try Attempt.ControlRosterBinding(
            validatedControlIdentities: Array(identities.reversed()),
            validatedControlRosterDigest: digest
        )

        #expect(binding.candidateCount == 7)
        #expect(binding.controlRosterDigest == digest)
        #expect(
            binding.controlIdentities == identities.sorted {
                $0.validatedBytes.lexicographicallyPrecedes($1.validatedBytes)
            }
        )

        for count in [6, 10] {
            #expect(
                throws: Attempt.ControlRosterBinding.ValidationError
                    .invalidCandidateCount(actual: count)
            ) {
                _ = try Attempt.ControlRosterBinding(
                    validatedControlIdentities: controlIdentities(count: count),
                    validatedControlRosterDigest: digest
                )
            }
        }
        for digestByteCount in [31, 33] {
            #expect(
                throws: Attempt.ControlRosterBinding.ValidationError
                    .invalidControlRosterDigestByteCount(actual: digestByteCount)
            ) {
                _ = try Attempt.ControlRosterBinding(
                    validatedControlIdentities: identities,
                    validatedControlRosterDigest: Array(
                        repeating: 0,
                        count: digestByteCount
                    )
                )
            }
        }

        var shortIdentityRoster = identities
        let shortIdentity = Attempt.ControlIdentity(
            validatedBytes: Array(repeating: 0, count: 31)
        )
        shortIdentityRoster[0] = shortIdentity
        #expect(
            throws: Attempt.ControlRosterBinding.ValidationError
                .invalidControlIdentityByteCount(shortIdentity, actual: 31)
        ) {
            _ = try Attempt.ControlRosterBinding(
                validatedControlIdentities: shortIdentityRoster,
                validatedControlRosterDigest: digest
            )
        }

        var duplicateRoster = identities
        duplicateRoster[6] = duplicateRoster[0]
        #expect(
            throws: Attempt.ControlRosterBinding.ValidationError
                .duplicateControlIdentity(identities[0])
        ) {
            _ = try Attempt.ControlRosterBinding(
                validatedControlIdentities: duplicateRoster,
                validatedControlRosterDigest: digest
            )
        }
    }

    @Test(
        "Accept and normalize complete commitment sets for every roster size",
        arguments: [7, 8, 9]
    )
    func validateCompleteCommitmentSet(candidateCount: Int) throws {
        let election = try makeElection(candidateCount: candidateCount)
        let reversed = try Attempt.RoleCommitmentSet(
            controlRoster: election.controlRoster,
            commitments: Array(election.commitments.reversed())
        )

        #expect(reversed == election.commitmentSet)
        #expect(
            reversed.commitments.map(\.candidate)
                == election.controlRoster.controlIdentities
        )
    }

    @Test("Reject incomplete duplicate unknown and malformed commitment sets")
    func rejectInvalidCommitmentSets() throws {
        let election = try makeElection(candidateCount: 7)
        let unknown = MosaicManifestSignatureFixtures.controlIdentity(scalarByte: 254)
        let first = election.commitments[0]
        let last = election.commitments[6]

        #expect(
            throws: Attempt.RoleCommitmentSet.ValidationError
                .missingCommitments([last.candidate])
        ) {
            _ = try Attempt.RoleCommitmentSet(
                controlRoster: election.controlRoster,
                commitments: Array(election.commitments.dropLast())
            )
        }

        var duplicate = election.commitments
        duplicate[6] = first
        #expect(
            throws: Attempt.RoleCommitmentSet.ValidationError
                .duplicateCandidate(first.candidate)
        ) {
            _ = try Attempt.RoleCommitmentSet(
                controlRoster: election.controlRoster,
                commitments: duplicate
            )
        }

        var unknownSet = election.commitments
        unknownSet[0] = .init(
            candidate: unknown,
            controlRosterDigest: election.controlRoster.controlRosterDigest,
            commitment: Array(repeating: 0x11, count: 32)
        )
        #expect(
            throws: Attempt.RoleCommitmentSet.ValidationError
                .unknownCandidate(unknown)
        ) {
            _ = try Attempt.RoleCommitmentSet(
                controlRoster: election.controlRoster,
                commitments: unknownSet
            )
        }

        var malformedRosterDigest = election.commitments
        malformedRosterDigest[0] = .init(
            candidate: first.candidate,
            controlRosterDigest: Array(repeating: 0, count: 31),
            commitment: first.commitment
        )
        #expect(
            throws: Attempt.RoleCommitmentSet.ValidationError
                .invalidControlRosterDigestByteCount(
                    candidate: first.candidate,
                    actual: 31
                )
        ) {
            _ = try Attempt.RoleCommitmentSet(
                controlRoster: election.controlRoster,
                commitments: malformedRosterDigest
            )
        }

        var wrongRosterDigest = election.commitments
        wrongRosterDigest[0] = .init(
            candidate: first.candidate,
            controlRosterDigest: Array(repeating: 0xFF, count: 32),
            commitment: first.commitment
        )
        #expect(
            throws: Attempt.RoleCommitmentSet.ValidationError
                .controlRosterDigestMismatch(first.candidate)
        ) {
            _ = try Attempt.RoleCommitmentSet(
                controlRoster: election.controlRoster,
                commitments: wrongRosterDigest
            )
        }

        for byteCount in [31, 33] {
            var malformedCommitment = election.commitments
            malformedCommitment[0] = .init(
                candidate: first.candidate,
                controlRosterDigest: first.controlRosterDigest,
                commitment: Array(repeating: 0, count: byteCount)
            )
            #expect(
                throws: Attempt.RoleCommitmentSet.ValidationError
                    .invalidCommitmentByteCount(
                        candidate: first.candidate,
                        actual: byteCount
                    )
            ) {
                _ = try Attempt.RoleCommitmentSet(
                    controlRoster: election.controlRoster,
                    commitments: malformedCommitment
                )
            }
        }
    }

    @Test("Validate one complete normalized reveal transcript through a profile seam")
    func validateRoleSeedRecord() throws {
        let election = try makeElection(candidateCount: 7)
        let validation = try Attempt.RoleSeedValidation(
            profile: .opalV0,
            commitmentSet: election.commitmentSet,
            reveals: Array(election.reveals.reversed()),
            using: MosaicRoleElectionFixtures.FixedSeedValidator(
                seed: election.validation.roleSeed
            )
        )

        #expect(validation == election.validation)
        #expect(
            validation.revealSet.reveals.map(\.candidate)
                == election.controlRoster.controlIdentities
        )
    }

    @Test("Reject incomplete duplicate unknown and malformed reveal transcripts")
    func rejectInvalidRevealSets() throws {
        let election = try makeElection(candidateCount: 7)
        let validator = MosaicRoleElectionFixtures.FixedSeedValidator(
            seed: Array(repeating: 0, count: 32)
        )
        let unknown = MosaicManifestSignatureFixtures.controlIdentity(scalarByte: 254)
        let first = election.reveals[0]
        let last = election.reveals[6]

        try expectRevealFailure(
            .missingReveals([last.candidate]),
            reveals: Array(election.reveals.dropLast()),
            election: election,
            validator: validator
        )

        var duplicate = election.reveals
        duplicate[6] = first
        try expectRevealFailure(
            .duplicateCandidate(first.candidate),
            reveals: duplicate,
            election: election,
            validator: validator
        )

        var unknownSet = election.reveals
        unknownSet[0] = .init(
            candidate: unknown,
            controlRosterDigest: election.controlRoster.controlRosterDigest,
            randomness: Array(repeating: 0x22, count: 32)
        )
        try expectRevealFailure(
            .unknownCandidate(unknown),
            reveals: unknownSet,
            election: election,
            validator: validator
        )

        var malformedRosterDigest = election.reveals
        malformedRosterDigest[0] = .init(
            candidate: first.candidate,
            controlRosterDigest: Array(repeating: 0, count: 31),
            randomness: first.randomness
        )
        try expectRevealFailure(
            .invalidControlRosterDigestByteCount(
                candidate: first.candidate,
                actual: 31
            ),
            reveals: malformedRosterDigest,
            election: election,
            validator: validator
        )

        var wrongRosterDigest = election.reveals
        wrongRosterDigest[0] = .init(
            candidate: first.candidate,
            controlRosterDigest: Array(repeating: 0xFF, count: 32),
            randomness: first.randomness
        )
        try expectRevealFailure(
            .controlRosterDigestMismatch(first.candidate),
            reveals: wrongRosterDigest,
            election: election,
            validator: validator
        )

        for byteCount in [31, 33] {
            var malformedRandomness = election.reveals
            malformedRandomness[0] = .init(
                candidate: first.candidate,
                controlRosterDigest: first.controlRosterDigest,
                randomness: Array(repeating: 0, count: byteCount)
            )
            try expectRevealFailure(
                .invalidRandomnessByteCount(
                    candidate: first.candidate,
                    actual: byteCount
                ),
                reveals: malformedRandomness,
                election: election,
                validator: validator
            )
        }
    }

    @Test("Fail closed on validator rejection and malformed derived seeds")
    func rejectInvalidRoleSeedValidation() throws {
        let election = try makeElection(candidateCount: 7)

        #expect(
            throws: Attempt.RoleSeedValidation.ValidationError.validatorRejected
        ) {
            _ = try Attempt.RoleSeedValidation(
                profile: .opalV0,
                commitmentSet: election.commitmentSet,
                reveals: election.reveals,
                using: MosaicRoleElectionFixtures.FixedSeedValidator(
                    seed: Array(repeating: 0, count: 32),
                    rejectsTranscript: true
                )
            )
        }

        for byteCount in [31, 33] {
            #expect(
                throws: Attempt.RoleSeedValidation.ValidationError
                    .invalidRoleSeedByteCount(actual: byteCount)
            ) {
                _ = try Attempt.RoleSeedValidation(
                    profile: .opalV0,
                    commitmentSet: election.commitmentSet,
                    reveals: election.reveals,
                    using: MosaicRoleElectionFixtures.FixedSeedValidator(
                        seed: Array(repeating: 0, count: byteCount)
                    )
                )
            }
        }
    }

    @Test(
        "Derive one conductor with explicit big-endian modulo selection",
        arguments: [7, 8, 9]
    )
    func deriveRosterFromValidatedSeed(candidateCount: Int) throws {
        let conductorIndex = candidateCount - 1
        let election = try makeElection(
            candidateCount: candidateCount,
            roleSeed: seed(selector: UInt64(conductorIndex))
        )
        let sortedIdentities = election.controlRoster.controlIdentities

        #expect(election.result.roster.members.map(\.controlIdentity) == sortedIdentities)
        #expect(
            election.result.roster.conductor
                == sortedIdentities[conductorIndex]
        )
        #expect(election.result.roster.contributors.count == candidateCount - 1)
        #expect(!election.result.roster.contributors.contains(election.result.roster.conductor))
    }

    @Test("Role selection is invariant to candidate commitment and reveal arrival order")
    func normalizeElectionOrder() throws {
        let identities = controlIdentities(count: 9)
        let forward = try MosaicRoleElectionFixtures.makeElection(
            controlIdentities: identities,
            roleSeed: seed(selector: 0x0102_0304_0506_0708)
        )
        let reversed = try MosaicRoleElectionFixtures.makeElection(
            controlIdentities: Array(identities.reversed()),
            roleSeed: seed(selector: 0x0102_0304_0506_0708)
        )

        #expect(forward.result == reversed.result)
    }

    @Test("Reject profile control-roster and commitment substitution")
    func rejectRoleElectionBindingSubstitution() throws {
        let election = try makeElection(candidateCount: 7)
        let wrongProfileValidation = try Attempt.RoleSeedValidation(
            profile: .draft1,
            commitmentSet: election.commitmentSet,
            reveals: election.reveals,
            using: MosaicRoleElectionFixtures.FixedSeedValidator(
                seed: election.validation.roleSeed
            )
        )
        #expect(
            throws: Attempt.RoleElectionResult.ValidationError.profileMismatch(
                expected: .opalV0,
                received: .draft1
            )
        ) {
            _ = try Attempt.RoleElectionResult(
                profile: .opalV0,
                commitmentSet: election.commitmentSet,
                validation: wrongProfileValidation
            )
        }

        let otherElection = try MosaicRoleElectionFixtures.makeElection(
            controlIdentities: controlIdentities(count: 7, scalarOffset: 1),
            profile: .opalV0,
            controlRosterDigestByte: 0xE1
        )
        #expect(
            throws: Attempt.RoleElectionResult.ValidationError.commitmentSetMismatch
        ) {
            _ = try Attempt.RoleElectionResult(
                profile: .opalV0,
                commitmentSet: election.commitmentSet,
                validation: otherElection.validation
            )
        }

        var changedCommitments = election.commitments
        changedCommitments[0] = .init(
            candidate: changedCommitments[0].candidate,
            controlRosterDigest: changedCommitments[0].controlRosterDigest,
            commitment: Array(repeating: 0xAB, count: 32)
        )
        let changedSet = try Attempt.RoleCommitmentSet(
            controlRoster: election.controlRoster,
            commitments: changedCommitments
        )
        #expect(
            throws: Attempt.RoleElectionResult.ValidationError.commitmentSetMismatch
        ) {
            _ = try Attempt.RoleElectionResult(
                profile: .opalV0,
                commitmentSet: changedSet,
                validation: election.validation
            )
        }
    }

    @Test("Reducer terminates malformed commitment and mismatched profile paths")
    func terminateInvalidReducerInputs() throws {
        let election = try makeElection(candidateCount: 7)
        var malformedAttempt = attemptAwaitingCommitments(election: election)
        let missingCommitments = Array(election.commitments.dropLast())
        let missingIdentity = election.commitments.last!.candidate
        let commitmentError = Attempt.RoleCommitmentSet.ValidationError
            .missingCommitments([missingIdentity])
        let commitmentFailure = Attempt.Failure.invalidRoleCommitmentSet(
            commitmentError
        )

        #expect(
            malformedAttempt.apply(
                input: .roleCommitmentsReceived(missingCommitments)
            ) == [.attemptTerminated(.failed(commitmentFailure))]
        )
        #expect(
            malformedAttempt.state == .terminal(.failed(commitmentFailure))
        )

        var wrongProfileAttempt = attemptAwaitingCommitments(election: election)
        _ = wrongProfileAttempt.apply(
            input: .roleCommitmentsReceived(election.commitments)
        )
        let wrongProfileValidation = try Attempt.RoleSeedValidation(
            profile: .draft1,
            commitmentSet: election.commitmentSet,
            reveals: election.reveals,
            using: MosaicRoleElectionFixtures.FixedSeedValidator(
                seed: election.validation.roleSeed
            )
        )
        let electionError = Attempt.RoleElectionResult.ValidationError
            .profileMismatch(expected: .opalV0, received: .draft1)
        let electionFailure = Attempt.Failure.invalidRoleElectionValidation(
            electionError
        )

        #expect(
            wrongProfileAttempt.apply(
                input: .roleElectionValidated(wrongProfileValidation)
            ) == [.attemptTerminated(.failed(electionFailure))]
        )
        #expect(
            wrongProfileAttempt.state == .terminal(.failed(electionFailure))
        )
    }

    @Test("Timeout and cancellation after commitments remain pre-reservation terminal")
    func terminateAfterCommitmentBarrier() throws {
        let election = try makeElection(candidateCount: 7)

        var timedOut = attemptAwaitingCommitments(election: election)
        _ = timedOut.apply(
            input: .roleCommitmentsReceived(election.commitments)
        )
        let timeoutFailure = Attempt.Failure.aborted(
            during: .roleSelection,
            reason: .timeout
        )
        #expect(
            timedOut.apply(input: .abort(.timeout))
                == [.attemptTerminated(.failed(timeoutFailure))]
        )

        var cancelled = attemptAwaitingCommitments(election: election)
        _ = cancelled.apply(
            input: .roleCommitmentsReceived(election.commitments)
        )
        #expect(
            cancelled.apply(input: .cancel)
                == [
                    .attemptTerminated(
                        .cancelled(.requested(during: .roleSelection))
                    )
                ]
        )
    }

    private func makeElection(
        candidateCount: Int,
        roleSeed: [UInt8] = Array(repeating: 0, count: 32)
    ) throws -> MosaicRoleElectionFixtures.Election {
        try MosaicRoleElectionFixtures.makeElection(
            controlIdentities: controlIdentities(count: candidateCount),
            roleSeed: roleSeed
        )
    }

    private func controlIdentities(
        count: Int,
        scalarOffset: UInt8 = 0
    ) -> [Attempt.ControlIdentity] {
        (0 ..< count).map {
            MosaicManifestSignatureFixtures.controlIdentity(
                scalarByte: scalarOffset &+ UInt8($0 + 1)
            )
        }
    }

    private func seed(selector: UInt64) -> [UInt8] {
        [
            UInt8(truncatingIfNeeded: selector >> 56),
            UInt8(truncatingIfNeeded: selector >> 48),
            UInt8(truncatingIfNeeded: selector >> 40),
            UInt8(truncatingIfNeeded: selector >> 32),
            UInt8(truncatingIfNeeded: selector >> 24),
            UInt8(truncatingIfNeeded: selector >> 16),
            UInt8(truncatingIfNeeded: selector >> 8),
            UInt8(truncatingIfNeeded: selector),
        ] + Array(repeating: 0, count: 24)
    }

    private func expectRevealFailure(
        _ error: Attempt.RoleRevealSet.ValidationError,
        reveals: [Attempt.RoleReveal],
        election: MosaicRoleElectionFixtures.Election,
        validator: MosaicRoleElectionFixtures.FixedSeedValidator
    ) throws {
        #expect(
            throws: Attempt.RoleSeedValidation.ValidationError
                .invalidRevealSet(error)
        ) {
            _ = try Attempt.RoleSeedValidation(
                profile: .opalV0,
                commitmentSet: election.commitmentSet,
                reveals: reveals,
                using: validator
            )
        }
    }

    private func attemptAwaitingCommitments(
        election: MosaicRoleElectionFixtures.Election
    ) -> Attempt {
        var attempt = Attempt(
            configuration: .init(profile: .opalV0)
        )
        _ = attempt.apply(
            input: .discoveryCompleted(
                candidateCount: election.controlRoster.candidateCount
            )
        )
        _ = attempt.apply(input: .candidateSetAgreementValidated)
        _ = attempt.apply(
            input: .controlRosterValidated(election.controlRoster)
        )
        return attempt
    }
}

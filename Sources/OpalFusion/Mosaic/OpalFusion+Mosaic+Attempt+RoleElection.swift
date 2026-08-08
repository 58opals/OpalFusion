// OpalFusion+Mosaic+Attempt+RoleElection.swift

extension OpalFusion.Mosaic.Attempt {
    /// The candidate identities and control-roster digest established by an upstream seam.
    ///
    /// The complete candidate-admission document remains unresolved. That seam must derive and
    /// validate `controlRosterDigest` before constructing this binding.
    struct ControlRosterBinding: Sendable, Equatable {
        enum ValidationError: Error, Sendable, Equatable {
            case invalidCandidateCount(actual: Int)
            case invalidControlRosterDigestByteCount(actual: Int)
            case invalidControlIdentityByteCount(ControlIdentity, actual: Int)
            case duplicateControlIdentity(ControlIdentity)
        }

        let controlIdentities: [ControlIdentity]
        let controlRosterDigest: [UInt8]

        init(
            validatedControlIdentities: [ControlIdentity],
            validatedControlRosterDigest: [UInt8]
        ) throws(ValidationError) {
            guard (7 ... 9).contains(validatedControlIdentities.count) else {
                throw ValidationError.invalidCandidateCount(
                    actual: validatedControlIdentities.count
                )
            }
            guard validatedControlRosterDigest.count == 32 else {
                throw ValidationError.invalidControlRosterDigestByteCount(
                    actual: validatedControlRosterDigest.count
                )
            }

            var seenControlIdentities: Set<ControlIdentity> = []
            for controlIdentity in validatedControlIdentities {
                guard controlIdentity.validatedBytes.count == 32 else {
                    throw ValidationError.invalidControlIdentityByteCount(
                        controlIdentity,
                        actual: controlIdentity.validatedBytes.count
                    )
                }
                guard seenControlIdentities.insert(controlIdentity).inserted else {
                    throw ValidationError.duplicateControlIdentity(controlIdentity)
                }
            }

            self.controlIdentities = validatedControlIdentities.sorted {
                $0.validatedBytes.lexicographicallyPrecedes($1.validatedBytes)
            }
            self.controlRosterDigest = Array(validatedControlRosterDigest)
        }

        var candidateCount: Int {
            controlIdentities.count
        }
    }

    /// One authenticated candidate's opaque role commitment.
    ///
    /// The commitment bytes remain opaque until a profile-owned role-seed validator checks the
    /// commitment/reveal construction frozen by that profile.
    struct RoleCommitment: Sendable, Equatable {
        let candidate: ControlIdentity
        let controlRosterDigest: [UInt8]
        let commitment: [UInt8]

        init(
            candidate: ControlIdentity,
            controlRosterDigest: [UInt8],
            commitment: [UInt8]
        ) {
            self.candidate = candidate
            self.controlRosterDigest = Array(controlRosterDigest)
            self.commitment = Array(commitment)
        }
    }

    /// The complete, normalized role-commitment set for one control roster.
    struct RoleCommitmentSet: Sendable, Equatable {
        enum ValidationError: Error, Sendable, Equatable {
            case unknownCandidate(ControlIdentity)
            case duplicateCandidate(ControlIdentity)
            case invalidControlRosterDigestByteCount(
                candidate: ControlIdentity,
                actual: Int
            )
            case controlRosterDigestMismatch(ControlIdentity)
            case invalidCommitmentByteCount(
                candidate: ControlIdentity,
                actual: Int
            )
            case missingCommitments([ControlIdentity])
        }

        let controlRoster: ControlRosterBinding
        let commitments: [RoleCommitment]

        init(
            controlRoster: ControlRosterBinding,
            commitments: [RoleCommitment]
        ) throws(ValidationError) {
            let expectedCandidates = Set(controlRoster.controlIdentities)
            var commitmentsByCandidate: [ControlIdentity: RoleCommitment] = [:]

            for commitment in commitments {
                guard expectedCandidates.contains(commitment.candidate) else {
                    throw ValidationError.unknownCandidate(commitment.candidate)
                }
                guard commitmentsByCandidate[commitment.candidate] == nil else {
                    throw ValidationError.duplicateCandidate(commitment.candidate)
                }
                guard commitment.controlRosterDigest.count == 32 else {
                    throw ValidationError.invalidControlRosterDigestByteCount(
                        candidate: commitment.candidate,
                        actual: commitment.controlRosterDigest.count
                    )
                }
                guard commitment.controlRosterDigest
                    == controlRoster.controlRosterDigest else {
                    throw ValidationError.controlRosterDigestMismatch(
                        commitment.candidate
                    )
                }
                guard commitment.commitment.count == 32 else {
                    throw ValidationError.invalidCommitmentByteCount(
                        candidate: commitment.candidate,
                        actual: commitment.commitment.count
                    )
                }
                commitmentsByCandidate[commitment.candidate] = commitment
            }

            let missingCommitments = controlRoster.controlIdentities.filter {
                commitmentsByCandidate[$0] == nil
            }
            guard missingCommitments.isEmpty else {
                throw ValidationError.missingCommitments(missingCommitments)
            }

            self.controlRoster = controlRoster
            self.commitments = controlRoster.controlIdentities.map {
                guard let commitment = commitmentsByCandidate[$0] else {
                    preconditionFailure(
                        "Complete role-commitment membership was validated before normalization."
                    )
                }
                return commitment
            }
        }
    }

    /// One authenticated candidate's opaque 32-byte role reveal.
    struct RoleReveal: Sendable, Equatable {
        let candidate: ControlIdentity
        let controlRosterDigest: [UInt8]
        let randomness: [UInt8]

        init(
            candidate: ControlIdentity,
            controlRosterDigest: [UInt8],
            randomness: [UInt8]
        ) {
            self.candidate = candidate
            self.controlRosterDigest = Array(controlRosterDigest)
            self.randomness = Array(randomness)
        }
    }

    /// The complete, normalized reveal set supplied to a profile-owned validator.
    struct RoleRevealSet: Sendable, Equatable {
        enum ValidationError: Error, Sendable, Equatable {
            case unknownCandidate(ControlIdentity)
            case duplicateCandidate(ControlIdentity)
            case invalidControlRosterDigestByteCount(
                candidate: ControlIdentity,
                actual: Int
            )
            case controlRosterDigestMismatch(ControlIdentity)
            case invalidRandomnessByteCount(
                candidate: ControlIdentity,
                actual: Int
            )
            case missingReveals([ControlIdentity])
        }

        let reveals: [RoleReveal]

        init(
            controlRoster: ControlRosterBinding,
            reveals: [RoleReveal]
        ) throws(ValidationError) {
            let expectedCandidates = Set(controlRoster.controlIdentities)
            var revealsByCandidate: [ControlIdentity: RoleReveal] = [:]

            for reveal in reveals {
                guard expectedCandidates.contains(reveal.candidate) else {
                    throw ValidationError.unknownCandidate(reveal.candidate)
                }
                guard revealsByCandidate[reveal.candidate] == nil else {
                    throw ValidationError.duplicateCandidate(reveal.candidate)
                }
                guard reveal.controlRosterDigest.count == 32 else {
                    throw ValidationError.invalidControlRosterDigestByteCount(
                        candidate: reveal.candidate,
                        actual: reveal.controlRosterDigest.count
                    )
                }
                guard reveal.controlRosterDigest
                    == controlRoster.controlRosterDigest else {
                    throw ValidationError.controlRosterDigestMismatch(reveal.candidate)
                }
                guard reveal.randomness.count == 32 else {
                    throw ValidationError.invalidRandomnessByteCount(
                        candidate: reveal.candidate,
                        actual: reveal.randomness.count
                    )
                }
                revealsByCandidate[reveal.candidate] = reveal
            }

            let missingReveals = controlRoster.controlIdentities.filter {
                revealsByCandidate[$0] == nil
            }
            guard missingReveals.isEmpty else {
                throw ValidationError.missingReveals(missingReveals)
            }

            self.reveals = controlRoster.controlIdentities.map {
                guard let reveal = revealsByCandidate[$0] else {
                    preconditionFailure(
                        "Complete role-reveal membership was validated before normalization."
                    )
                }
                return reveal
            }
        }
    }

    /// A profile-owned dependency that validates commitments against reveals and derives the seed.
    ///
    /// No production implementation exists until the selected profile freezes its role domains and
    /// canonical sorted-pair document.
    protocol RoleSeedValidating: Sendable {
        func validateAndDeriveSeed(
            profile: OpalFusion.Mosaic.Profile,
            controlRoster: ControlRosterBinding,
            commitments: [RoleCommitment],
            reveals: [RoleReveal]
        ) throws -> [UInt8]
    }

    /// Proof that a profile-owned validator accepted one exact commitment/reveal transcript.
    struct RoleSeedValidation: Sendable, Equatable {
        enum ValidationError: Error, Sendable, Equatable {
            case invalidRevealSet(RoleRevealSet.ValidationError)
            case validatorRejected
            case invalidRoleSeedByteCount(actual: Int)
        }

        let profile: OpalFusion.Mosaic.Profile
        let commitmentSet: RoleCommitmentSet
        let revealSet: RoleRevealSet
        let roleSeed: [UInt8]

        init<Validator: RoleSeedValidating>(
            profile: OpalFusion.Mosaic.Profile,
            commitmentSet: RoleCommitmentSet,
            reveals: [RoleReveal],
            using validator: Validator
        ) throws(ValidationError) {
            let revealSet: RoleRevealSet
            do {
                revealSet = try .init(
                    controlRoster: commitmentSet.controlRoster,
                    reveals: reveals
                )
            } catch {
                throw ValidationError.invalidRevealSet(error)
            }

            let roleSeed: [UInt8]
            do {
                roleSeed = try validator.validateAndDeriveSeed(
                    profile: profile,
                    controlRoster: commitmentSet.controlRoster,
                    commitments: commitmentSet.commitments,
                    reveals: revealSet.reveals
                )
            } catch {
                throw ValidationError.validatorRejected
            }
            guard roleSeed.count == 32 else {
                throw ValidationError.invalidRoleSeedByteCount(
                    actual: roleSeed.count
                )
            }

            self.profile = profile
            self.commitmentSet = commitmentSet
            self.revealSet = revealSet
            self.roleSeed = Array(roleSeed)
        }
    }

    /// The deterministic role result derived by the reducer from one validated 32-byte seed.
    struct RoleElectionResult: Sendable, Equatable {
        enum ValidationError: Error, Sendable, Equatable {
            case profileMismatch(
                expected: OpalFusion.Mosaic.Profile,
                received: OpalFusion.Mosaic.Profile
            )
            case commitmentSetMismatch
        }

        let profile: OpalFusion.Mosaic.Profile
        let controlRosterDigest: [UInt8]
        let roleSeed: [UInt8]
        let roster: Roster

        init(
            profile: OpalFusion.Mosaic.Profile,
            commitmentSet: RoleCommitmentSet,
            validation: RoleSeedValidation
        ) throws(ValidationError) {
            guard validation.profile == profile else {
                throw ValidationError.profileMismatch(
                    expected: profile,
                    received: validation.profile
                )
            }
            guard validation.commitmentSet == commitmentSet else {
                throw ValidationError.commitmentSetMismatch
            }

            let sortedControlIdentities = commitmentSet.controlRoster.controlIdentities
            let selector = validation.roleSeed.prefix(8).reduce(UInt64.zero) {
                ($0 << 8) | UInt64($1)
            }
            let conductorIndex = Int(selector % UInt64(sortedControlIdentities.count))
            let members = sortedControlIdentities.enumerated().map { index, identity in
                RosterMember(
                    controlIdentity: identity,
                    role: index == conductorIndex ? .conductor : .contributor
                )
            }

            let roster: Roster
            do {
                roster = try .init(members: members)
            } catch {
                preconditionFailure(
                    "A validated control roster and one selected index always form a valid roster."
                )
            }

            self.profile = profile
            self.controlRosterDigest = commitmentSet.controlRoster.controlRosterDigest
            self.roleSeed = validation.roleSeed
            self.roster = roster
        }
    }

    enum RoleSelectionState: Sendable, Equatable {
        case awaitingCommitments(ControlRosterBinding)
        case awaitingElectionValidation(RoleCommitmentSet)
    }
}

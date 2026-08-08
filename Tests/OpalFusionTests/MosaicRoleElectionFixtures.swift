// MosaicRoleElectionFixtures.swift

@testable import OpalFusion

enum MosaicRoleElectionFixtures {
    typealias Attempt = OpalFusion.Mosaic.Attempt

    struct Election {
        let controlRoster: Attempt.ControlRosterBinding
        let commitments: [Attempt.RoleCommitment]
        let commitmentSet: Attempt.RoleCommitmentSet
        let reveals: [Attempt.RoleReveal]
        let validation: Attempt.RoleSeedValidation
        let result: Attempt.RoleElectionResult
    }

    enum ValidatorFailure: Error {
        case rejected
    }

    struct FixedSeedValidator: Attempt.RoleSeedValidating {
        let seed: [UInt8]
        let rejectsTranscript: Bool

        init(
            seed: [UInt8],
            rejectsTranscript: Bool = false
        ) {
            self.seed = Array(seed)
            self.rejectsTranscript = rejectsTranscript
        }

        func validateAndDeriveSeed(
            profile _: OpalFusion.Mosaic.Profile,
            controlRoster _: Attempt.ControlRosterBinding,
            commitments _: [Attempt.RoleCommitment],
            reveals _: [Attempt.RoleReveal]
        ) throws -> [UInt8] {
            guard !rejectsTranscript else {
                throw ValidatorFailure.rejected
            }
            return seed
        }
    }

    static func makeElection(
        controlIdentities: [Attempt.ControlIdentity],
        profile: OpalFusion.Mosaic.Profile = .opalV0,
        controlRosterDigestByte: UInt8? = nil,
        roleSeed: [UInt8] = Array(repeating: 0, count: 32)
    ) throws -> Election {
        let controlRosterDigest: [UInt8]
        if let controlRosterDigestByte {
            controlRosterDigest = Array(
                repeating: controlRosterDigestByte,
                count: 32
            )
        } else if let firstIdentity = controlIdentities.min(by: {
            $0.validatedBytes.lexicographicallyPrecedes($1.validatedBytes)
        }) {
            controlRosterDigest = firstIdentity.validatedBytes.map { $0 ^ 0xA5 }
        } else {
            controlRosterDigest = []
        }
        let controlRoster = try Attempt.ControlRosterBinding(
            validatedControlIdentities: controlIdentities,
            validatedControlRosterDigest: controlRosterDigest
        )
        let commitments = controlIdentities.map { identity in
            Attempt.RoleCommitment(
                candidate: identity,
                controlRosterDigest: controlRoster.controlRosterDigest,
                commitment: identity.validatedBytes.map { $0 ^ 0x5A }
            )
        }
        let commitmentSet = try Attempt.RoleCommitmentSet(
            controlRoster: controlRoster,
            commitments: commitments
        )
        let reveals = controlIdentities.map { identity in
            Attempt.RoleReveal(
                candidate: identity,
                controlRosterDigest: controlRoster.controlRosterDigest,
                randomness: Array(identity.validatedBytes.reversed())
            )
        }
        let validation = try Attempt.RoleSeedValidation(
            profile: profile,
            commitmentSet: commitmentSet,
            reveals: reveals,
            using: FixedSeedValidator(seed: roleSeed)
        )
        let result = try Attempt.RoleElectionResult(
            profile: profile,
            commitmentSet: commitmentSet,
            validation: validation
        )
        return .init(
            controlRoster: controlRoster,
            commitments: commitments,
            commitmentSet: commitmentSet,
            reveals: reveals,
            validation: validation,
            result: result
        )
    }
}

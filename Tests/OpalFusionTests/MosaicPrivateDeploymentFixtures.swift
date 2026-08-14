// MosaicPrivateDeploymentFixtures.swift

import Foundation
import OpalCrypto
@testable import OpalFusion

enum MosaicPrivateDeploymentFixtures {
    typealias Alpha = OpalFusion.Mosaic.OpalMainnetAlpha
    typealias Attempt = OpalFusion.Mosaic.Attempt

    struct CandidateKeyMaterial: Sendable {
        let signingKey: OpalCrypto.Secp256k1.SigningKey
        let identity: OpalCrypto.Signature.BIP340.VerificationKey

        init(scalar: UInt8) throws {
            signingKey = try .init(
                rawRepresentation: Data(repeating: 0, count: 31) + Data([scalar])
            )
            identity = signingKey.bip340VerificationKey
        }

        var controlIdentity: Attempt.ControlIdentity {
            .init(validatedBytes: [UInt8](identity.rawRepresentation))
        }
    }

    struct Discovery: Sendable {
        let epochStart: UInt64
        let pool: Alpha.OpaquePoolDocument
        let relaySet: Alpha.RelaySetDocument
        let candidates: [CandidateKeyMaterial]
        let beacons: [Alpha.AvailabilityBeaconDocument]

        func candidate(
            for identity: OpalCrypto.Signature.BIP340.VerificationKey
        ) -> CandidateKeyMaterial {
            guard let candidate = candidates.first(where: {
                $0.identity == identity
            }) else {
                preconditionFailure("Every fixture beacon has one signing key.")
            }
            return candidate
        }
    }

    struct Formation: Sendable {
        let discovery: Discovery
        let selection: Alpha.CandidateSelectionValidation
        let acknowledgementSet: Alpha.CandidateSetAcknowledgementSetDocument
        let controlCandidates: [CandidateKeyMaterial]
        let controlRoster: Alpha.ControlRosterValidation
        let commitments: [Attempt.RoleCommitment]
        let reveals: [Attempt.RoleReveal]
        let roleElection: Attempt.RoleElectionResult
        let nonceAllocation: Alpha.ContributorNonceAllocationDocument

        func controlCandidate(
            for identity: Attempt.ControlIdentity
        ) -> CandidateKeyMaterial {
            guard let candidate = controlCandidates.first(where: {
                $0.controlIdentity == identity
            }) else {
                preconditionFailure("Every formation control identity has one key.")
            }
            return candidate
        }
    }

    static var discovery: Discovery {
        get throws { try makeDiscovery(candidateCount: 10) }
    }

    static func sign(
        digestBytes: [UInt8],
        using signingKey: OpalCrypto.Secp256k1.SigningKey,
        auxiliaryByte: UInt8
    ) throws -> [UInt8] {
        let signature = try signingKey.signBIP340(
            digest: .init(rawRepresentation: Data(digestBytes)),
            auxiliaryRandomness: .init(
                rawRepresentation: Data(repeating: auxiliaryByte, count: 32)
            )
        )
        return [UInt8](signature.rawRepresentation)
    }

    static func leadingZeroBitCount(in bytes: [UInt8]) -> UInt16 {
        var result: UInt16 = 0
        for byte in bytes {
            guard byte != 0 else {
                result += 8
                continue
            }
            result += UInt16(byte.leadingZeroBitCount)
            break
        }
        return result
    }
}

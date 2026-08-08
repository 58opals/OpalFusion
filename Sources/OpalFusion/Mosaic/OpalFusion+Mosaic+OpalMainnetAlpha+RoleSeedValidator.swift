// OpalFusion+Mosaic+OpalMainnetAlpha+RoleSeedValidator.swift

import Foundation
import OpalCrypto

extension OpalFusion.Mosaic.OpalMainnetAlpha {
    /// The production hash-document validator frozen by the mainnet-alpha profile.
    struct RoleSeedValidator: OpalFusion.Mosaic.Attempt.RoleSeedValidating {
        func validateAndDeriveSeed(
            profile: OpalFusion.Mosaic.Profile,
            controlRoster: OpalFusion.Mosaic.Attempt.ControlRosterBinding,
            commitments: [OpalFusion.Mosaic.Attempt.RoleCommitment],
            reveals: [OpalFusion.Mosaic.Attempt.RoleReveal]
        ) throws -> [UInt8] {
            guard profile == .opalMainnetAlpha else {
                throw ContractError.unsupportedProfile(profile)
            }
            guard commitments.count == controlRoster.candidateCount,
                  reveals.count == controlRoster.candidateCount else {
                throw ContractError.rosterMismatch
            }

            for (commitment, reveal) in zip(commitments, reveals) {
                guard commitment.candidate == reveal.candidate else {
                    throw ContractError.rosterMismatch
                }
                let expectedCommitment = Self.hash(
                    domainSuffix: "role-commitment",
                    fields: [
                        controlRoster.controlRosterDigest,
                        commitment.candidate.validatedBytes,
                        reveal.randomness
                    ]
                )
                guard commitment.commitment == expectedCommitment else {
                    throw ContractError.roleCommitmentMismatch
                }
            }

            var encoder = OpalFusion.Mosaic.CanonicalEncoder()
            try encoder.writeVector(Array(zip(commitments, reveals))) {
                encoder, pair in
                try encoder.writeFixedBytes(
                    pair.0.candidate.validatedBytes,
                    byteCount: OpalFusion.Mosaic.OpalV0.digestByteCount
                )
                try encoder.writeFixedBytes(
                    pair.1.randomness,
                    byteCount: OpalFusion.Mosaic.OpalV0.digestByteCount
                )
            }
            return Self.hash(
                domainSuffix: "role-seed",
                fields: [
                    controlRoster.controlRosterDigest,
                    encoder.encodedBytes
                ]
            )
        }

        static func roleCommitment(
            controlRosterDigest: [UInt8],
            controlIdentity: OpalFusion.Mosaic.Attempt.ControlIdentity,
            randomness: [UInt8]
        ) throws -> [UInt8] {
            try validateFixed(
                controlRosterDigest,
                field: .controlRosterDigest
            )
            try validateFixed(
                controlIdentity.validatedBytes,
                field: .controlIdentity
            )
            try validateFixed(randomness, field: .roleSeed)
            return hash(
                domainSuffix: "role-commitment",
                fields: [
                    controlRosterDigest,
                    controlIdentity.validatedBytes,
                    randomness
                ]
            )
        }

        static func hash(
            domainSuffix: String,
            fields: [[UInt8]]
        ) -> [UInt8] {
            var data = Data(
                "\(OpalFusion.Mosaic.Profile.opalMainnetAlpha.rawValue)/\(domainSuffix)".utf8
            )
            for field in fields {
                data.append(contentsOf: field)
            }
            return [UInt8](OpalCrypto.Hashing.sha256(data))
        }

        static func validateFixed(
            _ bytes: [UInt8],
            field: ContractError.Field,
            byteCount: Int = OpalFusion.Mosaic.OpalV0.digestByteCount
        ) throws {
            guard bytes.count == byteCount else {
                throw ContractError.invalidFixedByteCount(
                    field: field,
                    expected: byteCount,
                    actual: bytes.count
                )
            }
        }
    }
}

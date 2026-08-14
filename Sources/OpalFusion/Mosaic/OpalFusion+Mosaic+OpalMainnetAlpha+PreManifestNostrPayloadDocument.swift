// OpalFusion+Mosaic+OpalMainnetAlpha+PreManifestNostrPayloadDocument.swift

import Foundation
import OpalCrypto

extension OpalFusion.Mosaic.OpalMainnetAlpha {
    /// Strict canonical payload shared by every private-deployment coordination event.
    struct PreManifestNostrPayloadDocument: Sendable, Equatable {
        enum ValidationError: Error, Sendable, Equatable {
            case invalidSelector
            case invalidProtocolIdentifier
            case invalidNetworkGenesisHash
            case unknownPayloadKind(UInt8)
            case unknownSignerRole(UInt8)
            case signerRoleNotPermitted
            case signerNotInRoster
            case authorityMismatch
            case invalidDiscoveryEpoch
            case invalidExpiry
            case emptyBody
            case bodyTooLarge(actual: Int)
        }

        static let maximumBodyByteCount = 65_536

        let discoveryEpochStartUnixSeconds: UInt64
        let payloadKind: PrivateDeploymentNostrSelector.PayloadKind
        let signerRole: PrivateDeploymentNostrSelector.SignerRole
        let signerIdentity: OpalCrypto.Signature.BIP340.VerificationKey
        let expiryUnixSeconds: UInt64
        let body: [UInt8]

        var canonicalBytes: [UInt8] {
            var encoder = OpalFusion.Mosaic.CanonicalEncoder()
            do {
                try encoder.writeText(
                    PrivateDeploymentNostrSelector.identifier
                )
                try encoder.writeText(
                    OpalFusion.Mosaic.Profile.opalMainnetAlpha.rawValue
                )
                try encoder.writeFixedBytes(
                    OpalFusion.Mosaic.OpalMainnetAlpha.mainnetGenesisHash,
                    byteCount: 32
                )
                encoder.writeUInt64(discoveryEpochStartUnixSeconds)
                encoder.writeUInt8(payloadKind.rawValue)
                encoder.writeUInt8(signerRole.rawValue)
                try encoder.writeFixedBytes(
                    [UInt8](signerIdentity.rawRepresentation),
                    byteCount: 32
                )
                encoder.writeUInt64(expiryUnixSeconds)
                try encoder.writeBytes(body)
                return encoder.encodedBytes
            } catch {
                preconditionFailure("A validated pre-manifest payload must encode.")
            }
        }

        init(
            discoveryEpochStartUnixSeconds: UInt64,
            payloadKind: PrivateDeploymentNostrSelector.PayloadKind,
            signerRole: PrivateDeploymentNostrSelector.SignerRole,
            signerIdentity: OpalCrypto.Signature.BIP340.VerificationKey,
            expiryUnixSeconds: UInt64,
            body: [UInt8]
        ) throws(ValidationError) {
            let deadlines: PreManifestDeadlineSchedule
            do {
                deadlines = try PrivateDeploymentPolicy.frozen
                    .preManifestDeadlines(
                        forEpochStartingAt: discoveryEpochStartUnixSeconds
                    )
            } catch {
                throw .invalidDiscoveryEpoch
            }
            guard PrivateDeploymentNostrSelector.privateDeployment.allows(
                signerRole: signerRole,
                for: payloadKind
            ) else {
                throw .signerRoleNotPermitted
            }
            guard !body.isEmpty else { throw .emptyBody }
            guard body.count <= Self.maximumBodyByteCount else {
                throw .bodyTooLarge(actual: body.count)
            }
            let requiredExpiry: UInt64?
            switch payloadKind {
            case .availabilityBeacon:
                requiredExpiry = deadlines.beaconCutoff
            case .candidateSetAcknowledgement:
                requiredExpiry = deadlines.candidateSetAgreement
            case .candidateAdmission:
                requiredExpiry = deadlines.controlRosterAgreement
            case .roleCommitment:
                requiredExpiry = deadlines.roleCommitment
            case .roleReveal:
                requiredExpiry = deadlines.roleReveal
            case .contributorNonceAllocation:
                requiredExpiry = deadlines.manifestAgreement
            case .manifestProposal, .manifestSignature:
                requiredExpiry = deadlines.manifestAgreement
            case .abort, .completion:
                requiredExpiry = nil
            }
            guard expiryUnixSeconds > discoveryEpochStartUnixSeconds,
                  requiredExpiry == nil || expiryUnixSeconds == requiredExpiry else {
                throw .invalidExpiry
            }
            self.discoveryEpochStartUnixSeconds = discoveryEpochStartUnixSeconds
            self.payloadKind = payloadKind
            self.signerRole = signerRole
            self.signerIdentity = signerIdentity
            self.expiryUnixSeconds = expiryUnixSeconds
            self.body = Array(body)
        }

        static func decode(from encodedBytes: [UInt8]) throws -> Self {
            try OpalFusion.Mosaic.CanonicalDecoder.decode(
                from: encodedBytes
            ) { decoder in
                guard try decoder.readText()
                        == PrivateDeploymentNostrSelector.identifier else {
                    throw ValidationError.invalidSelector
                }
                guard try decoder.readText()
                        == OpalFusion.Mosaic.Profile.opalMainnetAlpha.rawValue else {
                    throw ValidationError.invalidProtocolIdentifier
                }
                guard try decoder.readFixedBytes(byteCount: 32)
                        == OpalFusion.Mosaic.OpalMainnetAlpha.mainnetGenesisHash else {
                    throw ValidationError.invalidNetworkGenesisHash
                }
                let epochStart = try decoder.readUInt64()
                let payloadKindRawValue = try decoder.readUInt8()
                guard let payloadKind = PrivateDeploymentNostrSelector.PayloadKind(
                    rawValue: payloadKindRawValue
                ) else {
                    throw ValidationError.unknownPayloadKind(payloadKindRawValue)
                }
                let signerRoleRawValue = try decoder.readUInt8()
                guard let signerRole = PrivateDeploymentNostrSelector.SignerRole(
                    rawValue: signerRoleRawValue
                ) else {
                    throw ValidationError.unknownSignerRole(signerRoleRawValue)
                }
                return try .init(
                    discoveryEpochStartUnixSeconds: epochStart,
                    payloadKind: payloadKind,
                    signerRole: signerRole,
                    signerIdentity: try .init(
                        rawRepresentation: Data(
                            decoder.readFixedBytes(byteCount: 32)
                        )
                    ),
                    expiryUnixSeconds: decoder.readUInt64(),
                    body: decoder.readBytes()
                )
            }
        }
    }
}

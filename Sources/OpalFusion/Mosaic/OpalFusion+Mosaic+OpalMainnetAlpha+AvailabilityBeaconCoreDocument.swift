// OpalFusion+Mosaic+OpalMainnetAlpha+AvailabilityBeaconCoreDocument.swift

import Foundation
import OpalCrypto

extension OpalFusion.Mosaic.OpalMainnetAlpha {
    /// Canonical unsigned availability fields covered by work and discovery signatures.
    struct AvailabilityBeaconCoreDocument: Sendable, Equatable {
        enum ValidationError: Error, Sendable, Equatable {
            case invalidSelector
            case invalidProtocolIdentifier
            case invalidNetworkGenesisHash
            case invalidOpaquePoolIdentifierByteCount(actual: Int)
            case invalidRelaySetDigestByteCount(actual: Int)
            case invalidDiscoveryEpoch
            case invalidExpiry
        }

        let discoveryEpochStartUnixSeconds: UInt64
        let opaquePoolIdentifier: [UInt8]
        let discoveryIdentity: OpalCrypto.Signature.BIP340.VerificationKey
        let relaySetDigest: [UInt8]
        let proofOfWorkNonce: UInt64
        let expiryUnixSeconds: UInt64

        var canonicalBytes: [UInt8] {
            var encoder = OpalFusion.Mosaic.CanonicalEncoder()
            do {
                try encoder.writeText(PrivateDeploymentNostrSelector.identifier)
                try encoder.writeText(OpalFusion.Mosaic.Profile.opalMainnetAlpha.rawValue)
                try encoder.writeFixedBytes(
                    OpalFusion.Mosaic.OpalMainnetAlpha.mainnetGenesisHash,
                    byteCount: 32
                )
                encoder.writeUInt64(discoveryEpochStartUnixSeconds)
                try encoder.writeFixedBytes(
                    opaquePoolIdentifier,
                    byteCount: OpalFusion.Mosaic.OpalMainnetAlpha
                        .opaquePoolIdentifierByteCount
                )
                try encoder.writeFixedBytes(
                    [UInt8](discoveryIdentity.rawRepresentation),
                    byteCount: 32
                )
                try encoder.writeFixedBytes(relaySetDigest, byteCount: 32)
                encoder.writeUInt64(proofOfWorkNonce)
                encoder.writeUInt64(expiryUnixSeconds)
                return encoder.encodedBytes
            } catch {
                preconditionFailure("A validated availability core must encode.")
            }
        }

        var workDigest: [UInt8] {
            RoleSeedValidator.hash(
                domainSuffix: "private-deployment/availability-beacon-work",
                fields: [
                    PrivateDeploymentNostrSelector.identifierBytes,
                    canonicalBytes,
                ]
            )
        }

        init(
            discoveryEpochStartUnixSeconds: UInt64,
            opaquePoolIdentifier: [UInt8],
            discoveryIdentity: OpalCrypto.Signature.BIP340.VerificationKey,
            relaySetDigest: [UInt8],
            proofOfWorkNonce: UInt64,
            expiryUnixSeconds: UInt64
        ) throws(ValidationError) {
            guard opaquePoolIdentifier.count
                    == OpalFusion.Mosaic.OpalMainnetAlpha
                        .opaquePoolIdentifierByteCount else {
                throw .invalidOpaquePoolIdentifierByteCount(
                    actual: opaquePoolIdentifier.count
                )
            }
            guard relaySetDigest.count == 32 else {
                throw .invalidRelaySetDigestByteCount(actual: relaySetDigest.count)
            }
            let deadlines: PreManifestDeadlineSchedule
            do {
                deadlines = try PrivateDeploymentPolicy.frozen
                    .preManifestDeadlines(
                        forEpochStartingAt: discoveryEpochStartUnixSeconds
                    )
            } catch {
                throw .invalidDiscoveryEpoch
            }
            guard expiryUnixSeconds == deadlines.beaconCutoff else {
                throw .invalidExpiry
            }
            self.discoveryEpochStartUnixSeconds = discoveryEpochStartUnixSeconds
            self.opaquePoolIdentifier = Array(opaquePoolIdentifier)
            self.discoveryIdentity = discoveryIdentity
            self.relaySetDigest = Array(relaySetDigest)
            self.proofOfWorkNonce = proofOfWorkNonce
            self.expiryUnixSeconds = expiryUnixSeconds
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
                let poolIdentifier = try decoder.readFixedBytes(
                    byteCount: OpalFusion.Mosaic.OpalMainnetAlpha
                        .opaquePoolIdentifierByteCount
                )
                let identity = try OpalCrypto.Signature.BIP340.VerificationKey(
                    rawRepresentation: Data(
                        decoder.readFixedBytes(byteCount: 32)
                    )
                )
                return try .init(
                    discoveryEpochStartUnixSeconds: epochStart,
                    opaquePoolIdentifier: poolIdentifier,
                    discoveryIdentity: identity,
                    relaySetDigest: decoder.readFixedBytes(byteCount: 32),
                    proofOfWorkNonce: decoder.readUInt64(),
                    expiryUnixSeconds: decoder.readUInt64()
                )
            }
        }
    }
}

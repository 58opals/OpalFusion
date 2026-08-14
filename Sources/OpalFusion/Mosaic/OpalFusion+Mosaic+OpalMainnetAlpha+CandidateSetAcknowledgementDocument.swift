// OpalFusion+Mosaic+OpalMainnetAlpha+CandidateSetAcknowledgementDocument.swift

import Foundation
import OpalCrypto

extension OpalFusion.Mosaic.OpalMainnetAlpha {
    /// One discovery-key acknowledgement of an exact candidate-set digest.
    struct CandidateSetAcknowledgementDocument: Sendable, Equatable {
        enum ValidationError: Error, Sendable, Equatable {
            case invalidSelector
            case invalidProtocolIdentifier
            case invalidNetworkGenesisHash
            case invalidCandidateSetDigestByteCount(actual: Int)
            case invalidDiscoveryEpoch
            case invalidExpiry
            case invalidSignature
        }

        let discoveryEpochStartUnixSeconds: UInt64
        let candidateSetDigest: [UInt8]
        let signerDiscoveryIdentity: OpalCrypto.Signature.BIP340.VerificationKey
        let expiryUnixSeconds: UInt64
        let signature: [UInt8]

        var canonicalBodyBytes: [UInt8] {
            var encoder = OpalFusion.Mosaic.CanonicalEncoder()
            do {
                try encoder.writeText(PrivateDeploymentNostrSelector.identifier)
                try encoder.writeText(OpalFusion.Mosaic.Profile.opalMainnetAlpha.rawValue)
                try encoder.writeFixedBytes(
                    OpalFusion.Mosaic.OpalMainnetAlpha.mainnetGenesisHash,
                    byteCount: 32
                )
                encoder.writeUInt64(discoveryEpochStartUnixSeconds)
                try encoder.writeFixedBytes(candidateSetDigest, byteCount: 32)
                try encoder.writeFixedBytes(
                    [UInt8](signerDiscoveryIdentity.rawRepresentation),
                    byteCount: 32
                )
                encoder.writeUInt64(expiryUnixSeconds)
                return encoder.encodedBytes
            } catch {
                preconditionFailure("A validated candidate acknowledgement body must encode.")
            }
        }

        var signatureDigest: [UInt8] {
            RoleSeedValidator.hash(
                domainSuffix: "private-deployment/candidate-set-acknowledgement",
                fields: [
                    PrivateDeploymentNostrSelector.identifierBytes,
                    canonicalBodyBytes,
                ]
            )
        }

        var canonicalBytes: [UInt8] {
            var encoder = OpalFusion.Mosaic.CanonicalEncoder()
            do {
                try encoder.writeText(PrivateDeploymentNostrSelector.identifier)
                try encoder.writeBytes(canonicalBodyBytes)
                try encoder.writeFixedBytes(signature, byteCount: 64)
                return encoder.encodedBytes
            } catch {
                preconditionFailure("A validated candidate acknowledgement must encode.")
            }
        }

        init(
            discoveryEpochStartUnixSeconds: UInt64,
            candidateSetDigest: [UInt8],
            signerDiscoveryIdentity: OpalCrypto.Signature.BIP340.VerificationKey,
            expiryUnixSeconds: UInt64,
            signature: [UInt8]
        ) throws(ValidationError) {
            let digest = try Self.deriveSignatureDigest(
                discoveryEpochStartUnixSeconds: discoveryEpochStartUnixSeconds,
                candidateSetDigest: candidateSetDigest,
                signerDiscoveryIdentity: signerDiscoveryIdentity,
                expiryUnixSeconds: expiryUnixSeconds
            )
            self.discoveryEpochStartUnixSeconds = discoveryEpochStartUnixSeconds
            self.candidateSetDigest = Array(candidateSetDigest)
            self.signerDiscoveryIdentity = signerDiscoveryIdentity
            self.expiryUnixSeconds = expiryUnixSeconds
            self.signature = Array(signature)
            guard PrivateDeploymentSignatureValidation.verify(
                signatureBytes: signature,
                digestBytes: digest,
                using: signerDiscoveryIdentity
            ) else {
                throw .invalidSignature
            }
        }

        static func deriveSignatureDigest(
            discoveryEpochStartUnixSeconds: UInt64,
            candidateSetDigest: [UInt8],
            signerDiscoveryIdentity: OpalCrypto.Signature.BIP340.VerificationKey,
            expiryUnixSeconds: UInt64
        ) throws(ValidationError) -> [UInt8] {
            guard candidateSetDigest.count == 32 else {
                throw .invalidCandidateSetDigestByteCount(
                    actual: candidateSetDigest.count
                )
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
            guard expiryUnixSeconds == deadlines.candidateSetAgreement else {
                throw .invalidExpiry
            }
            var encoder = OpalFusion.Mosaic.CanonicalEncoder()
            do {
                try encoder.writeText(PrivateDeploymentNostrSelector.identifier)
                try encoder.writeText(
                    OpalFusion.Mosaic.Profile.opalMainnetAlpha.rawValue
                )
                try encoder.writeFixedBytes(
                    OpalFusion.Mosaic.OpalMainnetAlpha.mainnetGenesisHash,
                    byteCount: 32
                )
                encoder.writeUInt64(discoveryEpochStartUnixSeconds)
                try encoder.writeFixedBytes(candidateSetDigest, byteCount: 32)
                try encoder.writeFixedBytes(
                    [UInt8](signerDiscoveryIdentity.rawRepresentation),
                    byteCount: 32
                )
                encoder.writeUInt64(expiryUnixSeconds)
            } catch {
                preconditionFailure("Validated acknowledgement fields must encode.")
            }
            return RoleSeedValidator.hash(
                domainSuffix: "private-deployment/candidate-set-acknowledgement",
                fields: [
                    PrivateDeploymentNostrSelector.identifierBytes,
                    encoder.encodedBytes,
                ]
            )
        }

        static func decode(from encodedBytes: [UInt8]) throws -> Self {
            try OpalFusion.Mosaic.CanonicalDecoder.decode(
                from: encodedBytes
            ) { decoder in
                guard try decoder.readText()
                        == PrivateDeploymentNostrSelector.identifier else {
                    throw ValidationError.invalidSelector
                }
                let bodyBytes = try decoder.readBytes()
                let signature = try decoder.readFixedBytes(byteCount: 64)
                return try OpalFusion.Mosaic.CanonicalDecoder.decode(
                    from: bodyBytes
                ) { bodyDecoder in
                    guard try bodyDecoder.readText()
                            == PrivateDeploymentNostrSelector.identifier else {
                        throw ValidationError.invalidSelector
                    }
                    guard try bodyDecoder.readText()
                            == OpalFusion.Mosaic.Profile.opalMainnetAlpha.rawValue else {
                        throw ValidationError.invalidProtocolIdentifier
                    }
                    guard try bodyDecoder.readFixedBytes(byteCount: 32)
                            == OpalFusion.Mosaic.OpalMainnetAlpha
                                .mainnetGenesisHash else {
                        throw ValidationError.invalidNetworkGenesisHash
                    }
                    return try .init(
                        discoveryEpochStartUnixSeconds: bodyDecoder.readUInt64(),
                        candidateSetDigest: bodyDecoder.readFixedBytes(byteCount: 32),
                        signerDiscoveryIdentity: try .init(
                            rawRepresentation: Data(
                                bodyDecoder.readFixedBytes(byteCount: 32)
                            )
                        ),
                        expiryUnixSeconds: bodyDecoder.readUInt64(),
                        signature: signature
                    )
                }
            }
        }
    }
}

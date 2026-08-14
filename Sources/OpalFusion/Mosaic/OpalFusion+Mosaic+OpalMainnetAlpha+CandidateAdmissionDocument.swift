// OpalFusion+Mosaic+OpalMainnetAlpha+CandidateAdmissionDocument.swift

import Foundation
import OpalCrypto

extension OpalFusion.Mosaic.OpalMainnetAlpha {
    /// Dual-signed discovery-to-control identity binding for one selected candidate.
    struct CandidateAdmissionDocument: Sendable, Equatable {
        enum ValidationError: Error, Sendable, Equatable {
            case invalidSelector
            case invalidProtocolIdentifier
            case invalidNetworkGenesisHash
            case invalidCandidateSetDigestByteCount(actual: Int)
            case invalidDiscoveryEpoch
            case invalidExpiry
            case invalidControlIdentity
            case identicalDiscoveryAndControlIdentity
            case invalidDiscoverySignature
            case invalidControlSignature
        }

        let discoveryEpochStartUnixSeconds: UInt64
        let candidateSetDigest: [UInt8]
        let discoveryIdentity: OpalCrypto.Signature.BIP340.VerificationKey
        let controlIdentity: OpalFusion.Mosaic.Attempt.ControlIdentity
        let expiryUnixSeconds: UInt64
        let discoverySignature: [UInt8]
        let controlSignature: [UInt8]

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
                    [UInt8](discoveryIdentity.rawRepresentation),
                    byteCount: 32
                )
                try encoder.writeFixedBytes(
                    controlIdentity.validatedBytes,
                    byteCount: 32
                )
                encoder.writeUInt64(expiryUnixSeconds)
                return encoder.encodedBytes
            } catch {
                preconditionFailure("A validated candidate admission body must encode.")
            }
        }

        var signatureDigest: [UInt8] {
            RoleSeedValidator.hash(
                domainSuffix: "private-deployment/candidate-admission",
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
                try encoder.writeFixedBytes(discoverySignature, byteCount: 64)
                try encoder.writeFixedBytes(controlSignature, byteCount: 64)
                return encoder.encodedBytes
            } catch {
                preconditionFailure("A validated candidate admission must encode.")
            }
        }

        init(
            discoveryEpochStartUnixSeconds: UInt64,
            candidateSetDigest: [UInt8],
            discoveryIdentity: OpalCrypto.Signature.BIP340.VerificationKey,
            controlIdentity: OpalFusion.Mosaic.Attempt.ControlIdentity,
            expiryUnixSeconds: UInt64,
            discoverySignature: [UInt8],
            controlSignature: [UInt8]
        ) throws(ValidationError) {
            let digest = try Self.deriveSignatureDigest(
                discoveryEpochStartUnixSeconds: discoveryEpochStartUnixSeconds,
                candidateSetDigest: candidateSetDigest,
                discoveryIdentity: discoveryIdentity,
                controlIdentity: controlIdentity,
                expiryUnixSeconds: expiryUnixSeconds
            )
            let controlVerificationKey = try Self.controlVerificationKey(
                for: controlIdentity
            )
            self.discoveryEpochStartUnixSeconds = discoveryEpochStartUnixSeconds
            self.candidateSetDigest = Array(candidateSetDigest)
            self.discoveryIdentity = discoveryIdentity
            self.controlIdentity = controlIdentity
            self.expiryUnixSeconds = expiryUnixSeconds
            self.discoverySignature = Array(discoverySignature)
            self.controlSignature = Array(controlSignature)
            guard PrivateDeploymentSignatureValidation.verify(
                signatureBytes: discoverySignature,
                digestBytes: digest,
                using: discoveryIdentity
            ) else {
                throw .invalidDiscoverySignature
            }
            guard PrivateDeploymentSignatureValidation.verify(
                signatureBytes: controlSignature,
                digestBytes: digest,
                using: controlVerificationKey
            ) else {
                throw .invalidControlSignature
            }
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
                let discoverySignature = try decoder.readFixedBytes(byteCount: 64)
                let controlSignature = try decoder.readFixedBytes(byteCount: 64)
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
                        discoveryIdentity: try .init(
                            rawRepresentation: Data(
                                bodyDecoder.readFixedBytes(byteCount: 32)
                            )
                        ),
                        controlIdentity: .init(
                            validatedBytes: bodyDecoder.readFixedBytes(byteCount: 32)
                        ),
                        expiryUnixSeconds: bodyDecoder.readUInt64(),
                        discoverySignature: discoverySignature,
                        controlSignature: controlSignature
                    )
                }
            }
        }
    }
}

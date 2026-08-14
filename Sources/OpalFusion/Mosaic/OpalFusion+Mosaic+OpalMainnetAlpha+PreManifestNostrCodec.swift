// OpalFusion+Mosaic+OpalMainnetAlpha+PreManifestNostrCodec.swift

import Foundation
import OpalCrypto

extension OpalFusion.Mosaic.OpalMainnetAlpha {
    /// Signs and validates the strict private-deployment Nostr event projection.
    enum PreManifestNostrCodec {
        enum ValidationError: Error, Sendable, Equatable {
            case signingIdentityMismatch
            case eventKindMismatch
            case invalidTags
            case invalidHexadecimalContent
            case nonCanonicalHexadecimalContent
            case signerIdentityMismatch
            case signerRoleMismatch
            case payloadKindMismatch
            case bodySignerIdentityMismatch
            case bodyDiscoveryEpochMismatch
            case bodyCandidateSetDigestMismatch
            case bodyManifestMismatch
            case unrecognizedSigner
            case invalidFormationProof
            case discoveryEpochMismatch
            case expiryMismatch
            case eventCreatedOutsideEpoch
            case eventCreatedBeforePayloadWindow
            case eventCreatedInFuture
            case expired
        }

        static func makeEvent(
            for payload: PreManifestNostrPayloadDocument,
            createdAtUnixSeconds: UInt64,
            using signingKey: OpalCrypto.Secp256k1.SigningKey,
            auxiliaryRandomness: OpalCrypto.Signature.BIP340.AuxiliaryRandomness,
            limits: OpalFusion.Mosaic.NostrNamespace.EventCodingLimits
        ) throws -> OpalFusion.Mosaic.NostrNamespace.Event {
            guard signingKey.bip340VerificationKey == payload.signerIdentity else {
                throw ValidationError.signingIdentityMismatch
            }
            guard createdAtUnixSeconds >= payload.discoveryEpochStartUnixSeconds,
                  createdAtUnixSeconds <= payload.expiryUnixSeconds else {
                throw ValidationError.eventCreatedOutsideEpoch
            }
            if payload.payloadKind == .contributorNonceAllocation {
                let deadlines = try PrivateDeploymentPolicy.frozen
                    .preManifestDeadlines(
                        forEpochStartingAt:
                            payload.discoveryEpochStartUnixSeconds
                    )
                guard createdAtUnixSeconds >= deadlines.roleReveal else {
                    throw ValidationError.eventCreatedBeforePayloadWindow
                }
            }
            let template = try OpalFusion.Mosaic.NostrNamespace.EventTemplate(
                createdAt: createdAtUnixSeconds,
                kind: PrivateDeploymentNostrSelector.privateDeployment.eventKind(
                    for: payload.payloadKind
                ),
                tags: [["d", PrivateDeploymentNostrSelector.identifier]],
                content: encodeHexadecimal(payload.canonicalBytes),
                limits: limits
            )
            return try OpalFusion.Mosaic.NostrNamespace.EventSigner.sign(
                template,
                using: signingKey,
                auxiliaryRandomness: auxiliaryRandomness,
                limits: limits
            )
        }

        static func decode(
            _ event: OpalFusion.Mosaic.NostrNamespace.Event,
            validating context: PreManifestNostrValidationContext
        ) throws -> PreManifestNostrPayloadDocument {
            guard event.template.tags
                    == [["d", PrivateDeploymentNostrSelector.identifier]] else {
                throw ValidationError.invalidTags
            }
            let payloadBytes = try decodeHexadecimal(event.template.content)
            guard encodeHexadecimal(payloadBytes) == event.template.content else {
                throw ValidationError.nonCanonicalHexadecimalContent
            }
            let payload = try PreManifestNostrPayloadDocument.decode(
                from: payloadBytes
            )
            guard event.template.kind
                    == PrivateDeploymentNostrSelector.privateDeployment.eventKind(
                        for: payload.payloadKind
                    ) else {
                throw ValidationError.eventKindMismatch
            }
            guard event.publicKey == payload.signerIdentity,
                  payload.signerIdentity == context.expectedSignerIdentity else {
                throw ValidationError.signerIdentityMismatch
            }
            guard payload.signerRole == context.expectedSignerRole else {
                throw ValidationError.signerRoleMismatch
            }
            guard payload.discoveryEpochStartUnixSeconds
                    == context.discoveryEpochStartUnixSeconds else {
                throw ValidationError.discoveryEpochMismatch
            }
            guard payload.expiryUnixSeconds
                    == context.expectedExpiryUnixSeconds else {
                throw ValidationError.expiryMismatch
            }
            guard event.template.createdAt
                    >= context.discoveryEpochStartUnixSeconds,
                  event.template.createdAt <= payload.expiryUnixSeconds else {
                throw ValidationError.eventCreatedOutsideEpoch
            }
            if payload.payloadKind == .contributorNonceAllocation {
                let deadlines = try PrivateDeploymentPolicy.frozen
                    .preManifestDeadlines(
                        forEpochStartingAt:
                            payload.discoveryEpochStartUnixSeconds
                    )
                guard event.template.createdAt >= deadlines.roleReveal else {
                    throw ValidationError.eventCreatedBeforePayloadWindow
                }
            }
            guard event.template.createdAt <= context.currentUnixSeconds else {
                throw ValidationError.eventCreatedInFuture
            }
            guard context.currentUnixSeconds <= payload.expiryUnixSeconds else {
                throw ValidationError.expired
            }
            return payload
        }

        private static func encodeHexadecimal(_ bytes: [UInt8]) -> String {
            let alphabet = Array("0123456789abcdef".utf8)
            var result: [UInt8] = []
            result.reserveCapacity(bytes.count * 2)
            for byte in bytes {
                result.append(alphabet[Int(byte >> 4)])
                result.append(alphabet[Int(byte & 0x0F)])
            }
            return String(decoding: result, as: UTF8.self)
        }

        private static func decodeHexadecimal(
            _ encoded: String
        ) throws(ValidationError) -> [UInt8] {
            let bytes = Array(encoded.utf8)
            guard bytes.count.isMultiple(of: 2) else {
                throw .invalidHexadecimalContent
            }
            var result: [UInt8] = []
            result.reserveCapacity(bytes.count / 2)
            var index = 0
            while index < bytes.count {
                guard let high = nibble(bytes[index]),
                      let low = nibble(bytes[index + 1]) else {
                    throw .invalidHexadecimalContent
                }
                result.append(high << 4 | low)
                index += 2
            }
            return result
        }

        private static func nibble(_ byte: UInt8) -> UInt8? {
            switch byte {
            case 0x30 ... 0x39: byte - 0x30
            case 0x61 ... 0x66: byte - 0x61 + 10
            default: nil
            }
        }
    }
}

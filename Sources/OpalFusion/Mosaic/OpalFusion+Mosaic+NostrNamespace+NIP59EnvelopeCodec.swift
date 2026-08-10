// OpalFusion+Mosaic+NostrNamespace+NIP59EnvelopeCodec.swift

import Foundation
import OpalCrypto

extension OpalFusion.Mosaic.NostrNamespace {
    /// Strict structural support for the NIP-59 rumor, seal, and gift-wrap layers.
    ///
    /// Outbound encryption uses fresh NIP-44 nonces, and each gift wrap uses a
    /// newly generated wrapper key. Inbound validation can prove signed identity
    /// separation but cannot prove that a remote wrapper key was never reused.
    ///
    /// This codec deliberately does not assign an application rumor kind, timestamp
    /// policy, fixed outer size, proof of work, relay policy, or Mosaic runtime fact.
    enum NIP59EnvelopeCodec {
        private static let sealKind: UInt16 = 13

        /// A signed seal bound to the recipient used for its NIP-44 conversation key.
        struct SealedRumor: Sendable, Equatable {
            let event: Event
            let recipientPublicKey: OpalCrypto.Signature.BIP340.VerificationKey

            fileprivate init(
                event: Event,
                recipientPublicKey: OpalCrypto.Signature.BIP340.VerificationKey
            ) {
                self.event = event
                self.recipientPublicKey = recipientPublicKey
            }
        }

        static func seal(
            _ rumor: UnsignedEvent,
            createdAt: UInt64,
            senderSigningKey: OpalCrypto.Secp256k1.SigningKey,
            recipientPublicKey: OpalCrypto.Signature.BIP340.VerificationKey,
            limits: CodingLimits
        ) throws -> SealedRumor {
            guard rumor.publicKey == senderSigningKey.bip340VerificationKey else {
                throw Error.rumorAuthorMismatch
            }
            let rumorData = try UnsignedEventCodec.encode(
                rumor,
                limits: limits.event
            )
            try validateRumorByteCount(rumorData.count, limits: limits)
            let event = try EncryptedEventCodec.encrypt(
                String(decoding: rumorData, as: UTF8.self),
                kind: sealKind,
                createdAt: createdAt,
                tags: [],
                senderSigningKey: senderSigningKey,
                recipientPublicKey: recipientPublicKey,
                auxiliaryRandomness: freshAuxiliaryRandomness(),
                maximumPlaintextByteCount: limits.maximumRumorJSONByteCount,
                eventLimits: limits.event
            )
            return SealedRumor(
                event: event,
                recipientPublicKey: recipientPublicKey
            )
        }

        static func wrap(
            _ sealedRumor: SealedRumor,
            deliveryKind: DeliveryKind,
            createdAt: UInt64,
            additionalTags: [[String]] = [],
            limits: CodingLimits
        ) throws -> Event {
            let seal = sealedRumor.event
            let recipientPublicKey = sealedRumor.recipientPublicKey
            let wrapperSigningKey = try OpalCrypto.Secp256k1.PrivateKey
                .generate()
                .makeSigningKey()
            let wrapperPublicKey = wrapperSigningKey.bip340VerificationKey
            guard wrapperPublicKey != seal.publicKey,
                  wrapperPublicKey != recipientPublicKey else {
                throw Error.wrapperIdentityCollision
            }
            let sealData = try EventCodec.encode(seal, limits: limits.event)
            try validateSealByteCount(sealData.count, limits: limits)
            let tags = [recipientTag(recipientPublicKey)] + additionalTags
            try validateRecipientTags(
                tags,
                expectedRecipient: recipientPublicKey
            )
            return try EncryptedEventCodec.encrypt(
                String(decoding: sealData, as: UTF8.self),
                kind: deliveryKind.rawValue,
                createdAt: createdAt,
                tags: tags,
                senderSigningKey: wrapperSigningKey,
                recipientPublicKey: recipientPublicKey,
                auxiliaryRandomness: freshAuxiliaryRandomness(),
                maximumPlaintextByteCount: limits.maximumSealJSONByteCount,
                eventLimits: limits.event
            )
        }

        static func open(
            _ giftWrap: Event,
            expectedDeliveryKind: DeliveryKind,
            expectedRumorKind: UInt16,
            recipientSigningKey: OpalCrypto.Secp256k1.SigningKey,
            limits: CodingLimits
        ) throws -> AuthenticatedRumor {
            guard giftWrap.template.kind == expectedDeliveryKind.rawValue else {
                throw Error.unexpectedGiftWrapKind(
                    expected: expectedDeliveryKind.rawValue,
                    actual: giftWrap.template.kind
                )
            }
            let recipientPublicKey = recipientSigningKey.bip340VerificationKey
            try validateRecipientTags(
                giftWrap.template.tags,
                expectedRecipient: recipientPublicKey
            )
            guard giftWrap.publicKey != recipientPublicKey else {
                throw Error.wrapperIdentityCollision
            }

            let sealString = try decrypt(
                giftWrap,
                recipientSigningKey: recipientSigningKey,
                maximumPlaintextByteCount: limits.maximumSealJSONByteCount,
                eventLimits: limits.event
            )
            let sealData = Data(sealString.utf8)
            try validateSealByteCount(sealData.count, limits: limits)
            let seal = try EventCodec.decode(sealData, limits: limits.event)
            try validateSeal(seal)
            guard giftWrap.publicKey != seal.publicKey else {
                throw Error.wrapperIdentityCollision
            }

            let rumorString = try decrypt(
                seal,
                recipientSigningKey: recipientSigningKey,
                maximumPlaintextByteCount: limits.maximumRumorJSONByteCount,
                eventLimits: limits.event
            )
            let rumorData = Data(rumorString.utf8)
            try validateRumorByteCount(rumorData.count, limits: limits)
            let rumor = try UnsignedEventCodec.decode(
                rumorData,
                limits: limits.event
            )
            guard rumor.publicKey == seal.publicKey else {
                throw Error.rumorAuthorMismatch
            }
            guard rumor.template.kind == expectedRumorKind else {
                throw Error.unexpectedRumorKind(
                    expected: expectedRumorKind,
                    actual: rumor.template.kind
                )
            }

            return AuthenticatedRumor(
                rumor: rumor,
                recipientPublicKey: recipientPublicKey,
                sealIdentifier: seal.identifier,
                giftWrapIdentifier: giftWrap.identifier,
                sealCreatedAt: seal.template.createdAt,
                giftWrapCreatedAt: giftWrap.template.createdAt,
                rumorJSONByteCount: rumorData.count,
                sealContentByteCount: seal.template.content.utf8.count,
                sealJSONByteCount: sealData.count,
                giftWrapContentByteCount: giftWrap.template.content.utf8.count,
                deliveryKind: expectedDeliveryKind
            )
        }

        private static func decrypt(
            _ event: Event,
            recipientSigningKey: OpalCrypto.Secp256k1.SigningKey,
            maximumPlaintextByteCount: Int,
            eventLimits: EventCodingLimits
        ) throws -> String {
            let payload = try OpalCrypto.Nostr.NIP44.Payload(
                encodedRepresentation: event.template.content,
                maximumEncodedPayloadByteCount: eventLimits.maximumStringByteCount
            )
            let conversationKey = OpalCrypto.Nostr.NIP44.deriveConversationKey(
                signingKey: recipientSigningKey,
                publicKey: event.publicKey
            )
            return try OpalCrypto.Nostr.NIP44.decrypt(
                payload,
                conversationKey: conversationKey,
                maximumPlaintextByteCount: maximumPlaintextByteCount
            )
        }

        private static func validateSeal(_ seal: Event) throws {
            guard seal.template.kind == sealKind else {
                throw Error.invalidSealKind(actual: seal.template.kind)
            }
            guard seal.template.tags.isEmpty else {
                throw Error.invalidSealTags
            }
        }

        private static func validateRumorByteCount(
            _ actual: Int,
            limits: CodingLimits
        ) throws {
            guard actual <= limits.maximumRumorJSONByteCount else {
                throw Error.rumorJSONByteCountExceedsMaximum(
                    maximum: limits.maximumRumorJSONByteCount,
                    actual: actual
                )
            }
        }

        private static func validateSealByteCount(
            _ actual: Int,
            limits: CodingLimits
        ) throws {
            guard actual <= limits.maximumSealJSONByteCount else {
                throw Error.sealJSONByteCountExceedsMaximum(
                    maximum: limits.maximumSealJSONByteCount,
                    actual: actual
                )
            }
        }

        private static func recipientTag(
            _ recipientPublicKey: OpalCrypto.Signature.BIP340.VerificationKey
        ) -> [String] {
            ["p", EventCodec.hexadecimal(recipientPublicKey.rawRepresentation)]
        }

        private static func validateRecipientTags(
            _ tags: [[String]],
            expectedRecipient: OpalCrypto.Signature.BIP340.VerificationKey
        ) throws {
            let recipientTags = tags.filter { $0.first == "p" }
            guard recipientTags == [recipientTag(expectedRecipient)] else {
                throw Error.invalidGiftWrapTags
            }
        }

        private static func freshAuxiliaryRandomness()
            throws -> OpalCrypto.Signature.BIP340.AuxiliaryRandomness {
            try .init(
                rawRepresentation: OpalCrypto.SecureRandom.makeBytes(count: 32)
            )
        }
    }
}

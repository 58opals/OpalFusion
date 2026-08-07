// OpalFusion+Mosaic+Nostr+EncryptedEventCodec.swift

import OpalCrypto

extension OpalFusion.Mosaic.Nostr {
    /// NIP-44 content carried only by a validated, signed NIP-01 event.
    ///
    /// Mosaic event kinds, tags, fixed outer sizes, and timing remain injected
    /// profile decisions. This codec does not assign any of them.
    enum EncryptedEventCodec {
        enum Error: Swift.Error, Sendable, Equatable {
            case unexpectedKind(expected: UInt16, actual: UInt16)
            case unexpectedSender
        }

        static func encrypt(
            _ plaintext: String,
            kind: UInt16,
            createdAt: UInt64,
            tags: [[String]],
            senderSigningKey: OpalCrypto.Secp256k1.SigningKey,
            recipientPublicKey: OpalCrypto.Signature.BIP340.VerificationKey,
            auxiliaryRandomness: OpalCrypto.Signature.BIP340.AuxiliaryRandomness,
            maximumPlaintextByteCount: Int,
            eventLimits: EventCodingLimits
        ) throws -> Event {
            let conversationKey = OpalCrypto.Nostr.NIP44
                .deriveConversationKey(
                    signingKey: senderSigningKey,
                    publicKey: recipientPublicKey
                )
            let encrypted = try OpalCrypto.Nostr.NIP44.encrypt(
                plaintext,
                conversationKey: conversationKey,
                maximumPlaintextByteCount: maximumPlaintextByteCount
            )
            let template = try EventTemplate(
                createdAt: createdAt,
                kind: kind,
                tags: tags,
                content: encrypted.encodedRepresentation,
                limits: eventLimits
            )
            return try EventSigner.sign(
                template,
                using: senderSigningKey,
                auxiliaryRandomness: auxiliaryRandomness,
                limits: eventLimits
            )
        }

        static func decrypt(
            _ event: Event,
            expectedKind: UInt16,
            expectedSender: OpalCrypto.Signature.BIP340.VerificationKey,
            recipientSigningKey: OpalCrypto.Secp256k1.SigningKey,
            maximumEncodedPayloadByteCount: Int,
            maximumPlaintextByteCount: Int
        ) throws -> String {
            guard event.template.kind == expectedKind else {
                throw Error.unexpectedKind(
                    expected: expectedKind,
                    actual: event.template.kind
                )
            }
            guard event.publicKey == expectedSender else {
                throw Error.unexpectedSender
            }
            let payload = try OpalCrypto.Nostr.NIP44.Payload(
                encodedRepresentation: event.template.content,
                maximumEncodedPayloadByteCount:
                    maximumEncodedPayloadByteCount
            )
            let conversationKey = OpalCrypto.Nostr.NIP44
                .deriveConversationKey(
                    signingKey: recipientSigningKey,
                    publicKey: event.publicKey
                )
            return try OpalCrypto.Nostr.NIP44.decrypt(
                payload,
                conversationKey: conversationKey,
                maximumPlaintextByteCount: maximumPlaintextByteCount
            )
        }
    }
}

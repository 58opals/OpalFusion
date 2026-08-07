// MosaicNostrEncryptedEventCodecValidator.swift

import Foundation
import OpalCrypto
import Testing
@testable import OpalFusion

@Suite("Mosaic Nostr authenticated encrypted-event validation")
struct MosaicNostrEncryptedEventCodecValidator {
    typealias Nostr = OpalFusion.Mosaic.Nostr

    @Test("Decrypt only after strict outer-event validation")
    func decryptOnlyAfterOuterEventValidation() throws {
        let sender = try signingKey(1)
        let recipient = try signingKey(2)
        let event = try Nostr.EncryptedEventCodec.encrypt(
            "authenticated Mosaic payload",
            kind: 31_337,
            createdAt: 1_700_000_000,
            tags: [["p", hexadecimal(recipient.bip340VerificationKey.rawRepresentation)]],
            senderSigningKey: sender,
            recipientPublicKey: recipient.bip340VerificationKey,
            auxiliaryRandomness: .init(
                rawRepresentation: Data(repeating: 0x42, count: 32)
            ),
            maximumPlaintextByteCount: 128,
            eventLimits: limits
        )
        let encoded = try Nostr.EventCodec.encode(event, limits: limits)
        let validated = try Nostr.EventCodec.decode(encoded, limits: limits)

        let plaintext = try Nostr.EncryptedEventCodec.decrypt(
            validated,
            expectedKind: 31_337,
            expectedSender: sender.bip340VerificationKey,
            recipientSigningKey: recipient,
            maximumEncodedPayloadByteCount: validated.template.content.utf8.count,
            maximumPlaintextByteCount: 128
        )

        #expect(plaintext == "authenticated Mosaic payload")

        let tampered = String(decoding: encoded, as: UTF8.self)
            .replacingOccurrences(of: "\"content\":\"A", with: "\"content\":\"B")
        #expect(throws: Nostr.EventCodingError.self) {
            _ = try Nostr.EventCodec.decode(
                Data(tampered.utf8),
                limits: limits
            )
        }
    }

    @Test("Reject cross-kind cross-sender and wrong-recipient decryption")
    func rejectContextAndRecipientMismatch() throws {
        let sender = try signingKey(3)
        let recipient = try signingKey(4)
        let outsider = try signingKey(5)
        let event = try Nostr.EncryptedEventCodec.encrypt(
            "x",
            kind: 1_234,
            createdAt: 1,
            tags: [],
            senderSigningKey: sender,
            recipientPublicKey: recipient.bip340VerificationKey,
            auxiliaryRandomness: .init(
                rawRepresentation: Data(repeating: 0x24, count: 32)
            ),
            maximumPlaintextByteCount: 1,
            eventLimits: limits
        )

        #expect(
            throws: Nostr.EncryptedEventCodec.Error
                .unexpectedKind(expected: 4_321, actual: 1_234)
        ) {
            _ = try Nostr.EncryptedEventCodec.decrypt(
                event,
                expectedKind: 4_321,
                expectedSender: sender.bip340VerificationKey,
                recipientSigningKey: recipient,
                maximumEncodedPayloadByteCount: event.template.content.utf8.count,
                maximumPlaintextByteCount: 1
            )
        }
        #expect(throws: Nostr.EncryptedEventCodec.Error.unexpectedSender) {
            _ = try Nostr.EncryptedEventCodec.decrypt(
                event,
                expectedKind: 1_234,
                expectedSender: outsider.bip340VerificationKey,
                recipientSigningKey: recipient,
                maximumEncodedPayloadByteCount: event.template.content.utf8.count,
                maximumPlaintextByteCount: 1
            )
        }
        #expect(throws: OpalCrypto.Nostr.NIP44.Error.authenticationFailed) {
            _ = try Nostr.EncryptedEventCodec.decrypt(
                event,
                expectedKind: 1_234,
                expectedSender: sender.bip340VerificationKey,
                recipientSigningKey: outsider,
                maximumEncodedPayloadByteCount: event.template.content.utf8.count,
                maximumPlaintextByteCount: 1
            )
        }
    }

    private var limits: Nostr.EventCodingLimits {
        get throws {
            try .init(
                maximumEventJSONByteCount: 8_192,
                maximumTagCount: 8,
                maximumTagElementCount: 4,
                maximumStringByteCount: 4_096
            )
        }
    }

    private func signingKey(
        _ value: UInt8
    ) throws -> OpalCrypto.Secp256k1.SigningKey {
        try .init(
            rawRepresentation: Data(repeating: 0, count: 31) + Data([value])
        )
    }

    private func hexadecimal(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }
}

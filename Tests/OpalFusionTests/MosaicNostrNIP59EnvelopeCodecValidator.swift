// MosaicNostrNIP59EnvelopeCodecValidator.swift

import Foundation
import OpalCrypto
import Testing
@testable import OpalFusion

@Suite("Mosaic Nostr NIP-59 structural validation")
struct MosaicNostrNIP59EnvelopeCodecValidator {
    typealias Nostr = OpalFusion.Mosaic.NostrNamespace
    typealias Codec = Nostr.NIP59EnvelopeCodec

    @Test(
        "Authenticate the seal author for either official gift-wrap kind",
        arguments: Codec.DeliveryKind.allCases
    )
    func roundTrip(_ deliveryKind: Codec.DeliveryKind) throws {
        let sender = try signingKey(1)
        let recipient = try signingKey(2)
        let rumor = try makeRumor(author: sender, kind: 42_042)
        let seal = try Codec.seal(
            rumor,
            createdAt: 1_700_000_001,
            senderSigningKey: sender,
            recipientPublicKey: recipient.bip340VerificationKey,
            limits: codingLimits
        )
        let giftWrap = try Codec.wrap(
            seal,
            deliveryKind: deliveryKind,
            createdAt: 1_700_000_002,
            limits: codingLimits
        )

        let encoded = try Nostr.EventCodec.encode(
            giftWrap,
            limits: codingLimits.event
        )
        let validated = try Nostr.EventCodec.decode(
            encoded,
            limits: codingLimits.event
        )
        let opened = try Codec.open(
            validated,
            expectedDeliveryKind: deliveryKind,
            expectedRumorKind: 42_042,
            recipientSigningKey: recipient,
            limits: codingLimits
        )

        #expect(opened.rumor == rumor)
        #expect(opened.senderPublicKey == sender.bip340VerificationKey)
        #expect(opened.recipientPublicKey == recipient.bip340VerificationKey)
        #expect(opened.sealIdentifier == seal.event.identifier)
        #expect(opened.giftWrapIdentifier == giftWrap.identifier)
        #expect(opened.deliveryKind == deliveryKind)
        #expect(giftWrap.publicKey != opened.senderPublicKey)
    }

    @Test("Generate fresh independent outbound seal and wrapper material")
    func generateFreshOutboundMaterial() throws {
        let sender = try signingKey(39)
        let recipient = try signingKey(40)
        let rumor = try makeRumor(author: sender, kind: 40_040)
        let firstSeal = try Codec.seal(
            rumor,
            createdAt: 1_700_000_001,
            senderSigningKey: sender,
            recipientPublicKey: recipient.bip340VerificationKey,
            limits: codingLimits
        )
        let secondSeal = try Codec.seal(
            rumor,
            createdAt: 1_700_000_001,
            senderSigningKey: sender,
            recipientPublicKey: recipient.bip340VerificationKey,
            limits: codingLimits
        )
        #expect(firstSeal.event.template.content != secondSeal.event.template.content)
        #expect(firstSeal.event.identifier != secondSeal.event.identifier)

        let firstWrap = try Codec.wrap(
            firstSeal,
            deliveryKind: .regular,
            createdAt: 1_700_000_002,
            limits: codingLimits
        )
        let secondWrap = try Codec.wrap(
            firstSeal,
            deliveryKind: .regular,
            createdAt: 1_700_000_002,
            limits: codingLimits
        )
        #expect(firstWrap.publicKey != secondWrap.publicKey)
        #expect(firstWrap.identifier != secondWrap.identifier)
        #expect(firstWrap.publicKey != sender.bip340VerificationKey)
        #expect(firstWrap.publicKey != recipient.bip340VerificationKey)
    }

    @Test("Match independent deterministic inbound identifiers")
    func deterministicInboundIdentifiers() throws {
        let sender = try signingKey(31)
        let recipient = try signingKey(32)
        let wrapper = try signingKey(33)
        let rumor = try makeRumor(author: sender, kind: 42_042)
        let rumorJSON = try Nostr.UnsignedEventCodec.encode(
            rumor,
            limits: codingLimits.event
        )
        let seal = try encryptedEvent(
            plaintext: String(decoding: rumorJSON, as: UTF8.self),
            kind: 13,
            tags: [],
            signingKey: sender,
            recipient: recipient,
            nonceByte: 0x91,
            auxiliaryRandomnessByte: 0x92,
            createdAt: 1_700_000_001
        )
        let sealJSON = try Nostr.EventCodec.encode(
            seal,
            limits: codingLimits.event
        )

        #expect(
            hexadecimal(rumor.identifier.rawRepresentation)
                == "798f41e5bc1d4f63ea0926c781029b11c8a010c41aec7e149a5da1800c75450d"
        )
        #expect(
            hexadecimal(seal.identifier.rawRepresentation)
                == "9e92f564c02e2615c3018af2f9034fdec4435f1813690d4d7484e4f97529b73c"
        )
        for (deliveryKind, nonceByte, auxiliaryByte, expectedIdentifier) in [
            (
                Codec.DeliveryKind.regular,
                UInt8(0x93),
                UInt8(0x94),
                "a37fde505e288fcb6dfd15622768109e536a2ff4f0bbbdb7897052a9158376ae"
            ),
            (
                .ephemeral,
                UInt8(0x95),
                UInt8(0x96),
                "154a0796ea2bde98fd976595cee5d2709185acd40c62fccd3c4f614bf2c33ddb"
            )
        ] {
            let giftWrap = try encryptedEvent(
                plaintext: String(decoding: sealJSON, as: UTF8.self),
                kind: deliveryKind.rawValue,
                tags: [recipientTag(recipient)],
                signingKey: wrapper,
                recipient: recipient,
                nonceByte: nonceByte,
                auxiliaryRandomnessByte: auxiliaryByte,
                createdAt: 1_700_000_002
            )
            #expect(
                hexadecimal(giftWrap.identifier.rawRepresentation)
                    == expectedIdentifier
            )
            #expect(
                try Codec.open(
                    giftWrap,
                    expectedDeliveryKind: deliveryKind,
                    expectedRumorKind: 42_042,
                    recipientSigningKey: recipient,
                    limits: codingLimits
                ).rumor == rumor
            )
        }
    }

    @Test("Code rumors strictly as unsigned NIP-01 events")
    func strictUnsignedRumorCoding() throws {
        let rumor = try makeRumor(author: signingKey(4), kind: 51_051)
        let encoded = try Nostr.UnsignedEventCodec.encode(
            rumor,
            limits: codingLimits.event
        )
        #expect(
            try Nostr.UnsignedEventCodec.decode(
                encoded,
                limits: codingLimits.event
            ) == rumor
        )

        let signed = try signedEvent(
            kind: 51_051,
            tags: [],
            content: "not a rumor",
            signingKey: signingKey(4),
            auxiliaryRandomnessByte: 0x31
        )
        let signedJSON = try Nostr.EventCodec.encode(
            signed,
            limits: codingLimits.event
        )
        #expect(
            throws: Nostr.EventCodingError.unexpectedTopLevelField("sig")
        ) {
            _ = try Nostr.UnsignedEventCodec.decode(
                signedJSON,
                limits: codingLimits.event
            )
        }
        #expect(throws: Nostr.EventCodingError.identifierMismatch) {
            _ = try Nostr.UnsignedEventCodec.decode(
                tamperContent(in: encoded),
                limits: codingLimits.event
            )
        }
    }

    @Test("Reject wrong delivery recipient and application kind")
    func rejectContextMismatch() throws {
        let sender = try signingKey(5)
        let recipient = try signingKey(6)
        let outsider = try signingKey(7)
        let (seal, giftWrap) = try makeGiftWrap(
            sender: sender,
            recipient: recipient,
            rumorKind: 9_999
        )

        #expect(
            throws: Codec.Error.unexpectedGiftWrapKind(
                expected: Codec.DeliveryKind.ephemeral.rawValue,
                actual: Codec.DeliveryKind.regular.rawValue
            )
        ) {
            _ = try Codec.open(
                giftWrap,
                expectedDeliveryKind: .ephemeral,
                expectedRumorKind: 9_999,
                recipientSigningKey: recipient,
                limits: codingLimits
            )
        }
        #expect(throws: Codec.Error.invalidGiftWrapTags) {
            _ = try Codec.open(
                giftWrap,
                expectedDeliveryKind: .regular,
                expectedRumorKind: 9_999,
                recipientSigningKey: outsider,
                limits: codingLimits
            )
        }
        #expect(
            throws: Codec.Error.unexpectedRumorKind(
                expected: 10_000,
                actual: 9_999
            )
        ) {
            _ = try Codec.open(
                giftWrap,
                expectedDeliveryKind: .regular,
                expectedRumorKind: 10_000,
                recipientSigningKey: recipient,
                limits: codingLimits
            )
        }
        #expect(seal.publicKey == sender.bip340VerificationKey)
    }

    @Test("Reject invalid seal structure on inbound paths")
    func rejectInvalidSealStructure() throws {
        let recipient = try signingKey(8)
        let wrongKind = try signedEvent(
            kind: 12,
            tags: [],
            content: "x",
            signingKey: signingKey(9),
            auxiliaryRandomnessByte: 0x41
        )
        let taggedSeal = try signedEvent(
            kind: 13,
            tags: [["p", hexadecimal(recipient.bip340VerificationKey.rawRepresentation)]],
            content: "x",
            signingKey: signingKey(9),
            auxiliaryRandomnessByte: 0x44
        )
        let wrongKindWrap = try encryptedEvent(
            plaintext: String(
                decoding: Nostr.EventCodec.encode(
                    wrongKind,
                    limits: codingLimits.event
                ),
                as: UTF8.self
            ),
            kind: Codec.DeliveryKind.regular.rawValue,
            tags: [recipientTag(recipient)],
            signingKey: signingKey(10),
            recipient: recipient,
            nonceByte: 0x47,
            auxiliaryRandomnessByte: 0x48
        )
        #expect(throws: Codec.Error.invalidSealKind(actual: 12)) {
            _ = try Codec.open(
                wrongKindWrap,
                expectedDeliveryKind: .regular,
                expectedRumorKind: 1,
                recipientSigningKey: recipient,
                limits: codingLimits
            )
        }

        let taggedSealWrap = try encryptedEvent(
            plaintext: String(
                decoding: Nostr.EventCodec.encode(
                    taggedSeal,
                    limits: codingLimits.event
                ),
                as: UTF8.self
            ),
            kind: Codec.DeliveryKind.regular.rawValue,
            tags: [recipientTag(recipient)],
            signingKey: signingKey(10),
            recipient: recipient,
            nonceByte: 0x49,
            auxiliaryRandomnessByte: 0x4a
        )
        #expect(throws: Codec.Error.invalidSealTags) {
            _ = try Codec.open(
                taggedSealWrap,
                expectedDeliveryKind: .regular,
                expectedRumorKind: 1,
                recipientSigningKey: recipient,
                limits: codingLimits
            )
        }
    }

    @Test("Bind rumor authorship to the authenticated seal signer")
    func rejectRumorAuthorSubstitution() throws {
        let rumorAuthor = try signingKey(11)
        let sealAuthor = try signingKey(12)
        let recipient = try signingKey(13)
        let rumor = try makeRumor(author: rumorAuthor, kind: 23_456)
        #expect(throws: Codec.Error.rumorAuthorMismatch) {
            _ = try Codec.seal(
                rumor,
                createdAt: 4,
                senderSigningKey: sealAuthor,
                recipientPublicKey: recipient.bip340VerificationKey,
                limits: codingLimits
            )
        }
        let rumorJSON = try Nostr.UnsignedEventCodec.encode(
            rumor,
            limits: codingLimits.event
        )
        let substitutedSeal = try encryptedEvent(
            plaintext: String(decoding: rumorJSON, as: UTF8.self),
            kind: 13,
            tags: [],
            signingKey: sealAuthor,
            recipient: recipient,
            nonceByte: 0x51,
            auxiliaryRandomnessByte: 0x52
        )
        let giftWrap = try encryptedEvent(
            plaintext: String(
                decoding: Nostr.EventCodec.encode(
                    substitutedSeal,
                    limits: codingLimits.event
                ),
                as: UTF8.self
            ),
            kind: Codec.DeliveryKind.regular.rawValue,
            tags: [recipientTag(recipient)],
            signingKey: signingKey(14),
            recipient: recipient,
            nonceByte: 0x53,
            auxiliaryRandomnessByte: 0x54
        )

        #expect(throws: Codec.Error.rumorAuthorMismatch) {
            _ = try Codec.open(
                giftWrap,
                expectedDeliveryKind: .regular,
                expectedRumorKind: 23_456,
                recipientSigningKey: recipient,
                limits: codingLimits
            )
        }
    }

    @Test("Validate the signed wrapper and seal before nested decryption")
    func validateEverySignedLayerBeforeDecrypting() throws {
        let sender = try signingKey(15)
        let recipient = try signingKey(16)
        let (_, giftWrap) = try makeGiftWrap(
            sender: sender,
            recipient: recipient,
            rumorKind: 5_432
        )
        let encodedGiftWrap = try Nostr.EventCodec.encode(
            giftWrap,
            limits: codingLimits.event
        )
        #expect(throws: Nostr.EventCodingError.identifierMismatch) {
            _ = try Nostr.EventCodec.decode(
                tamperContent(in: encodedGiftWrap),
                limits: codingLimits.event
            )
        }

        let validSeal = try Codec.seal(
            makeRumor(author: sender, kind: 5_432),
            createdAt: 5,
            senderSigningKey: sender,
            recipientPublicKey: recipient.bip340VerificationKey,
            limits: codingLimits
        )
        let tamperedSealJSON = try tamperContent(
            in: try Nostr.EventCodec.encode(
                validSeal.event,
                limits: codingLimits.event
            )
        )
        let validOuter = try encryptedEvent(
            plaintext: String(decoding: tamperedSealJSON, as: UTF8.self),
            kind: Codec.DeliveryKind.regular.rawValue,
            tags: [recipientTag(recipient)],
            signingKey: signingKey(17),
            recipient: recipient,
            nonceByte: 0x63,
            auxiliaryRandomnessByte: 0x64
        )
        #expect(throws: Nostr.EventCodingError.identifierMismatch) {
            _ = try Codec.open(
                validOuter,
                expectedDeliveryKind: .regular,
                expectedRumorKind: 5_432,
                recipientSigningKey: recipient,
                limits: codingLimits
            )
        }
    }

    @Test("Reject wrapper identity collisions at both signed layers")
    func rejectWrapperIdentityCollisions() throws {
        let sender = try signingKey(34)
        let recipient = try signingKey(35)
        let seal = try Codec.seal(
            makeRumor(author: sender, kind: 8_888),
            createdAt: 5,
            senderSigningKey: sender,
            recipientPublicKey: recipient.bip340VerificationKey,
            limits: codingLimits
        )
        let sealJSON = try Nostr.EventCodec.encode(
            seal.event,
            limits: codingLimits.event
        )
        let recipientSignedWrapper = try signedEvent(
            kind: Codec.DeliveryKind.regular.rawValue,
            tags: [recipientTag(recipient)],
            content: "identity collision checked before decryption",
            signingKey: recipient,
            auxiliaryRandomnessByte: 0x97
        )
        #expect(throws: Codec.Error.wrapperIdentityCollision) {
            _ = try Codec.open(
                recipientSignedWrapper,
                expectedDeliveryKind: .regular,
                expectedRumorKind: 8_888,
                recipientSigningKey: recipient,
                limits: codingLimits
            )
        }

        let sealAuthorSignedWrapper = try encryptedEvent(
            plaintext: String(decoding: sealJSON, as: UTF8.self),
            kind: Codec.DeliveryKind.regular.rawValue,
            tags: [recipientTag(recipient)],
            signingKey: sender,
            recipient: recipient,
            nonceByte: 0x98,
            auxiliaryRandomnessByte: 0x99
        )
        #expect(throws: Codec.Error.wrapperIdentityCollision) {
            _ = try Codec.open(
                sealAuthorSignedWrapper,
                expectedDeliveryKind: .regular,
                expectedRumorKind: 8_888,
                recipientSigningKey: recipient,
                limits: codingLimits
            )
        }
    }

    @Test("Reject ciphertext authenticated for a different recipient")
    func rejectCiphertextRecipientSubstitution() throws {
        let recipient = try signingKey(36)
        let substitutedRecipient = try signingKey(37)
        let wrapper = try encryptedEvent(
            plaintext: "not decryptable by the tagged recipient",
            kind: Codec.DeliveryKind.regular.rawValue,
            tags: [recipientTag(recipient)],
            signingKey: signingKey(38),
            recipient: substitutedRecipient,
            nonceByte: 0x9a,
            auxiliaryRandomnessByte: 0x9b
        )

        #expect(throws: OpalCrypto.Nostr.NIP44.Error.authenticationFailed) {
            _ = try Codec.open(
                wrapper,
                expectedDeliveryKind: .regular,
                expectedRumorKind: 1,
                recipientSigningKey: recipient,
                limits: codingLimits
            )
        }
    }

    @Test("Require one recipient tag while permitting caller-owned metadata")
    func validateGiftWrapMetadata() throws {
        let sender = try signingKey(18)
        let recipient = try signingKey(19)
        let seal = try Codec.seal(
            makeRumor(author: sender, kind: 7_777),
            createdAt: 6,
            senderSigningKey: sender,
            recipientPublicKey: recipient.bip340VerificationKey,
            limits: codingLimits
        )
        let extraTagWrap = try Codec.wrap(
            seal,
            deliveryKind: .regular,
            createdAt: 7,
            additionalTags: [["nonce", "1", "1"]],
            limits: codingLimits
        )
        #expect(
            try Codec.open(
                extraTagWrap,
                expectedDeliveryKind: .regular,
                expectedRumorKind: 7_777,
                recipientSigningKey: recipient,
                limits: codingLimits
            ).rumor.template.content == "opaque application payload"
        )

        #expect(throws: Codec.Error.invalidGiftWrapTags) {
            _ = try Codec.wrap(
                seal,
                deliveryKind: .regular,
                createdAt: 7,
                additionalTags: [recipientTag(recipient)],
                limits: codingLimits
            )
        }

        let missingRecipientWrap = try signedEvent(
            kind: Codec.DeliveryKind.regular.rawValue,
            tags: [],
            content: "recipient tag checked before decryption",
            signingKey: signingKey(20),
            auxiliaryRandomnessByte: 0x78
        )
        #expect(throws: Codec.Error.invalidGiftWrapTags) {
            _ = try Codec.open(
                missingRecipientWrap,
                expectedDeliveryKind: .regular,
                expectedRumorKind: 7_777,
                recipientSigningKey: recipient,
                limits: codingLimits
            )
        }
    }

    @Test("Fail closed on malformed nested JSON and allocation bounds")
    func rejectMalformedOrOversizedLayers() throws {
        let sender = try signingKey(21)
        let recipient = try signingKey(22)
        let malformedOuter = try encryptedEvent(
            plaintext: "not-json",
            kind: Codec.DeliveryKind.regular.rawValue,
            tags: [recipientTag(recipient)],
            signingKey: signingKey(23),
            recipient: recipient,
            nonceByte: 0x81,
            auxiliaryRandomnessByte: 0x82
        )
        #expect(throws: Nostr.EventCodingError.invalidJSON) {
            _ = try Codec.open(
                malformedOuter,
                expectedDeliveryKind: .regular,
                expectedRumorKind: 1,
                recipientSigningKey: recipient,
                limits: codingLimits
            )
        }

        let malformedSeal = try encryptedEvent(
            plaintext: "not-json",
            kind: 13,
            tags: [],
            signingKey: sender,
            recipient: recipient,
            nonceByte: 0x83,
            auxiliaryRandomnessByte: 0x84
        )
        let malformedSealJSON = try Nostr.EventCodec.encode(
            malformedSeal,
            limits: codingLimits.event
        )
        let wrappedMalformedRumor = try encryptedEvent(
            plaintext: String(decoding: malformedSealJSON, as: UTF8.self),
            kind: Codec.DeliveryKind.regular.rawValue,
            tags: [recipientTag(recipient)],
            signingKey: signingKey(24),
            recipient: recipient,
            nonceByte: 0x85,
            auxiliaryRandomnessByte: 0x86
        )
        #expect(throws: Nostr.EventCodingError.invalidJSON) {
            _ = try Codec.open(
                wrappedMalformedRumor,
                expectedDeliveryKind: .regular,
                expectedRumorKind: 1,
                recipientSigningKey: recipient,
                limits: codingLimits
            )
        }

        #expect(throws: Codec.Error.invalidResourceLimit) {
            _ = try Codec.CodingLimits(
                event: codingLimits.event,
                maximumRumorJSONByteCount: 0,
                maximumSealJSONByteCount: 1
            )
        }

        let rumor = try makeRumor(author: sender, kind: 1)
        let rumorJSON = try Nostr.UnsignedEventCodec.encode(
            rumor,
            limits: codingLimits.event
        )
        let restrictive = try Codec.CodingLimits(
            event: codingLimits.event,
            maximumRumorJSONByteCount: rumorJSON.count - 1,
            maximumSealJSONByteCount: codingLimits.maximumSealJSONByteCount
        )
        #expect(
            throws: Codec.Error.rumorJSONByteCountExceedsMaximum(
                maximum: rumorJSON.count - 1,
                actual: rumorJSON.count
            )
        ) {
            _ = try Codec.seal(
                rumor,
                createdAt: 8,
                senderSigningKey: sender,
                recipientPublicKey: recipient.bip340VerificationKey,
                limits: restrictive
            )
        }

        let seal = try Codec.seal(
            rumor,
            createdAt: 9,
            senderSigningKey: sender,
            recipientPublicKey: recipient.bip340VerificationKey,
            limits: codingLimits
        )
        let sealJSON = try Nostr.EventCodec.encode(
            seal.event,
            limits: codingLimits.event
        )
        let restrictiveSeal = try Codec.CodingLimits(
            event: codingLimits.event,
            maximumRumorJSONByteCount: codingLimits.maximumRumorJSONByteCount,
            maximumSealJSONByteCount: sealJSON.count - 1
        )
        #expect(
            throws: Codec.Error.sealJSONByteCountExceedsMaximum(
                maximum: sealJSON.count - 1,
                actual: sealJSON.count
            )
        ) {
            _ = try Codec.wrap(
                seal,
                deliveryKind: .regular,
                createdAt: 10,
                limits: restrictiveSeal
            )
        }
    }

    @Test("Enforce each nested plaintext bound during inbound decryption")
    func rejectOversizedInboundLayers() throws {
        let sender = try signingKey(41)
        let recipient = try signingKey(42)
        let rumor = try makeRumor(author: sender, kind: 4_242)
        let rumorJSON = try Nostr.UnsignedEventCodec.encode(
            rumor,
            limits: codingLimits.event
        )
        let seal = try Codec.seal(
            rumor,
            createdAt: 11,
            senderSigningKey: sender,
            recipientPublicKey: recipient.bip340VerificationKey,
            limits: codingLimits
        )
        let sealJSON = try Nostr.EventCodec.encode(
            seal.event,
            limits: codingLimits.event
        )
        let giftWrap = try Codec.wrap(
            seal,
            deliveryKind: .regular,
            createdAt: 12,
            limits: codingLimits
        )

        let restrictiveSeal = try Codec.CodingLimits(
            event: codingLimits.event,
            maximumRumorJSONByteCount: codingLimits.maximumRumorJSONByteCount,
            maximumSealJSONByteCount: sealJSON.count - 1
        )
        #expect(
            throws: OpalCrypto.Nostr.NIP44.Error
                .plaintextByteCountExceedsMaximum(
                    maximum: sealJSON.count - 1,
                    actual: sealJSON.count
                )
        ) {
            _ = try Codec.open(
                giftWrap,
                expectedDeliveryKind: .regular,
                expectedRumorKind: 4_242,
                recipientSigningKey: recipient,
                limits: restrictiveSeal
            )
        }

        let restrictiveRumor = try Codec.CodingLimits(
            event: codingLimits.event,
            maximumRumorJSONByteCount: rumorJSON.count - 1,
            maximumSealJSONByteCount: codingLimits.maximumSealJSONByteCount
        )
        #expect(
            throws: OpalCrypto.Nostr.NIP44.Error
                .plaintextByteCountExceedsMaximum(
                    maximum: rumorJSON.count - 1,
                    actual: rumorJSON.count
                )
        ) {
            _ = try Codec.open(
                giftWrap,
                expectedDeliveryKind: .regular,
                expectedRumorKind: 4_242,
                recipientSigningKey: recipient,
                limits: restrictiveRumor
            )
        }
    }

    private var codingLimits: Codec.CodingLimits {
        get throws {
            try .init(
                event: .init(
                    maximumEventJSONByteCount: 65_536,
                    maximumTagCount: 8,
                    maximumTagElementCount: 4,
                    maximumStringByteCount: 60_000
                ),
                maximumRumorJSONByteCount: 8_192,
                maximumSealJSONByteCount: 32_768
            )
        }
    }

    private func makeGiftWrap(
        sender: OpalCrypto.Secp256k1.SigningKey,
        recipient: OpalCrypto.Secp256k1.SigningKey,
        rumorKind: UInt16
    ) throws -> (Nostr.Event, Nostr.Event) {
        let seal = try Codec.seal(
            makeRumor(author: sender, kind: rumorKind),
            createdAt: 10,
            senderSigningKey: sender,
            recipientPublicKey: recipient.bip340VerificationKey,
            limits: codingLimits
        )
        let giftWrap = try Codec.wrap(
            seal,
            deliveryKind: .regular,
            createdAt: 11,
            limits: codingLimits
        )
        return (seal.event, giftWrap)
    }

    private func makeRumor(
        author: OpalCrypto.Secp256k1.SigningKey,
        kind: UInt16
    ) throws -> Nostr.UnsignedEvent {
        let template = try Nostr.EventTemplate(
            createdAt: 1_700_000_000,
            kind: kind,
            tags: [["d", "caller-owned-application-context"]],
            content: "opaque application payload",
            limits: codingLimits.event
        )
        return try .init(
            publicKey: author.bip340VerificationKey,
            template: template,
            limits: codingLimits.event
        )
    }

    private func signedEvent(
        kind: UInt16,
        tags: [[String]],
        content: String,
        signingKey: OpalCrypto.Secp256k1.SigningKey,
        auxiliaryRandomnessByte: UInt8,
        createdAt: UInt64 = 1
    ) throws -> Nostr.Event {
        let template = try Nostr.EventTemplate(
            createdAt: createdAt,
            kind: kind,
            tags: tags,
            content: content,
            limits: codingLimits.event
        )
        return try Nostr.EventSigner.sign(
            template,
            using: signingKey,
            auxiliaryRandomness: auxiliaryRandomness(
                auxiliaryRandomnessByte
            ),
            limits: codingLimits.event
        )
    }

    private func encryptedEvent(
        plaintext: String,
        kind: UInt16,
        tags: [[String]],
        signingKey: OpalCrypto.Secp256k1.SigningKey,
        recipient: OpalCrypto.Secp256k1.SigningKey,
        nonceByte: UInt8,
        auxiliaryRandomnessByte: UInt8,
        createdAt: UInt64 = 1
    ) throws -> Nostr.Event {
        let conversationKey = OpalCrypto.Nostr.NIP44.deriveConversationKey(
            signingKey: signingKey,
            publicKey: recipient.bip340VerificationKey
        )
        let payload = try OpalCrypto.Nostr.NIP44.encrypt(
            plaintext,
            conversationKey: conversationKey,
            nonce: nonce(nonceByte),
            maximumPlaintextByteCount: codingLimits.maximumSealJSONByteCount
        )
        return try signedEvent(
            kind: kind,
            tags: tags,
            content: payload.encodedRepresentation,
            signingKey: signingKey,
            auxiliaryRandomnessByte: auxiliaryRandomnessByte,
            createdAt: createdAt
        )
    }

    private func signingKey(
        _ value: UInt8
    ) throws -> OpalCrypto.Secp256k1.SigningKey {
        try .init(
            rawRepresentation: Data(repeating: 0, count: 31) + Data([value])
        )
    }

    private func nonce(
        _ byte: UInt8
    ) throws -> OpalCrypto.Nostr.NIP44.Nonce {
        try .init(rawRepresentation: Data(repeating: byte, count: 32))
    }

    private func auxiliaryRandomness(
        _ byte: UInt8
    ) throws -> OpalCrypto.Signature.BIP340.AuxiliaryRandomness {
        try .init(rawRepresentation: Data(repeating: byte, count: 32))
    }

    private func recipientTag(
        _ recipient: OpalCrypto.Secp256k1.SigningKey
    ) -> [String] {
        ["p", hexadecimal(recipient.bip340VerificationKey.rawRepresentation)]
    }

    private func hexadecimal(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }

    private func tamperContent(in data: Data) throws -> Data {
        var json = String(decoding: data, as: UTF8.self)
        let marker = "\"content\":\""
        guard let markerRange = json.range(of: marker),
              markerRange.upperBound < json.endIndex else {
            throw Nostr.EventCodingError.invalidJSON
        }
        let index = markerRange.upperBound
        json.replaceSubrange(index ... index, with: json[index] == "A" ? "B" : "A")
        return Data(json.utf8)
    }
}

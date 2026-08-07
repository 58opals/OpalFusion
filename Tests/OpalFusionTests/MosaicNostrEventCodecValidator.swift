// MosaicNostrEventCodecValidator.swift

import Foundation
import OpalCrypto
import Testing
@testable import OpalFusion

@Suite("Mosaic Nostr event codec validation")
struct MosaicNostrEventCodecValidator {
    private var limits: OpalFusion.Mosaic.NostrNamespace.EventCodingLimits {
        get throws {
            try .init(
                maximumEventJSONByteCount: 8_192,
                maximumTagCount: 16,
                maximumTagElementCount: 8,
                maximumStringByteCount: 4_096
            )
        }
    }

    @Test("Decode and verify the official NIP-13 signed event")
    func decodeAndVerifyOfficialNIP13SignedEvent() throws {
        let event = try OpalFusion.Mosaic.NostrNamespace.EventCodec.decode(
            Data(Self.officialNIP13Event.utf8),
            limits: limits
        )

        #expect(event.template.kind == 1)
        #expect(event.template.createdAt == 1_651_794_653)
        #expect(event.template.tags == [["nonce", "776797", "20"]])
        #expect(
            event.template.content
                == "It's just me mining my own business"
        )
        #expect(
            hexadecimal(event.identifier.rawRepresentation)
                == "000006d8c378af1779d2feebc7603a125d99eca0ccf1085959b307f64e5dd358"
        )
    }

    @Test("Sign encode and decode escaped Unicode event content")
    func signEncodeAndDecodeEscapedUnicodeEventContent() throws {
        let signingKey = try OpalCrypto.Secp256k1.SigningKey(
            rawRepresentation: Data(repeating: 0, count: 31) + Data([1])
        )
        let template = try OpalFusion.Mosaic.NostrNamespace.EventTemplate(
            createdAt: 1_700_000_000,
            kind: 21_059,
            tags: [["p", String(repeating: "0", count: 64)]],
            content: "Mosaic \"mailbox\"\n\\ \u{1F9E9}",
            limits: limits
        )
        let event = try OpalFusion.Mosaic.NostrNamespace.EventSigner.sign(
            template,
            using: signingKey,
            auxiliaryRandomness: .init(
                rawRepresentation: Data(repeating: 0xA5, count: 32)
            ),
            limits: limits
        )
        let encoded = try OpalFusion.Mosaic.NostrNamespace.EventCodec.encode(
            event,
            limits: limits
        )
        let decoded = try OpalFusion.Mosaic.NostrNamespace.EventCodec.decode(
            encoded,
            limits: limits
        )

        #expect(decoded == event)
        #expect(String(decoding: encoded, as: UTF8.self).contains("\\\"mailbox\\\""))
        #expect(String(decoding: encoded, as: UTF8.self).contains("\\n"))
    }

    @Test("Accept insignificant JSON whitespace and field reordering")
    func acceptInsignificantJSONWhitespaceAndFieldReordering() throws {
        let compact = Self.officialNIP13Event
        let object = try #require(
            JSONSerialization.jsonObject(with: Data(compact.utf8))
                as? [String: Any]
        )
        let reordered = try JSONSerialization.data(
            withJSONObject: object,
            options: [.prettyPrinted, .sortedKeys]
        )

        let event = try OpalFusion.Mosaic.NostrNamespace.EventCodec.decode(
            reordered,
            limits: limits
        )
        #expect(event.template.kind == 1)
    }

    @Test("Reject duplicate unknown and missing top-level fields")
    func rejectDuplicateUnknownAndMissingTopLevelFields() throws {
        let duplicate = Self.officialNIP13Event.dropLast()
            + ",\"kind\":1}"
        #expect(
            throws: OpalFusion.Mosaic.NostrNamespace.EventCodingError
                .duplicateTopLevelField("kind")
        ) {
            _ = try OpalFusion.Mosaic.NostrNamespace.EventCodec.decode(
                Data(duplicate.utf8),
                limits: limits
            )
        }

        let unknown = Self.officialNIP13Event.dropLast()
            + ",\"mosaic\":true}"
        #expect(
            throws: OpalFusion.Mosaic.NostrNamespace.EventCodingError
                .unexpectedTopLevelField("mosaic")
        ) {
            _ = try OpalFusion.Mosaic.NostrNamespace.EventCodec.decode(
                Data(unknown.utf8),
                limits: limits
            )
        }

        let missing = Self.officialNIP13Event.replacingOccurrences(
            of: "\"kind\":1,",
            with: ""
        )
        #expect(throws: OpalFusion.Mosaic.NostrNamespace.EventCodingError.self) {
            _ = try OpalFusion.Mosaic.NostrNamespace.EventCodec.decode(
                Data(missing.utf8),
                limits: limits
            )
        }
    }

    @Test("Reject changed identifiers signatures and payloads")
    func rejectChangedIdentifiersSignaturesAndPayloads() throws {
        let changedIdentifier = Self.officialNIP13Event.replacingOccurrences(
            of: "000006d8",
            with: "100006d8"
        )
        #expect(
            throws: OpalFusion.Mosaic.NostrNamespace.EventCodingError.identifierMismatch
        ) {
            _ = try OpalFusion.Mosaic.NostrNamespace.EventCodec.decode(
                Data(changedIdentifier.utf8),
                limits: limits
            )
        }

        let changedSignature = Self.officialNIP13Event.replacingOccurrences(
            of: "aba977\"",
            with: "aba976\""
        )
        #expect(
            throws: OpalFusion.Mosaic.NostrNamespace.EventCodingError
                .signatureVerificationFailed
        ) {
            _ = try OpalFusion.Mosaic.NostrNamespace.EventCodec.decode(
                Data(changedSignature.utf8),
                limits: limits
            )
        }

        let changedContent = Self.officialNIP13Event.replacingOccurrences(
            of: "my own business",
            with: "your own biz"
        )
        #expect(
            throws: OpalFusion.Mosaic.NostrNamespace.EventCodingError.identifierMismatch
        ) {
            _ = try OpalFusion.Mosaic.NostrNamespace.EventCodec.decode(
                Data(changedContent.utf8),
                limits: limits
            )
        }
    }

    @Test("Reject noncanonical hexadecimal and malformed numeric fields")
    func rejectNoncanonicalHexadecimalAndMalformedNumericFields() throws {
        let uppercase = Self.officialNIP13Event.replacingOccurrences(
            of: "a48380f4",
            with: "A48380F4"
        )
        #expect(throws: OpalFusion.Mosaic.NostrNamespace.EventCodingError.self) {
            _ = try OpalFusion.Mosaic.NostrNamespace.EventCodec.decode(
                Data(uppercase.utf8),
                limits: limits
            )
        }

        let oversizedKind = Self.officialNIP13Event.replacingOccurrences(
            of: "\"kind\":1",
            with: "\"kind\":65536"
        )
        #expect(throws: OpalFusion.Mosaic.NostrNamespace.EventCodingError.invalidJSON) {
            _ = try OpalFusion.Mosaic.NostrNamespace.EventCodec.decode(
                Data(oversizedKind.utf8),
                limits: limits
            )
        }

        let negativeTime = Self.officialNIP13Event.replacingOccurrences(
            of: "1651794653",
            with: "-1"
        )
        #expect(throws: OpalFusion.Mosaic.NostrNamespace.EventCodingError.invalidJSON) {
            _ = try OpalFusion.Mosaic.NostrNamespace.EventCodec.decode(
                Data(negativeTime.utf8),
                limits: limits
            )
        }
    }

    @Test("Enforce caller-owned event and string resource limits")
    func enforceCallerOwnedEventAndStringResourceLimits() throws {
        let tinyEventLimit = try OpalFusion.Mosaic.NostrNamespace.EventCodingLimits(
            maximumEventJSONByteCount: 64,
            maximumTagCount: 16,
            maximumTagElementCount: 8,
            maximumStringByteCount: 4_096
        )
        #expect(throws: OpalFusion.Mosaic.NostrNamespace.EventCodingError.self) {
            _ = try OpalFusion.Mosaic.NostrNamespace.EventCodec.decode(
                Data(Self.officialNIP13Event.utf8),
                limits: tinyEventLimit
            )
        }

        let tinyStringLimit = try OpalFusion.Mosaic.NostrNamespace.EventCodingLimits(
            maximumEventJSONByteCount: 8_192,
            maximumTagCount: 16,
            maximumTagElementCount: 8,
            maximumStringByteCount: 4
        )
        #expect(throws: OpalFusion.Mosaic.NostrNamespace.EventCodingError.self) {
            _ = try OpalFusion.Mosaic.NostrNamespace.EventCodec.decode(
                Data(Self.officialNIP13Event.utf8),
                limits: tinyStringLimit
            )
        }

        let event = try OpalFusion.Mosaic.NostrNamespace.EventCodec.decode(
            Data(Self.officialNIP13Event.utf8),
            limits: limits
        )
        #expect(throws: OpalFusion.Mosaic.NostrNamespace.EventCodingError.self) {
            _ = try OpalFusion.Mosaic.NostrNamespace.EventCodec.encode(
                event,
                limits: tinyStringLimit
            )
        }
    }

    @Test("Reject empty tags and invalid resource limits")
    func rejectEmptyTagsAndInvalidResourceLimits() throws {
        #expect(throws: OpalFusion.Mosaic.NostrNamespace.EventCodingError.self) {
            _ = try OpalFusion.Mosaic.NostrNamespace.EventTemplate(
                createdAt: 1,
                kind: 1,
                tags: [[]],
                content: "x",
                limits: limits
            )
        }
        #expect(throws: OpalFusion.Mosaic.NostrNamespace.EventCodingError.self) {
            _ = try OpalFusion.Mosaic.NostrNamespace.EventCodingLimits(
                maximumEventJSONByteCount: 0,
                maximumTagCount: 0,
                maximumTagElementCount: 0,
                maximumStringByteCount: 0
            )
        }
    }

    private func hexadecimal(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }

    private static let officialNIP13Event =
        "{\"id\":\"000006d8c378af1779d2feebc7603a125d99eca0ccf1085959b307f64e5dd358\","
        + "\"pubkey\":\"a48380f4cfcc1ad5378294fcac36439770f9c878dd880ffa94bb74ea54a6f243\","
        + "\"created_at\":1651794653,\"kind\":1,"
        + "\"tags\":[[\"nonce\",\"776797\",\"20\"]],"
        + "\"content\":\"It's just me mining my own business\","
        + "\"sig\":\"284622fc0a3f4f1303455d5175f7ba962a3300d136085b9566801bc2e0699de0"
        + "c7e31e44c81fb40ad9049173742e904713c3594a1da0fc5d2382a25c11aba977\"}"
}

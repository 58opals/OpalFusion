// MosaicNostrRelayMessageCodecValidator.swift

import Foundation
import OpalCrypto
import Testing
@testable import OpalFusion

@Suite("Mosaic NIP-01 relay message validation")
struct MosaicNostrRelayMessageCodecValidator {
    typealias Nostr = OpalFusion.Mosaic.NostrNamespace

    @Test("Encode publication request and close client frames")
    func encodeClientFrames() throws {
        let event = try makeEvent()
        let subscriptionIdentifier = try Nostr.SubscriptionIdentifier("mosaic-round")
        let filter = try Nostr.RelayFilter(
            identifiers: [event.identifier],
            authors: [event.publicKey],
            kinds: [event.template.kind],
            recipientPublicKeys: [event.publicKey],
            since: 10,
            until: 20,
            limit: 3
        )
        let subscription = try Nostr.RelaySubscription(
            identifier: subscriptionIdentifier,
            filters: [filter]
        )

        let publication = try Nostr.RelayMessageCodec.encode(
            .event(event),
            limits: limits
        )
        let request = try Nostr.RelayMessageCodec.encode(
            .request(subscription),
            limits: limits
        )
        let close = try Nostr.RelayMessageCodec.encode(
            .close(subscriptionIdentifier),
            limits: limits
        )

        #expect(String(decoding: publication, as: UTF8.self).hasPrefix("[\"EVENT\",{"))
        #expect(
            String(decoding: request, as: UTF8.self)
                == "[\"REQ\",\"mosaic-round\",{\"ids\":[\""
                    + hexadecimal(event.identifier.rawRepresentation)
                    + "\"],\"authors\":[\""
                    + hexadecimal(event.publicKey.rawRepresentation)
                    + "\"],\"kinds\":[7],\"#p\":[\""
                    + hexadecimal(event.publicKey.rawRepresentation)
                    + "\"],\"since\":10,\"until\":20,\"limit\":3}]"
        )
        #expect(String(decoding: close, as: UTF8.self) == "[\"CLOSE\",\"mosaic-round\"]")
    }

    @Test("Decode and validate every supported server frame")
    func decodeServerFrames() throws {
        let event = try makeEvent()
        let encodedEvent = try Nostr.EventCodec.encode(event, limits: eventLimits)
        let eventFrame = Data("[\"EVENT\",\"mosaic-round\",".utf8)
            + encodedEvent + Data("]".utf8)
        let identifier = hexadecimal(event.identifier.rawRepresentation)

        #expect(
            try Nostr.RelayMessageCodec.decodeServerMessage(
                eventFrame,
                limits: limits
            ) == .event(
                subscription: try .init("mosaic-round"),
                event: event
            )
        )
        #expect(
            try Nostr.RelayMessageCodec.decodeServerMessage(
                Data(("[\"OK\",\"" + identifier + "\",true,\"saved\"]").utf8),
                limits: limits
            ) == .acknowledgement(
                eventIdentifier: event.identifier,
                accepted: true,
                message: "saved"
            )
        )
        #expect(
            try Nostr.RelayMessageCodec.decodeServerMessage(
                Data("[\"EOSE\",\"mosaic-round\"]".utf8),
                limits: limits
            ) == .endOfStoredEvents(try .init("mosaic-round"))
        )
        #expect(
            try Nostr.RelayMessageCodec.decodeServerMessage(
                Data("[\"CLOSED\",\"mosaic-round\",\"expired\"]".utf8),
                limits: limits
            ) == .subscriptionClosed(
                identifier: try .init("mosaic-round"),
                message: "expired"
            )
        )
        #expect(
            try Nostr.RelayMessageCodec.decodeServerMessage(
                Data("[\"NOTICE\",\"maintenance\"]".utf8),
                limits: limits
            ) == .notice("maintenance")
        )
    }

    @Test("Preserve strict embedded-event validation")
    func preserveStrictEmbeddedEventValidation() throws {
        let event = try makeEvent()
        let encoded = try Nostr.EventCodec.encode(event, limits: eventLimits)
        let duplicated = String(decoding: encoded.dropLast(), as: UTF8.self)
            + ",\"kind\":7}"
        let frame = Data("[\"EVENT\",\"mosaic-round\",\(duplicated)]".utf8)

        #expect(
            throws: Nostr.EventCodingError.duplicateTopLevelField("kind")
        ) {
            _ = try Nostr.RelayMessageCodec.decodeServerMessage(
                frame,
                limits: limits
            )
        }
    }

    @Test("Scan escaped embedded event content without changing its bytes")
    func scanEscapedEmbeddedEventContent() throws {
        let event = try makeEvent(
            content: "quote \" slash \\ comma, brackets [ ] braces { } snowman ☃"
        )
        let encoded = try Nostr.EventCodec.encode(event, limits: eventLimits)
        let escaped = String(decoding: encoded, as: UTF8.self)
            .replacingOccurrences(of: "☃", with: "\\u2603")
        let frame = Data("[\"EVENT\",\"mosaic-round\",\(escaped)]".utf8)

        #expect(escaped.contains("\\u2603"))
        #expect(
            try Nostr.RelayMessageCodec.decodeServerMessage(
                frame,
                limits: limits
            ) == .event(
                subscription: .init("mosaic-round"),
                event: event
            )
        )
    }

    @Test("Reject mismatched composites and invalid string escapes")
    func rejectAdversarialArrayStructure() throws {
        #expect(throws: Nostr.RelayMessageCodingError.invalidJSON) {
            _ = try Nostr.RelayMessageCodec.decodeServerMessage(
                Data(#"["NOTICE",{"nested":[1,2}}]"#.utf8),
                limits: limits
            )
        }
        #expect(throws: Nostr.RelayMessageCodingError.invalidJSON) {
            _ = try Nostr.RelayMessageCodec.decodeServerMessage(
                Data(#"["NOTICE","bad\q"]"#.utf8),
                limits: limits
            )
        }
    }

    @Test("Reject malformed unknown and oversized server frames")
    func rejectInvalidServerFrames() throws {
        #expect(throws: Nostr.RelayMessageCodingError.invalidMessageShape) {
            _ = try Nostr.RelayMessageCodec.decodeServerMessage(
                Data("[\"NOTICE\"]".utf8),
                limits: limits
            )
        }
        #expect(
            throws: Nostr.RelayMessageCodingError.unsupportedMessageType("AUTH")
        ) {
            _ = try Nostr.RelayMessageCodec.decodeServerMessage(
                Data("[\"AUTH\",\"challenge\"]".utf8),
                limits: limits
            )
        }
        #expect(throws: Nostr.RelayMessageCodingError.invalidJSON) {
            _ = try Nostr.RelayMessageCodec.decodeServerMessage(
                Data("[\"NOTICE\",\"x\",]".utf8),
                limits: limits
            )
        }
        let tiny = try Nostr.RelayMessageCodingLimits(
            maximumFrameByteCount: 8,
            maximumFiltersPerRequest: 1,
            maximumValuesPerFilter: 1,
            maximumMessageStringByteCount: 8,
            event: eventLimits
        )
        #expect(
            throws: Nostr.RelayMessageCodingError
                .frameByteCountExceedsMaximum(maximum: 8, actual: 14)
        ) {
            _ = try Nostr.RelayMessageCodec.decodeServerMessage(
                Data("[\"NOTICE\",\"x\"]".utf8),
                limits: tiny
            )
        }
    }

    @Test("Validate subscription filter and caller-owned resource bounds")
    func validateInputsAndLimits() throws {
        #expect(throws: Nostr.RelayMessageCodingError.invalidSubscriptionIdentifier) {
            _ = try Nostr.SubscriptionIdentifier("")
        }
        #expect(throws: Nostr.RelayMessageCodingError.invalidSubscriptionIdentifier) {
            _ = try Nostr.SubscriptionIdentifier(String(repeating: "x", count: 65))
        }
        #expect(throws: Nostr.RelayMessageCodingError.emptyFilterSet) {
            _ = try Nostr.RelaySubscription(
                identifier: .init("round"),
                filters: []
            )
        }
        #expect(
            throws: Nostr.RelayMessageCodingError.duplicateFilterValue(
                field: "kinds"
            )
        ) {
            _ = try Nostr.RelayFilter(kinds: [1, 1])
        }
        #expect(throws: Nostr.RelayMessageCodingError.invalidFilterTimeRange) {
            _ = try Nostr.RelayFilter(since: 2, until: 1)
        }
        #expect(throws: Nostr.RelayMessageCodingError.invalidFilterLimit) {
            _ = try Nostr.RelayFilter(limit: -1)
        }
        #expect(throws: Nostr.RelayMessageCodingError.invalidResourceLimit) {
            _ = try Nostr.RelayMessageCodingLimits(
                maximumFrameByteCount: 0,
                maximumFiltersPerRequest: 1,
                maximumValuesPerFilter: 1,
                maximumMessageStringByteCount: 1,
                event: eventLimits
            )
        }

        let constrained = try Nostr.RelayMessageCodingLimits(
            maximumFrameByteCount: 8_192,
            maximumFiltersPerRequest: 1,
            maximumValuesPerFilter: 1,
            maximumMessageStringByteCount: 64,
            event: eventLimits
        )
        let twoFilters = try Nostr.RelaySubscription(
            identifier: .init("round"),
            filters: [try .init(kinds: [1]), try .init(kinds: [2])]
        )
        #expect(
            throws: Nostr.RelayMessageCodingError
                .filterCountExceedsMaximum(maximum: 1, actual: 2)
        ) {
            _ = try Nostr.RelayMessageCodec.encode(
                .request(twoFilters),
                limits: constrained
            )
        }
        let tooManyValues = try Nostr.RelaySubscription(
            identifier: .init("round"),
            filters: [try .init(kinds: [1, 2])]
        )
        #expect(
            throws: Nostr.RelayMessageCodingError
                .filterValueCountExceedsMaximum(maximum: 1, actual: 2)
        ) {
            _ = try Nostr.RelayMessageCodec.encode(
                .request(tooManyValues),
                limits: constrained
            )
        }
    }

    private var eventLimits: Nostr.EventCodingLimits {
        get throws {
            try .init(
                maximumEventJSONByteCount: 8_192,
                maximumTagCount: 16,
                maximumTagElementCount: 8,
                maximumStringByteCount: 4_096
            )
        }
    }

    private var limits: Nostr.RelayMessageCodingLimits {
        get throws {
            try .init(
                maximumFrameByteCount: 16_384,
                maximumFiltersPerRequest: 4,
                maximumValuesPerFilter: 16,
                maximumMessageStringByteCount: 4_096,
                event: eventLimits
            )
        }
    }

    private func makeEvent(
        content: String = "Mosaic relay frame"
    ) throws -> Nostr.Event {
        let signingKey = try OpalCrypto.Secp256k1.SigningKey(
            rawRepresentation: Data(repeating: 0, count: 31) + Data([1])
        )
        let template = try Nostr.EventTemplate(
            createdAt: 1_700_000_000,
            kind: 7,
            tags: [],
            content: content,
            limits: eventLimits
        )
        return try Nostr.EventSigner.sign(
            template,
            using: signingKey,
            auxiliaryRandomness: .init(
                rawRepresentation: Data(repeating: 0xA5, count: 32)
            ),
            limits: eventLimits
        )
    }

    private func hexadecimal(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }
}

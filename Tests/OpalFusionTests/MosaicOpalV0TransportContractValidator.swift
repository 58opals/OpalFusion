// MosaicOpalV0TransportContractValidator.swift

import Foundation
import OpalCrypto
@testable import OpalFusion
import Testing

@Suite("Mosaic Opal v0 transport contracts")
struct MosaicOpalV0TransportContractValidator {
    typealias OpalV0 = OpalFusion.Mosaic.OpalV0

    @Test("Freeze the conformance-only Nostr kind and size assignments")
    func freezeKindAndSizeAssignments() {
        #expect(OpalV0.EventKind.discovery.rawValue == 26_528)
        #expect(OpalV0.EventKind.control.rawValue == 21_939)
        #expect(OpalV0.EventKind.anonymous.rawValue == 20_652)
        #expect(OpalV0.paddedInnerPlaintextByteCount == 8_192)
        #expect(OpalV0.maximumInnerPayloadByteCount == 4_092)
        #expect(OpalV0.nip44ContentByteCount == 11_012)
        #expect(OpalV0.maximumEventJSONByteCount == 16_384)
    }

    @Test("Round-trip an empty fixed-size envelope")
    func roundTripEmptyEnvelope() throws {
        try validateRoundTrip(payload: [])
    }

    @Test("Round-trip a maximum fixed-size envelope")
    func roundTripMaximumEnvelope() throws {
        let encoded = try OpalV0.PaddedEnvelopeCodec.encode(
            Array(
                repeating: 0xab,
                count: OpalV0.maximumInnerPayloadByteCount
            )
        )
        let decoded = try OpalV0.PaddedEnvelopeCodec.decode(encoded)

        #expect(encoded.utf8.count == OpalV0.paddedInnerPlaintextByteCount)
        #expect(decoded.count == OpalV0.maximumInnerPayloadByteCount)
        #expect(decoded.allSatisfy { $0 == 0xab })
    }

    @Test("Produce the frozen NIP-44 content width")
    func produceFrozenNIP44ContentWidth() throws {
        let plaintext = try OpalV0.PaddedEnvelopeCodec.encode([0xab])
        let payload = try OpalCrypto.Nostr.NIP44.encrypt(
            plaintext,
            conversationKey: .init(
                rawRepresentation: Data(repeating: 0x11, count: 32)
            ),
            nonce: .init(rawRepresentation: Data(repeating: 0x22, count: 32)),
            maximumPlaintextByteCount: OpalV0.paddedInnerPlaintextByteCount
        )

        #expect(payload.encodedRepresentation.utf8.count == OpalV0.nip44ContentByteCount)
    }

    @Test("Reject every malformed fixed-size envelope class")
    func rejectMalformedFixedSizeEnvelopes() throws {
        #expect(
            throws: OpalV0.PaddedEnvelopeCodec.CodingError.payloadTooLarge(
                maximum: 4_092,
                actual: 4_093
            )
        ) {
            _ = try OpalV0.PaddedEnvelopeCodec.encode(
                Array(repeating: 0, count: 4_093)
            )
        }
        #expect(
            throws: OpalV0.PaddedEnvelopeCodec.CodingError.invalidEncodedLength(
                expected: 8_192,
                actual: 1
            )
        ) {
            _ = try OpalV0.PaddedEnvelopeCodec.decode("0")
        }

        var invalidHex = Array(try OpalV0.PaddedEnvelopeCodec.encode([]).utf8)
        invalidHex[0] = UInt8(ascii: "A")
        #expect(
            throws: OpalV0.PaddedEnvelopeCodec.CodingError.invalidLowercaseHexadecimal
        ) {
            _ = try OpalV0.PaddedEnvelopeCodec.decode(
                String(decoding: invalidHex, as: UTF8.self)
            )
        }

        var oversizedDeclaration = Array(try OpalV0.PaddedEnvelopeCodec.encode([]).utf8)
        oversizedDeclaration.replaceSubrange(0 ..< 8, with: Array("00000ffd".utf8))
        #expect(
            throws: OpalV0.PaddedEnvelopeCodec.CodingError.declaredPayloadTooLarge(
                maximum: 4_092,
                actual: 4_093
            )
        ) {
            _ = try OpalV0.PaddedEnvelopeCodec.decode(
                String(decoding: oversizedDeclaration, as: UTF8.self)
            )
        }

        var nonzeroPadding = Array(try OpalV0.PaddedEnvelopeCodec.encode([0xab]).utf8)
        nonzeroPadding[10] = UInt8(ascii: "1")
        #expect(throws: OpalV0.PaddedEnvelopeCodec.CodingError.nonzeroPadding) {
            _ = try OpalV0.PaddedEnvelopeCodec.decode(
                String(decoding: nonzeroPadding, as: UTF8.self)
            )
        }
    }

    @Test("Require distinct event and control identities with exact tags")
    func requireDistinctIdentitiesAndExactTags() throws {
        let eventKey = Array(repeating: UInt8(0x11), count: 32)
        let controlKey = Array(repeating: UInt8(0x22), count: 32)
        let binding = try OpalV0.IdentityBinding(
            eventPublicKey: eventKey,
            controlIdentity: controlKey
        )
        #expect(binding.eventPublicKey == eventKey)
        #expect(binding.controlIdentity == controlKey)
        #expect(
            throws: OpalV0.NostrContractError.reusedControlAndEventIdentity
        ) {
            _ = try OpalV0.IdentityBinding(
                eventPublicKey: eventKey,
                controlIdentity: eventKey
            )
        }
        #expect(
            throws: OpalV0.NostrContractError.invalidEventPublicKeyLength(actual: 31)
        ) {
            _ = try OpalV0.IdentityBinding(
                eventPublicKey: Array(repeating: 0, count: 31),
                controlIdentity: controlKey
            )
        }
        #expect(
            throws: OpalV0.NostrContractError.invalidControlIdentityLength(actual: 33)
        ) {
            _ = try OpalV0.IdentityBinding(
                eventPublicKey: eventKey,
                controlIdentity: Array(repeating: 0, count: 33)
            )
        }

        #expect(try OpalV0.validateDiscoveryTags([]) == ())
        #expect(throws: OpalV0.NostrContractError.invalidDiscoveryTags) {
            try OpalV0.validateDiscoveryTags([["p", "00"]])
        }

        let tags = try OpalV0.encryptedTags(recipientEventPublicKey: eventKey)
        #expect(tags == [["p", String(repeating: "11", count: 32)]])
        #expect(
            try OpalV0.validateEncryptedTags(
                tags,
                recipientEventPublicKey: eventKey
            ) == ()
        )
        #expect(throws: OpalV0.NostrContractError.invalidEncryptedTags) {
            try OpalV0.validateEncryptedTags([], recipientEventPublicKey: eventKey)
        }
        #expect(
            throws: OpalV0.NostrContractError.invalidEventPublicKeyLength(actual: 0)
        ) {
            _ = try OpalV0.encryptedTags(recipientEventPublicKey: [])
        }
    }

    private func validateRoundTrip(payload: [UInt8]) throws {
        let encoded = try OpalV0.PaddedEnvelopeCodec.encode(payload)
        #expect(encoded.utf8.count == OpalV0.paddedInnerPlaintextByteCount)
        #expect(encoded.utf8.allSatisfy { byte in
            (UInt8(ascii: "0") ... UInt8(ascii: "9")).contains(byte)
                || (UInt8(ascii: "a") ... UInt8(ascii: "f")).contains(byte)
        })
        #expect(try OpalV0.PaddedEnvelopeCodec.decode(encoded) == payload)
    }
}

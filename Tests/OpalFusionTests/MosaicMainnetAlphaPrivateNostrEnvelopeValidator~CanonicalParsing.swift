// MosaicMainnetAlphaPrivateNostrEnvelopeValidator~CanonicalParsing.swift

import Foundation
import OpalCrypto
import Testing
@testable import OpalFusion

extension MosaicMainnetAlphaPrivateNostrEnvelopeValidator {
    @Test("Fuzz canonical pre-manifest payload parsing deterministically")
    func fuzzCanonicalPreManifestPayloadParsingDeterministically() throws {
        let beacon = try MosaicPrivateDeploymentFixtures.discovery.beacons[0]
        let payload = try Alpha.PreManifestNostrPayloadDocument
            .makeAvailabilityBeacon(beacon)
        var state: UInt64 = 0x3C6E_F372_FE94_F82B

        for _ in 0 ..< 128 {
            state = state &* 6_364_136_223_846_793_005 &+ 1
            var mutation = payload.canonicalBytes
            let index = Int(state % UInt64(mutation.count))
            mutation[index] ^= UInt8(truncatingIfNeeded: state >> 40) | 1
            if let decoded = try? Alpha.PreManifestNostrPayloadDocument.decode(
                from: mutation
            ) {
                #expect(decoded.canonicalBytes == mutation)
            }
        }
    }

    var limits: Nostr.EventCodingLimits {
        get throws {
            try .init(
                maximumEventJSONByteCount: 200_000,
                maximumTagCount: 1,
                maximumTagElementCount: 2,
                maximumStringByteCount: 150_000
            )
        }
    }

    func resign(
        _ event: Nostr.Event,
        candidate: MosaicPrivateDeploymentFixtures.CandidateKeyMaterial,
        kind: UInt16,
        tags: [[String]],
        content: String,
        auxiliaryByte: UInt8
    ) throws -> Nostr.Event {
        let template = try Nostr.EventTemplate(
            createdAt: event.template.createdAt,
            kind: kind,
            tags: tags,
            content: content,
            limits: limits
        )
        return try Nostr.EventSigner.sign(
            template,
            using: candidate.signingKey,
            auxiliaryRandomness: auxiliaryRandomness(auxiliaryByte),
            limits: limits
        )
    }

    func auxiliaryRandomness(
        _ byte: UInt8
    ) throws -> OpalCrypto.Signature.BIP340.AuxiliaryRandomness {
        try .init(rawRepresentation: Data(repeating: byte, count: 32))
    }
}

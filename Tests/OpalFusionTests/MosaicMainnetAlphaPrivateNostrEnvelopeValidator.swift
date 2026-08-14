// MosaicMainnetAlphaPrivateNostrEnvelopeValidator.swift

import Foundation
import OpalCrypto
import Testing
@testable import OpalFusion

@Suite("Mosaic mainnet-alpha private Nostr envelope validation", .serialized)
struct MosaicMainnetAlphaPrivateNostrEnvelopeValidator {
    typealias Alpha = OpalFusion.Mosaic.OpalMainnetAlpha
    typealias Nostr = OpalFusion.Mosaic.NostrNamespace

    @Test("Sign and decode a canonical availability event")
    func signAndDecodeCanonicalAvailabilityEvent() throws {
        let fixture = try MosaicPrivateDeploymentFixtures.discovery
        let beacon = fixture.beacons[0]
        let candidate = fixture.candidate(for: beacon.core.discoveryIdentity)
        let payload = try Alpha.PreManifestNostrPayloadDocument
            .makeAvailabilityBeacon(beacon)
        let createdAt = fixture.epochStart + 1
        let event = try Alpha.PreManifestNostrCodec.makeEvent(
            for: payload,
            createdAtUnixSeconds: createdAt,
            using: candidate.signingKey,
            auxiliaryRandomness: auxiliaryRandomness(0xE1),
            limits: limits
        )
        #expect(event.template.kind == 26_540)
        #expect(
            event.template.tags
                == [["d", Alpha.PrivateDeploymentNostrSelector.identifier]]
        )
        #expect(
            try Alpha.PreManifestNostrCodec.decodeAvailabilityBeacon(
                event,
                discoveryEpochStartUnixSeconds: fixture.epochStart,
                currentUnixSeconds: createdAt
            ) == beacon
        )
        #expect(
            try Alpha.PreManifestNostrPayloadDocument.decode(
                from: payload.canonicalBytes
            ) == payload
        )
        #expect(throws: OpalFusion.Mosaic.CanonicalCodingError.trailingBytes(1)) {
            _ = try Alpha.PreManifestNostrPayloadDocument.decode(
                from: payload.canonicalBytes + [0]
            )
        }
    }

}

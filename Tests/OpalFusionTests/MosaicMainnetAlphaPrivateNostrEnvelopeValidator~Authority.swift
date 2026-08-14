// MosaicMainnetAlphaPrivateNostrEnvelopeValidator~Authority.swift

import Testing
@testable import OpalFusion

extension MosaicMainnetAlphaPrivateNostrEnvelopeValidator {
    @Test("Reject wrong event authority timing kind tags and canonical content")
    func rejectWrongEventAuthorityTimingKindTagsAndCanonicalContent() throws {
        let fixture = try MosaicPrivateDeploymentFixtures.discovery
        let beacon = fixture.beacons[0]
        let candidate = fixture.candidate(for: beacon.core.discoveryIdentity)
        let otherCandidate = fixture.candidates[1]
        let payload = try Alpha.PreManifestNostrPayloadDocument
            .makeAvailabilityBeacon(beacon)
        let createdAt = fixture.epochStart + 1
        let event = try Alpha.PreManifestNostrCodec.makeEvent(
            for: payload,
            createdAtUnixSeconds: createdAt,
            using: candidate.signingKey,
            auxiliaryRandomness: auxiliaryRandomness(0xE2),
            limits: limits
        )

        #expect(
            throws: Alpha.PreManifestNostrCodec.ValidationError
                .signingIdentityMismatch
        ) {
            _ = try Alpha.PreManifestNostrCodec.makeEvent(
                for: payload,
                createdAtUnixSeconds: createdAt,
                using: otherCandidate.signingKey,
                auxiliaryRandomness: auxiliaryRandomness(0xE3),
                limits: limits
            )
        }
        #expect(
            throws: Alpha.PreManifestNostrCodec.ValidationError
                .eventCreatedInFuture
        ) {
            _ = try Alpha.PreManifestNostrCodec.decodeAvailabilityBeacon(
                event,
                discoveryEpochStartUnixSeconds: fixture.epochStart,
                currentUnixSeconds: fixture.epochStart
            )
        }
        #expect(
            throws: Alpha.PreManifestNostrCodec.ValidationError.expired
        ) {
            _ = try Alpha.PreManifestNostrCodec.decodeAvailabilityBeacon(
                event,
                discoveryEpochStartUnixSeconds: fixture.epochStart,
                currentUnixSeconds: payload.expiryUnixSeconds + 1
            )
        }

        let wrongKind = try resign(
            event,
            candidate: candidate,
            kind: 26_541,
            tags: event.template.tags,
            content: event.template.content,
            auxiliaryByte: 0xE4
        )
        #expect(
            throws: Alpha.PreManifestNostrCodec.ValidationError.eventKindMismatch
        ) {
            _ = try Alpha.PreManifestNostrCodec.decodeAvailabilityBeacon(
                wrongKind,
                discoveryEpochStartUnixSeconds: fixture.epochStart,
                currentUnixSeconds: createdAt
            )
        }
        let wrongTags = try resign(
            event,
            candidate: candidate,
            kind: event.template.kind,
            tags: [["d", "foreign"]],
            content: event.template.content,
            auxiliaryByte: 0xE5
        )
        #expect(
            throws: Alpha.PreManifestNostrCodec.ValidationError.invalidTags
        ) {
            _ = try Alpha.PreManifestNostrCodec.decodeAvailabilityBeacon(
                wrongTags,
                discoveryEpochStartUnixSeconds: fixture.epochStart,
                currentUnixSeconds: createdAt
            )
        }
        let trailingContent = event.template.content + "00"
        let trailing = try resign(
            event,
            candidate: candidate,
            kind: event.template.kind,
            tags: event.template.tags,
            content: trailingContent,
            auxiliaryByte: 0xE6
        )
        #expect(throws: OpalFusion.Mosaic.CanonicalCodingError.trailingBytes(1)) {
            _ = try Alpha.PreManifestNostrCodec.decodeAvailabilityBeacon(
                trailing,
                discoveryEpochStartUnixSeconds: fixture.epochStart,
                currentUnixSeconds: createdAt
            )
        }
    }
}

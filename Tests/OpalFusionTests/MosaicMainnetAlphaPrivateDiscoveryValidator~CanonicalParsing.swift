// MosaicMainnetAlphaPrivateDiscoveryValidator~CanonicalParsing.swift

import Testing
@testable import OpalFusion

extension MosaicMainnetAlphaPrivateDiscoveryValidator {
    @Test("Reject candidate equivocation and insufficient formation")
    func rejectCandidateEquivocationAndInsufficientFormation() throws {
        let fixture = try MosaicPrivateDeploymentFixtures.discovery
        let first = fixture.beacons[0]
        let duplicate = try duplicateBeacon(first, auxiliaryByte: 0xD1)
        let selection = try makeSelection(
            beacons: fixture.beacons + [duplicate]
        )
        let reversedDuplicateSelection = try makeSelection(
            beacons: [duplicate] + Array(fixture.beacons.reversed())
        )
        #expect(selection.selectedBeacons.count == 9)
        #expect(selection == reversedDuplicateSelection)
        let selectedDuplicate = try #require(
            selection.selectedBeacons.first(where: {
                $0.core.discoveryIdentity == first.core.discoveryIdentity
            })
        )
        let expectedCanonicalBytes = duplicate.canonicalBytes
            .lexicographicallyPrecedes(first.canonicalBytes)
            ? duplicate.canonicalBytes
            : first.canonicalBytes
        #expect(selectedDuplicate.canonicalBytes == expectedCanonicalBytes)

        let candidate = fixture.candidate(for: first.core.discoveryIdentity)
        let conflicting = try MosaicPrivateDeploymentFixtures.makeBeacon(
            candidate: candidate,
            epochStart: fixture.epochStart,
            pool: fixture.pool,
            relaySet: fixture.relaySet,
            proofOfWorkNonce: 210_515_758,
            auxiliaryByte: 0xD2
        )
        #expect(
            throws: Alpha.CandidateSelectionValidation.ValidationError
                .discoveryIdentityEquivocation(
                    [UInt8](candidate.identity.rawRepresentation)
                )
        ) {
            _ = try makeSelection(
                beacons: fixture.beacons + [conflicting]
            )
        }
        #expect(
            throws: Alpha.CandidateSelectionValidation.ValidationError
                .insufficientCandidateCount(actual: 6)
        ) {
            _ = try makeSelection(
                beacons: fixture.beacons.prefix(6)
            )
        }
    }

    @Test("Fuzz canonical discovery parsers with a deterministic bound")
    func fuzzCanonicalDiscoveryParsersWithDeterministicBound() throws {
        let fixture = try MosaicPrivateDeploymentFixtures.discovery
        let selection = try makeSelection(beacons: fixture.beacons)
        let candidate = fixture.candidate(
            for: selection.selectedBeacons[0].core.discoveryIdentity
        )
        let acknowledgement = try MosaicPrivateDeploymentFixtures
            .makeAcknowledgement(selection: selection, candidate: candidate)
        var state: UInt64 = 0xBB67_AE85_84CA_A73B

        for original in [
            fixture.beacons[0].canonicalBytes,
            acknowledgement.canonicalBytes,
        ] {
            for _ in 0 ..< 64 {
                state = state &* 2_862_933_555_777_941_757 &+ 3_037_000_493
                var mutation = original
                let index = Int(state % UInt64(mutation.count))
                mutation[index] ^= UInt8(truncatingIfNeeded: state >> 32) | 1
                if let decoded = try? Alpha.AvailabilityBeaconDocument.decode(
                    from: mutation
                ) {
                    #expect(decoded.canonicalBytes == mutation)
                }
                if let decoded = try? Alpha.CandidateSetAcknowledgementDocument
                    .decode(from: mutation) {
                    #expect(decoded.canonicalBytes == mutation)
                }
            }
        }
    }

    func makeSelection<S: Sequence>(
        beacons: S
    ) throws -> Alpha.CandidateSelectionValidation
    where S.Element == Alpha.AvailabilityBeaconDocument {
        let fixture = try MosaicPrivateDeploymentFixtures.discovery
        return try .init(
            beacons: Array(beacons),
            discoveryEpochStartUnixSeconds: fixture.epochStart,
            opaquePool: fixture.pool,
            relaySet: fixture.relaySet
        )
    }

    private func duplicateBeacon(
        _ beacon: Alpha.AvailabilityBeaconDocument,
        auxiliaryByte: UInt8
    ) throws -> Alpha.AvailabilityBeaconDocument {
        let fixture = try MosaicPrivateDeploymentFixtures.discovery
        let candidate = fixture.candidate(for: beacon.core.discoveryIdentity)
        let signature = try MosaicPrivateDeploymentFixtures.sign(
            digestBytes: beacon.signatureDigest,
            using: candidate.signingKey,
            auxiliaryByte: auxiliaryByte
        )
        return try .init(
            core: beacon.core,
            claimedWorkBitCount: beacon.claimedWorkBitCount,
            signature: signature
        )
    }
}

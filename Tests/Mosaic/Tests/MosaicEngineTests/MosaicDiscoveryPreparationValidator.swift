// MosaicDiscoveryPreparationValidator.swift

import Foundation
import OpalCrypto
import Testing
@_spi(MosaicPrivateAlpha) @testable import MosaicEngine
@testable import OpalFusionCore
@Suite("Mosaic discovery preparation")
struct MosaicDiscoveryPreparationValidator {
    private typealias Preparation = OpalFusion.MosaicPrivateAlphaRuntime.DiscoveryPreparation

    @Test("Preparation reuses the frozen canonical documents and work predicate")
    func canonicalDocumentsAndWork() throws {
        let fixture = try MosaicPrivateDeploymentFixtures.makeDiscovery(candidateCount: 7)
        let preparation = try makePreparation()
        #expect(preparation.opaquePoolDocument == Data(fixture.pool.canonicalBytes))
        #expect(preparation.relaySetDocument == Data(fixture.relaySet.canonicalBytes))
        #expect(preparation.relaySetDigest == Data(fixture.relaySet.digest))
        #expect(preparation.beaconCutoffUnixSeconds == 1_800_000_060)
        #expect(Set(preparation.relayEndpointIdentifiers).count == 3)
        #expect(Set(preparation.relayOperatorDigests).count == 3)
        for beacon in fixture.beacons {
            #expect(try preparation.findAvailabilityNonce(
                discoveryVerificationKey: beacon.core.discoveryIdentity,
                startingAt: beacon.core.proofOfWorkNonce,
                count: 1
            ) == beacon.core.proofOfWorkNonce)
        }
        #expect(try preparation.findAvailabilityNonce(
            discoveryVerificationKey: fixture.beacons[0].core.discoveryIdentity,
            startingAt: 0,
            count: 1
        ) == nil)
    }

    @Test("Unreviewed shape, duplicate operators, and invalid epochs are rejected")
    func rejectsInvalidConfiguration() throws {
        #expect(throws: (any Error).self) { try makePreparation(epoch: 1_800_000_001) }
        #expect(throws: (any Error).self) { try makePreparation(epoch: UInt64.max - UInt64.max % 300) }
        #expect(throws: (any Error).self) { try makePreparation(pool: Data(repeating: 1, count: 31)) }
        #expect(throws: (any Error).self) { try makePreparation(relays: Array(relays.prefix(2))) }
        var duplicate = relays
        duplicate[1] = .init(endpoint: duplicate[1].endpoint, reviewedOperatorLabel: "FIXTURE OPERATOR 1")
        #expect(throws: (any Error).self) { try makePreparation(relays: duplicate) }
        duplicate = relays
        duplicate[1] = .init(endpoint: duplicate[0].endpoint, reviewedOperatorLabel: "fixture operator 2")
        #expect(throws: (any Error).self) { try makePreparation(relays: duplicate) }
    }

    @Test("Nonce batches are finite and never wrap the UInt64 space")
    func rejectsUnboundedSearch() throws {
        let preparation = try makePreparation()
        let key = try OpalCrypto.Secp256k1.PrivateKey.generate().makeSigningKey().bip340VerificationKey
        for count: UInt32 in [0, 65_537, .max] {
            #expect(throws: Preparation.PreparationFailure.invalidSearchRange) {
                try preparation.findAvailabilityNonce(discoveryVerificationKey: key, startingAt: 0, count: count)
            }
        }
        #expect(throws: Preparation.PreparationFailure.invalidSearchRange) {
            try preparation.findAvailabilityNonce(discoveryVerificationKey: key, startingAt: .max, count: 2)
        }
    }

    private var relays: [Preparation.Relay] {
        (1 ... 3).map {
            .init(endpoint: "wss://relay-\($0).example/", reviewedOperatorLabel: "fixture operator \($0)")
        }
    }

    private func makePreparation(
        epoch: UInt64 = 1_800_000_000,
        pool: Data = Data(repeating: 0x31, count: 32),
        relays: [Preparation.Relay]? = nil
    ) throws -> Preparation {
        try .init(epochStartUnixSeconds: epoch, appGeneratedOpaquePoolIdentifier: pool, relays: relays ?? self.relays)
    }
}

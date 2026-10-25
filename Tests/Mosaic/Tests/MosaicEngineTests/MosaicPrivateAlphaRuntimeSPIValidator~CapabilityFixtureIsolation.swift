import Foundation
import OpalCrypto
import Testing
@_spi(MosaicPrivateAlpha) @testable import MosaicEngine
@testable import OpalFusionCore

extension MosaicPrivateAlphaRuntimeSPIValidator {
    @Test(
        "Runtime capability fixtures preserve exact mailbox keys and independent effects",
        arguments: [true, false]
    )
    func isolateRuntimeCapabilityKeyMaterial(conductor: Bool) async throws {
        let formation = try MosaicPrivateDeploymentFixtures.makeFormation()
        let roster = formation.roleElection.roster
        let localIdentity = conductor
            ? roster.conductor
            : try #require(roster.contributors.first)
        let firstStores = RuntimeCapabilityFixtureStores()
        let secondStores = RuntimeCapabilityFixtureStores()
        let clock = ContinuousClock()
        let firstStarted = clock.now
        let first = try MosaicPrivateDeploymentFixtures.makeRuntimeCapabilities(
            formation: formation,
            localControlIdentity: Data(localIdentity.validatedBytes),
            admissionStore: firstStores.admission,
            publicationStore: firstStores.publication,
            terminalStore: firstStores.terminal,
            routeStore: firstStores.routes
        )
        let firstDuration = firstStarted.duration(to: clock.now)
        let secondStarted = clock.now
        let second = try MosaicPrivateDeploymentFixtures.makeRuntimeCapabilities(
            formation: formation,
            localControlIdentity: Data(localIdentity.validatedBytes),
            admissionStore: secondStores.admission,
            publicationStore: secondStores.publication,
            terminalStore: secondStores.terminal,
            routeStore: secondStores.routes
        )
        print(
            "Runtime capability fixture \(conductor ? "conductor" : "contributor") setup: "
                + "first \(firstDuration); repeat \(secondStarted.duration(to: clock.now))."
        )

        let expectedControlKeys = try roster.controlIdentities.indices.map {
            try runtimeFixtureReferenceSigningKey(seed: 100 + $0)
        }
        let expectedControlIdentities = roster.controlIdentities.map {
            Data($0.validatedBytes)
        }
        let expectedMailboxIdentities = expectedControlKeys.map {
            Data($0.publicKey.compressedRepresentation.dropFirst())
        }
        #expect(first.mailboxes.controlMailboxes == second.mailboxes.controlMailboxes)
        #expect(
            first.mailboxes.controlMailboxes.map(\.controlIdentity)
                == expectedControlIdentities
        )
        #expect(
            first.mailboxes.controlMailboxes.map {
                $0.eventVerificationKey.rawRepresentation
            } == expectedMailboxIdentities
        )
        let localIndex = try #require(
            roster.controlIdentities.firstIndex(of: localIdentity)
        )
        #expect(first.mailboxes.localControlRecipientSigningKey == expectedControlKeys[localIndex])
        #expect(second.mailboxes.localControlRecipientSigningKey == expectedControlKeys[localIndex])

        switch (first.mailboxes.anonymous, second.mailboxes.anonymous) {
        case let (.conductor(firstKeys), .conductor(secondKeys)):
            try #require(conductor)
            let count = roster.contributors.count * Alpha.componentCountPerContributor
            let expectedKeys = try (0 ..< count).map {
                try runtimeFixtureReferenceSigningKey(seed: 150 + $0)
            }
            #expect(firstKeys.count == count)
            #expect(firstKeys == secondKeys)
            #expect(firstKeys == expectedKeys)
            #expect(
                firstKeys.map { $0.publicKey.compressedRepresentation }
                    == expectedKeys.map { $0.publicKey.compressedRepresentation }
            )
        case let (.contributor(firstKeys), .contributor(secondKeys)):
            try #require(!conductor)
            let count = Alpha.componentCountPerContributor
            let expectedIdentities = try (0 ..< count).map {
                Data(
                    try runtimeFixtureReferenceSigningKey(seed: 400 + $0)
                        .publicKey.compressedRepresentation.dropFirst()
                )
            }
            #expect(firstKeys.count == count)
            #expect(firstKeys == secondKeys)
            #expect(firstKeys.map(\.rawRepresentation) == expectedIdentities)
        default:
            Issue.record("Repeated fixtures changed anonymous mailbox role.")
        }

        let binding = try makeBinding(seed: 0xD3)
        let firstChannels = [
            (first.admissionPersistence.load, first.admissionPersistence.compareAndSwap),
            (first.publicationPersistence.load, first.publicationPersistence.compareAndSwap),
            (first.terminalPersistence.load, first.terminalPersistence.compareAndSwap),
        ]
        let secondChannels = [
            (second.admissionPersistence.load, second.admissionPersistence.compareAndSwap),
            (second.publicationPersistence.load, second.publicationPersistence.compareAndSwap),
            (second.terminalPersistence.load, second.terminalPersistence.compareAndSwap),
        ]
        let firstPayload = Data([0xA1])
        let secondPayload = Data([0xB2])
        for (firstChannel, secondChannel) in zip(firstChannels, secondChannels) {
            #expect(try firstChannel.0(binding) == nil)
            #expect(try secondChannel.0(binding) == nil)
            #expect(try firstChannel.1(binding, nil, firstPayload) == firstPayload)
            #expect(try secondChannel.0(binding) == nil)
            #expect(try secondChannel.1(binding, nil, secondPayload) == secondPayload)
            #expect(try firstChannel.0(binding) == firstPayload)
            #expect(try secondChannel.0(binding) == secondPayload)
        }
        for store in [firstStores.admission, firstStores.publication, firstStores.terminal,
                      secondStores.admission, secondStores.publication, secondStores.terminal] {
            #expect(store.recordedCompareAndSwapCallCount == 1)
        }
        #expect(firstStores.routes.recordedProvisionCallCount == 0)
        #expect(secondStores.routes.recordedProvisionCallCount == 0)
        await #expect(throws: Runtime.Failure.invalidStateTransition) {
            try await first.relays.provisionRoutes([])
        }
        #expect(firstStores.routes.recordedProvisionCallCount == 1)
        #expect(secondStores.routes.recordedProvisionCallCount == 0)
        await #expect(throws: Runtime.Failure.invalidStateTransition) {
            try await second.relays.provisionRoutes([])
        }
        #expect(firstStores.routes.recordedProvisionCallCount == 1)
        #expect(secondStores.routes.recordedProvisionCallCount == 1)
    }
}

private struct RuntimeCapabilityFixtureStores {
    let admission = MosaicPrivateAlphaRuntimePersistenceStore()
    let publication = MosaicPrivateAlphaRuntimePersistenceStore()
    let terminal = MosaicPrivateAlphaRuntimePersistenceStore()
    let routes = MosaicPrivateAlphaRuntimePersistenceStore()
}

private func runtimeFixtureReferenceSigningKey(
    seed: Int
) throws -> OpalCrypto.Secp256k1.SigningKey {
    try .init(
        rawRepresentation: Data(repeating: 0, count: 30)
            + Data([UInt8(seed >> 8), UInt8(truncatingIfNeeded: seed)])
    )
}

extension MosaicPrivateAlphaRuntimeSPIValidator {
    @Test("Immutable key caches preserve count and scalar-domain boundaries")
    func preserveRuntimeCapabilityKeyCacheBoundaries() throws {
        let control = MosaicRuntimeCapabilityFixtureKeyCache<[Int]>()
        let anonymous = MosaicRuntimeCapabilityFixtureKeyCache<[Int]>()
        var controlBuilds: [Int] = []
        var anonymousBuilds: [Int] = []
        #expect(try control.value(for: 7) {
            controlBuilds.append(7)
            return Array(100 ..< 107)
        } == Array(100 ..< 107))
        #expect(try control.value(for: 9) {
            controlBuilds.append(9)
            return Array(100 ..< 109)
        } == Array(100 ..< 109))
        #expect(try control.value(for: 7) {
            controlBuilds.append(7)
            return Array(100 ..< 107)
        } == Array(100 ..< 107))
        #expect(controlBuilds == [7, 9])
        #expect(try anonymous.value(for: 7) {
            anonymousBuilds.append(7)
            return Array(400 ..< 407)
        } == Array(400 ..< 407))
        #expect(anonymousBuilds == [7])
    }
}

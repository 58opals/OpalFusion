// MosaicPrivateAlphaRuntimeSPIValidator~FixtureIsolation.swift

import Testing
@_spi(MosaicPrivateAlpha) @testable import OpalFusion

extension MosaicPrivateAlphaRuntimeSPIValidator {
    @Test("Formation templates preserve bindings and independent owner progress")
    func isolateFormationTemplateConsumers() async throws {
        let fixture = try MosaicPrivateDeploymentFixtures
            .makePrivateAlphaRuntimeProof()
        let firstBinding = try makeBinding(seed: 0xC7)
        let secondBinding = try makeBinding(seed: 0xC8)
        let firstSnapshot = try await MosaicPrivateAlphaFormationClient
            .makeSnapshot(at: .discovery, boundTo: firstBinding)
        #expect(throws: Runtime.Failure.recoveryBindingMismatch) {
            _ = try Runtime.loadRecovery(
                from: firstSnapshot,
                expectedBinding: secondBinding
            )
        }
        let first = try await resumedOwner(
            snapshot: firstSnapshot,
            binding: firstBinding
        )
        let event = try #require(fixture.beaconEvents.first)
        _ = try await persist(first.acceptAvailabilityBeacon(event), on: first)

        let secondSnapshot = try await MosaicPrivateAlphaFormationClient
            .makeSnapshot(at: .discovery, boundTo: secondBinding)
        let second = try await resumedOwner(
            snapshot: secondSnapshot,
            binding: secondBinding
        )
        _ = try await persist(second.acceptAvailabilityBeacon(event), on: second)
        #expect(
            try await first.acceptAvailabilityBeacon(event)
                == .ignoredDuplicate(.discovery)
        )
        #expect(
            try await second.acceptAvailabilityBeacon(event)
                == .ignoredDuplicate(.discovery)
        )
        #expect(
            try await MosaicPrivateAlphaFormationClient.makeSnapshot(
                at: .discovery,
                boundTo: firstBinding
            ) == firstSnapshot
        )
    }
}

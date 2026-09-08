// MosaicPrivateAlphaFormationClient.swift

import Foundation
@_spi(MosaicPrivateAlpha) @testable import OpalFusion

enum MosaicPrivateAlphaFormationClient {
    typealias Runtime = OpalFusion.MosaicPrivateAlphaRuntime

    private static let templates = MosaicFixtureRepository<[
        Runtime.RecoveryState
    ]>()

    static func makeSnapshot(
        at phase: Runtime.Phase,
        boundTo binding: Runtime.Binding
    ) async throws -> Data {
        let states = try await templates.load { try await makeTemplates() }
        guard let state = states.first(where: { $0.phase == phase }) else {
            throw Runtime.Failure.invalidStateTransition
        }
        return try Runtime.RecoveryState(
            binding: binding,
            revision: state.revision,
            discoveryEpochStartUnixSeconds:
                state.discoveryEpochStartUnixSeconds,
            phase: state.phase,
            preManifestDocuments: state.preManifestDocuments,
            preManifestAbortCause: state.preManifestAbortCause,
            manifestState: state.manifestState,
            postManifestJournalState: state.postManifestJournalState,
            publicationState: state.publicationState,
            terminalState: state.terminalState
        ).canonicalBytes()
    }

    private static func makeTemplates() async throws -> [Runtime.RecoveryState] {
        let fixture = try MosaicPrivateDeploymentFixtures
            .makePrivateAlphaRuntimeProof()
        let binding = try Runtime.Binding(
            attemptIdentifier: Data(repeating: 0xE0, count: 32),
            generationIdentifier: Data(repeating: 0xE1, count: 32),
            materialIdentifier: Data(repeating: 0xE2, count: 32)
        )
        let fresh = try Runtime.createFreshAttempt(
            boundTo: binding,
            discoveryEpochStartUnixSeconds: fixture.epoch
        )
        let owner = try Runtime.Owner(claiming: fresh)
        func acknowledge(_ step: Runtime.Step) async throws {
            guard case let .persist(transition) = step else {
                throw Runtime.Failure.invalidStateTransition
            }
            _ = try await owner.acknowledgePersistence(
                transition,
                exactReadback: transition.replacementSnapshot
            )
        }
        try await acknowledge(await owner.nextStep())
        try await acknowledge(owner.installPrivateDeploymentContext(
            opaquePoolDocument: fixture.opaquePoolDocument,
            relaySetDocument: fixture.relaySetDocument
        ))
        var states = [await owner.state]
        for event in fixture.beaconEvents {
            try await acknowledge(owner.acceptAvailabilityBeacon(event))
        }
        try await acknowledge(owner.completeDiscovery(
            currentUnixSeconds: fixture.epoch + 60
        ))
        states.append(await owner.state)
        for event in fixture.acknowledgementEvents {
            try await acknowledge(owner.acceptCandidateSetAcknowledgement(event))
        }
        try await acknowledge(owner.completeCandidateSetAgreement())
        states.append(await owner.state)
        for event in fixture.admissionEvents {
            try await acknowledge(owner.acceptCandidateAdmission(event))
        }
        try await acknowledge(owner.completeCandidateAdmission())
        states.append(await owner.state)
        for event in fixture.commitmentEvents {
            try await acknowledge(owner.acceptRoleCommitment(event))
        }
        try await acknowledge(owner.completeRoleCommitments())
        states.append(await owner.state)
        for event in fixture.revealEvents {
            try await acknowledge(owner.acceptRoleReveal(event))
        }
        try await acknowledge(owner.completeRoleElection())
        states.append(await owner.state)
        try await acknowledge(owner.acceptContributorNonceAllocation(
            fixture.nonceEvent
        ))
        try await acknowledge(owner.completeNonceAllocation())
        states.append(await owner.state)
        return states
    }
}

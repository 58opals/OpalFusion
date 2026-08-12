// MosaicMainnetAlphaPostManifestContributorTransportBridgeConformanceValidator.swift

import Foundation
import Testing
@testable import OpalFusion

@Suite(
    "Mosaic mainnet-alpha contributor transport real-RSABSSA conformance",
    .serialized
)
struct MosaicMainnetAlphaPostManifestContributorTransportBridgeConformanceValidator {
    typealias Support =
        MosaicMainnetAlphaPostManifestContributorTransportBridgeValidator
    typealias Alpha = Support.Alpha
    typealias Bridge = Support.Bridge
    typealias Coordinator = Support.Coordinator
    typealias ExecutionFixture = Support.ExecutionFixture
    typealias LocalAttempt = Support.LocalAttempt

    private enum ProbeFailure: Error {
        case injected
    }

    private struct SharedFixture: Sendable {
        let bridge: Support.SharedFixture
        let material: Alpha.LocalContributionMaterial
        let foreignMaterial: Alpha.LocalContributionMaterial
        let componentValidation:
            Coordinator.AnonymousComponentPublicationValidation
        let transcriptInclusion:
            LocalAttempt.TranscriptInclusionValidation
        let signatureValidation:
            Coordinator.AnonymousBCHSignaturePublicationValidation
    }

    private static let sharedFixtureTask = Task {
        try await makeSharedFixture()
    }

    @Test(
        "Conform real 23-slot material to every ordered transport callback",
        .timeLimit(.minutes(5))
    )
    func bindOrderedTransportCallbacks() async throws {
        let fixture = try await Self.sharedFixtureTask.value
        let common = fixture.bridge
        let routeFactory = Support.RouteFactory(endpoints: selectedEndpoints)
        let permitProbe = Support.PermitProbe()
        let authority = Support.PublicationAuthorityProbe(
            phaseStartUnixSeconds: common.context.phaseStartUnixSeconds
        )
        let bridge = try Support().makeBridge(
            fixture: common,
            routeFactory: routeFactory,
            permitProbe: permitProbe,
            authority: authority
        )
        let host = MosaicRuntimeCoordinatorHostProbe(
            lease: fixture.material.reservationLease,
            finalizedTransaction: common.finalizedTransaction
        )
        let execution = bridge.makeExecutionDependencies(
            transactionHost: host,
            previousOutputSource: common.previousOutputSource,
            makeLocalContributionMaterial: { eligibility, lease in
                #expect(eligibility == common.eligibility)
                #expect(lease == fixture.material.reservationLease)
                return fixture.material
            }
        )

        #expect(
            fixture.material.slots.map(\.slot)
                == Array(0 ..< Alpha.componentCountPerContributor)
        )
        _ = try await execution.makeLocalContributionMaterial(
            common.eligibility,
            fixture.material.reservationLease
        )
        try await execution.publishPlayerCommit(
            common.reservationValidation
        )
        try await execution.publishAnonymousComponents(
            fixture.componentValidation
        )
        try await execution.publishPreSignAcknowledgement(
            fixture.transcriptInclusion
        )
        try await execution.publishLocalBCHSignatures(
            fixture.signatureValidation
        )

        #expect(await bridge.state == .completed)
        #expect(
            await routeFactory.controlRequestCounts
                == Array(
                    repeating: common.context.roster.candidateCount,
                    count: 6
                )
        )
        #expect(
            await routeFactory.anonymousRequestCounts
                == [Alpha.componentCountPerContributor, 1]
        )
        let permitRequests = await permitProbe.requests
        #expect(
            permitRequests.filter { $0.kind == .components }.count
                == Alpha.componentCountPerContributor
        )
        #expect(
            permitRequests.filter { $0.kind == .bchSignatures }.count == 1
        )
        #expect(
            Set(
                permitRequests.filter { $0.kind == .components }
                    .map(\.recipientEventIdentity)
            ) == Set(
                fixture.componentValidation.entries.map {
                    Data($0.recipientEventIdentity)
                }
            )
        )
        #expect(
            Set(
                permitRequests.filter { $0.kind == .bchSignatures }
                    .map(\.recipientEventIdentity)
            ) == Set(
                fixture.signatureValidation.entries.map {
                    Data($0.recipientEventIdentity)
                }
            )
        )

        let authoritySnapshot = authority.snapshot()
        #expect(
            authoritySnapshot.expiries == [
                .playerCommit,
                .anonymousComponents,
                .preSignAcknowledgement,
                .localBCHSignatures,
            ]
        )
        #expect(authoritySnapshot.controlTimestamps.count == 6)
        #expect(
            authoritySnapshot.anonymousTimestamps.count
                == Alpha.componentCountPerContributor + 1
        )
        #expect(
            authoritySnapshot.controlTimestamps.allSatisfy {
                $0.expiryUnixSeconds == Support.expiryUnixSeconds
            }
        )
        #expect(
            authoritySnapshot.anonymousTimestamps.allSatisfy {
                $0.expiryUnixSeconds == Support.expiryUnixSeconds
            }
        )
    }

    @Test(
        "Reject real material with a foreign lease or contributor binding",
        .timeLimit(.minutes(5))
    )
    func rejectMaterialBindingMismatches() async throws {
        let fixture = try await Self.sharedFixtureTask.value
        let common = fixture.bridge
        let routeFactory = Support.RouteFactory(endpoints: selectedEndpoints)
        let permitProbe = Support.PermitProbe()
        let authority = Support.PublicationAuthorityProbe(
            phaseStartUnixSeconds: common.context.phaseStartUnixSeconds
        )
        let host = MosaicRuntimeCoordinatorHostProbe(
            lease: fixture.material.reservationLease,
            finalizedTransaction: common.finalizedTransaction
        )

        let foreignLeaseBridge = try Support().makeBridge(
            fixture: common,
            routeFactory: routeFactory,
            permitProbe: permitProbe,
            authority: authority
        )
        let foreignLeaseExecution = foreignLeaseBridge
            .makeExecutionDependencies(
                transactionHost: host,
                previousOutputSource: common.previousOutputSource,
                makeLocalContributionMaterial: { _, _ in
                    fixture.foreignMaterial
                }
            )
        await #expect(throws: Bridge.Failure.materialBindingFailed) {
            try await foreignLeaseExecution.makeLocalContributionMaterial(
                common.eligibility,
                fixture.material.reservationLease
            )
        }
        #expect(
            await foreignLeaseBridge.state
                == .terminal(.materialBindingFailed)
        )

        let foreignContributorBridge = try Support().makeBridge(
            fixture: common,
            routeFactory: routeFactory,
            permitProbe: permitProbe,
            authority: authority
        )
        let foreignContributorExecution = foreignContributorBridge
            .makeExecutionDependencies(
                transactionHost: host,
                previousOutputSource: common.previousOutputSource,
                makeLocalContributionMaterial: { _, _ in
                    fixture.foreignMaterial
                }
            )
        await #expect(throws: Bridge.Failure.materialBindingFailed) {
            try await foreignContributorExecution
                .makeLocalContributionMaterial(
                    common.eligibility,
                    fixture.foreignMaterial.reservationLease
                )
        }
        #expect(
            await foreignContributorBridge.state
                == .terminal(.materialBindingFailed)
        )
    }

    @Test(
        "Terminalize PlayerCommit publication when expiry authority fails",
        .timeLimit(.minutes(5))
    )
    func terminalizePlayerCommitExpiryFailure() async throws {
        try await assertExpiryFailure(for: .playerCommit)
    }

    @Test(
        "Terminalize failed control publication",
        .timeLimit(.minutes(5))
    )
    func terminalizeControlPublicationFailure() async throws {
        let fixture = try await Self.sharedFixtureTask.value
        let common = fixture.bridge
        let routeFactory = Support.RouteFactory(endpoints: selectedEndpoints)
        let permitProbe = Support.PermitProbe()
        let authority = Support.PublicationAuthorityProbe(
            phaseStartUnixSeconds: common.context.phaseStartUnixSeconds
        )
        let bridge = try Support().makeBridge(
            fixture: common,
            routeFactory: routeFactory,
            permitProbe: permitProbe,
            authority: authority,
            provideControlRoutes: { _ in
                throw ProbeFailure.injected
            }
        )
        let execution = makeExecution(bridge: bridge, fixture: fixture)
        _ = try await execution.makeLocalContributionMaterial(
            common.eligibility,
            fixture.material.reservationLease
        )
        await #expect(
            throws: Bridge.Failure.publicationFailed(.playerCommit)
        ) {
            try await execution.publishPlayerCommit(
                common.reservationValidation
            )
        }
        #expect(
            await bridge.state
                == .terminal(.publicationFailed(.playerCommit))
        )
    }

    @Test(
        "Drain concurrent relay publication before terminal state",
        .timeLimit(.minutes(5))
    )
    func drainConcurrentPublication() async throws {
        let fixture = try await Self.sharedFixtureTask.value
        let common = fixture.bridge
        let routeFactory = Support.RouteFactory(endpoints: selectedEndpoints)
        let permitProbe = Support.PermitProbe()
        let authority = Support.PublicationAuthorityProbe(
            phaseStartUnixSeconds: common.context.phaseStartUnixSeconds
        )
        let suspension = Support.ExplicitReleaseGate()
        await suspension.arm()
        let bridge = try Support().makeBridge(
            fixture: common,
            routeFactory: routeFactory,
            permitProbe: permitProbe,
            authority: authority,
            provideControlRoutes: { requests in
                await suspension.suspendIfArmed()
                return await routeFactory.controlRoutes(for: requests)
            }
        )
        let execution = makeExecution(bridge: bridge, fixture: fixture)
        _ = try await execution.makeLocalContributionMaterial(
            common.eligibility,
            fixture.material.reservationLease
        )
        let firstPublication = Task {
            try await execution.publishPlayerCommit(
                common.reservationValidation
            )
        }
        await suspension.waitUntilSuspended()
        #expect(await bridge.state == .publishing(.playerCommit))
        await #expect(throws: Bridge.Failure.concurrentOperation) {
            try await execution.publishPlayerCommit(
                common.reservationValidation
            )
        }
        await suspension.waitUntilCancellationRequested()
        #expect(await bridge.state == .draining(.concurrentOperation))
        await bridge.requestStop()
        await suspension.resume()
        await #expect(throws: Bridge.Failure.concurrentOperation) {
            try await firstPublication.value
        }
        #expect(
            await bridge.waitForTermination()
                == .terminal(.concurrentOperation)
        )
    }

    @Test(
        "Drain stopped relay publication before terminal state",
        .timeLimit(.minutes(5))
    )
    func drainStoppedPublication() async throws {
        let fixture = try await Self.sharedFixtureTask.value
        let common = fixture.bridge
        let routeFactory = Support.RouteFactory(endpoints: selectedEndpoints)
        let permitProbe = Support.PermitProbe()
        let authority = Support.PublicationAuthorityProbe(
            phaseStartUnixSeconds: common.context.phaseStartUnixSeconds
        )
        let suspension = Support.ExplicitReleaseGate()
        await suspension.arm()
        let bridge = try Support().makeBridge(
            fixture: common,
            routeFactory: routeFactory,
            permitProbe: permitProbe,
            authority: authority,
            provideControlRoutes: { requests in
                await suspension.suspendIfArmed()
                return await routeFactory.controlRoutes(for: requests)
            }
        )
        let execution = makeExecution(bridge: bridge, fixture: fixture)
        _ = try await execution.makeLocalContributionMaterial(
            common.eligibility,
            fixture.material.reservationLease
        )
        let publication = Task {
            try await execution.publishPlayerCommit(
                common.reservationValidation
            )
        }
        await suspension.waitUntilSuspended()
        #expect(await bridge.state == .publishing(.playerCommit))
        await bridge.requestStop()
        await suspension.waitUntilCancellationRequested()
        #expect(await bridge.state == .draining(.cancelled))
        await suspension.resume()
        await #expect(throws: Bridge.Failure.cancelled) {
            try await publication.value
        }
        #expect(
            await bridge.waitForTermination() == .terminal(.cancelled)
        )
        await #expect(throws: Bridge.Failure.inputAfterTermination) {
            try await execution.publishPlayerCommit(
                common.reservationValidation
            )
        }
    }

    @Test(
        "Drain directly cancelled relay publication before terminal state",
        .timeLimit(.minutes(5))
    )
    func drainCancelledPublication() async throws {
        let fixture = try await Self.sharedFixtureTask.value
        let common = fixture.bridge
        let routeFactory = Support.RouteFactory(endpoints: selectedEndpoints)
        let permitProbe = Support.PermitProbe()
        let authority = Support.PublicationAuthorityProbe(
            phaseStartUnixSeconds: common.context.phaseStartUnixSeconds
        )
        let suspension = Support.ExplicitReleaseGate()
        await suspension.arm()
        let bridge = try Support().makeBridge(
            fixture: common,
            routeFactory: routeFactory,
            permitProbe: permitProbe,
            authority: authority,
            provideControlRoutes: { requests in
                await suspension.suspendIfArmed()
                return await routeFactory.controlRoutes(for: requests)
            }
        )
        let execution = makeExecution(bridge: bridge, fixture: fixture)
        _ = try await execution.makeLocalContributionMaterial(
            common.eligibility,
            fixture.material.reservationLease
        )
        let publication = Task {
            try await execution.publishPlayerCommit(
                common.reservationValidation
            )
        }
        await suspension.waitUntilSuspended()
        publication.cancel()
        await suspension.waitUntilCancellationRequested()
        #expect(await bridge.state == .publishing(.playerCommit))
        await suspension.resume()
        await #expect(throws: Bridge.Failure.cancelled) {
            try await publication.value
        }
        #expect(
            await bridge.waitForTermination() == .terminal(.cancelled)
        )
        await bridge.requestStop()
        #expect(await bridge.state == .terminal(.cancelled))
    }

    @Test(
        "Terminalize component publication when expiry authority fails",
        .timeLimit(.minutes(5))
    )
    func terminalizeComponentExpiryFailure() async throws {
        try await assertExpiryFailure(for: .anonymousComponents)
    }

    @Test(
        "Terminalize acknowledgement publication when expiry authority fails",
        .timeLimit(.minutes(5))
    )
    func terminalizeAcknowledgementExpiryFailure() async throws {
        try await assertExpiryFailure(for: .preSignAcknowledgement)
    }

    @Test(
        "Terminalize signature publication when expiry authority fails",
        .timeLimit(.minutes(5))
    )
    func terminalizeSignatureExpiryFailure() async throws {
        try await assertExpiryFailure(for: .localBCHSignatures)
    }

    @Test(
        "Terminalize failed anonymous publication",
        .timeLimit(.minutes(5))
    )
    func terminalizeAnonymousPublicationFailure() async throws {
        let fixture = try await Self.sharedFixtureTask.value
        let common = fixture.bridge
        let routeFactory = Support.RouteFactory(endpoints: selectedEndpoints)
        let permitProbe = Support.PermitProbe()
        let authority = Support.PublicationAuthorityProbe(
            phaseStartUnixSeconds: common.context.phaseStartUnixSeconds
        )
        let bridge = try Support().makeBridge(
            fixture: common,
            routeFactory: routeFactory,
            permitProbe: permitProbe,
            authority: authority,
            awaitAnonymousPublicationPermit: { _ in
                throw ProbeFailure.injected
            }
        )
        let execution = makeExecution(bridge: bridge, fixture: fixture)
        _ = try await execution.makeLocalContributionMaterial(
            common.eligibility,
            fixture.material.reservationLease
        )
        try await execution.publishPlayerCommit(
            common.reservationValidation
        )
        await #expect(
            throws: Bridge.Failure.publicationFailed(.anonymousComponents)
        ) {
            try await execution.publishAnonymousComponents(
                fixture.componentValidation
            )
        }
        #expect(
            await bridge.state
                == .terminal(.publicationFailed(.anonymousComponents))
        )
    }

    private static func makeSharedFixture() async throws -> SharedFixture {
        let prepared = try await ExecutionFixture.prepare()
        let localMaterial = prepared.localMaterial
        let foreignMaterial = try #require(
            prepared.materialized.materials.first {
                $0.key != localMaterial.contributor
            }?.value
        )
        let reservationValidation = try Alpha.RuntimeSession
            .ReservationPublicationValidation(
                validating: .init(
                    attemptIdentifier: localMaterial.attemptIdentifier,
                    generationIdentifier: localMaterial.generationIdentifier,
                    materialIdentifier: localMaterial.materialIdentifier,
                    contributor: localMaterial.contributor,
                    manifest: localMaterial.manifest,
                    reservationLease: localMaterial.reservationLease,
                    playerCommit: localMaterial.playerCommit
                ),
                using: localMaterial
            )
        let common = try Support.makeSharedFixture(
            admission: prepared.admission,
            runtimeContext: prepared.session.context,
            reservationLease: localMaterial.reservationLease,
            reservationValidation: reservationValidation,
            previousOutputSource: prepared.previousOutputSource,
            finalizedTransaction: prepared.localFinalizedTransaction
        )
        let componentTokens = prepared.localAuthorizationValidation
            .componentAuthorizationTokens
        let componentPublications = try localMaterial.slots.map { slot in
            Coordinator.LocalAnonymousComponentPublication(
                slot: slot.slot,
                recipientEventIdentity: slot.recipientEventIdentity,
                payload: try .init(
                    roundIdentifier:
                        prepared.admission.manifest.core.roundIdentifier,
                    authorizationToken: componentTokens[slot.slot],
                    component: slot.component
                )
            )
        }
        let componentValidation = try Coordinator
            .AnonymousComponentPublicationValidation(
                validating: componentPublications,
                material: localMaterial,
                runtimeContext: prepared.session.context
            )
        let transcript = prepared.materialized.prepared.transcript
        let transcriptInclusion = try LocalAttempt
            .TranscriptInclusionValidation(
                attemptIdentifier: localMaterial.attemptIdentifier,
                generationIdentifier: localMaterial.generationIdentifier,
                contributor: localMaterial.contributor,
                materialIdentifier: localMaterial.materialIdentifier,
                transcript: transcript,
                using: localMaterial
            )
        let signaturePublications = try Alpha.LocalBCHSignatureBuilder.build(
            finalizedTransaction: prepared.localFinalizedTransaction,
            signingRequest: prepared.signingRequest,
            transcript: transcript,
            material: localMaterial,
            authorizationValidation: prepared.localAuthorizationValidation
        )
        let signatureValidation = try Coordinator
            .AnonymousBCHSignaturePublicationValidation(
                validating: signaturePublications,
                transcriptInclusion: transcriptInclusion,
                material: localMaterial,
                runtimeContext: prepared.session.context
            )
        return .init(
            bridge: common,
            material: localMaterial,
            foreignMaterial: foreignMaterial,
            componentValidation: componentValidation,
            transcriptInclusion: transcriptInclusion,
            signatureValidation: signatureValidation
        )
    }

    private func assertExpiryFailure(
        for publication: Bridge.Publication
    ) async throws {
        let fixture = try await Self.sharedFixtureTask.value
        let common = fixture.bridge
        let routeFactory = Support.RouteFactory(endpoints: selectedEndpoints)
        let permitProbe = Support.PermitProbe()
        let authority = Support.PublicationAuthorityProbe(
            phaseStartUnixSeconds: common.context.phaseStartUnixSeconds
        )
        let bridge = try Support().makeBridge(
            fixture: common,
            routeFactory: routeFactory,
            permitProbe: permitProbe,
            authority: authority,
            makeExpiryUnixSeconds: { requestedPublication in
                guard requestedPublication != publication else {
                    throw ProbeFailure.injected
                }
                return Support.expiryUnixSeconds
            }
        )
        let execution = makeExecution(bridge: bridge, fixture: fixture)
        _ = try await execution.makeLocalContributionMaterial(
            common.eligibility,
            fixture.material.reservationLease
        )
        try await publishPreceding(
            publication,
            execution: execution,
            fixture: fixture
        )
        await #expect(
            throws: Bridge.Failure.expiryUnavailable(publication)
        ) {
            try await publish(
                publication,
                execution: execution,
                fixture: fixture
            )
        }
        #expect(
            await bridge.state
                == .terminal(.expiryUnavailable(publication))
        )
        await #expect(throws: Bridge.Failure.inputAfterTermination) {
            try await publish(
                publication,
                execution: execution,
                fixture: fixture
            )
        }
    }

    private func makeExecution(
        bridge: Bridge,
        fixture: SharedFixture
    ) -> Coordinator.ExecutionDependencies {
        let common = fixture.bridge
        let host = MosaicRuntimeCoordinatorHostProbe(
            lease: fixture.material.reservationLease,
            finalizedTransaction: common.finalizedTransaction
        )
        return bridge.makeExecutionDependencies(
            transactionHost: host,
            previousOutputSource: common.previousOutputSource,
            makeLocalContributionMaterial: { _, _ in fixture.material }
        )
    }

    private func publishPreceding(
        _ publication: Bridge.Publication,
        execution: Coordinator.ExecutionDependencies,
        fixture: SharedFixture
    ) async throws {
        switch publication {
        case .playerCommit:
            return
        case .anonymousComponents:
            try await execution.publishPlayerCommit(
                fixture.bridge.reservationValidation
            )
        case .preSignAcknowledgement:
            try await execution.publishPlayerCommit(
                fixture.bridge.reservationValidation
            )
            try await execution.publishAnonymousComponents(
                fixture.componentValidation
            )
        case .localBCHSignatures:
            try await execution.publishPlayerCommit(
                fixture.bridge.reservationValidation
            )
            try await execution.publishAnonymousComponents(
                fixture.componentValidation
            )
            try await execution.publishPreSignAcknowledgement(
                fixture.transcriptInclusion
            )
        }
    }

    private func publish(
        _ publication: Bridge.Publication,
        execution: Coordinator.ExecutionDependencies,
        fixture: SharedFixture
    ) async throws {
        switch publication {
        case .playerCommit:
            try await execution.publishPlayerCommit(
                fixture.bridge.reservationValidation
            )
        case .anonymousComponents:
            try await execution.publishAnonymousComponents(
                fixture.componentValidation
            )
        case .preSignAcknowledgement:
            try await execution.publishPreSignAcknowledgement(
                fixture.transcriptInclusion
            )
        case .localBCHSignatures:
            try await execution.publishLocalBCHSignatures(
                fixture.signatureValidation
            )
        }
    }

    private var selectedEndpoints: [Support.Tracker.Endpoint] {
        Support.selectedEndpoints
    }
}

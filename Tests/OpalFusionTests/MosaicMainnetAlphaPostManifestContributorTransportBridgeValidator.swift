// MosaicMainnetAlphaPostManifestContributorTransportBridgeValidator.swift

import Foundation
import OpalCrypto
import Synchronization
import Testing
@testable import OpalFusion

@Suite("Mosaic mainnet-alpha contributor transport binding", .serialized)
struct MosaicMainnetAlphaPostManifestContributorTransportBridgeValidator {
    typealias Alpha = OpalFusion.Mosaic.OpalMainnetAlpha
    typealias Attempt = OpalFusion.Mosaic.Attempt
    typealias Bridge = Alpha.PostManifestContributorTransportBridge
    typealias ControlBridge = Alpha.PostManifestControlPublicationBridge
    typealias ControlPublisher = Alpha.PostManifestControlBatchPublisher
    typealias AnonymousBridge = Alpha.PostManifestAnonymousPublicationBridge
    typealias AnonymousPublisher = Alpha.PostManifestAnonymousBatchPublisher
    typealias Coordinator = Alpha.ReservationCoordinator
    typealias ExecutionFixture = MosaicMainnetAlphaExecutionFixtures
    typealias Fixture = MosaicMainnetAlphaAdmissionLedgerFixtures
    typealias LocalAttempt = OpalFusion.Mosaic.LocalAttempt
    typealias Nostr = OpalFusion.Mosaic.NostrNamespace
    typealias RuntimeSession = Alpha.RuntimeSession
    typealias Tracker = OpalFusion.Mosaic.RelayPublicationTracker
    typealias Transport = Alpha.PostManifestNIP59Transport

    private static let currentUnixSeconds: UInt64 = 1_800_000_100
    private static let expiryUnixSeconds: UInt64 = 1_800_000_200

    private enum ProbeFailure: Error {
        case injected
    }

    private struct ExactRelaySelectionValidator:
        Alpha.PostManifestRelaySelectionValidating
    {
        let expectedDigest: [UInt8]
        let expectedEndpoints: Set<Tracker.Endpoint>

        func validateRelaySelection(
            manifestRelaySetDigest: [UInt8],
            endpoints: [Tracker.Endpoint]
        ) throws {
            guard manifestRelaySetDigest == expectedDigest,
                  Set(endpoints) == expectedEndpoints else {
                throw ProbeFailure.injected
            }
        }
    }

    private struct SharedFixture: Sendable {
        let bootstrap: Alpha.PostManifestRuntimeDriver.Bootstrap
        let conductorBootstrap: Alpha.PostManifestRuntimeDriver.Bootstrap
        let manifest: Alpha.RoundManifest
        let context: ControlBridge.Context
        let eligibility: Coordinator.ReservationEligibility
        let material: Alpha.LocalContributionMaterial
        let foreignMaterial: Alpha.LocalContributionMaterial
        let reservationValidation:
            RuntimeSession.ReservationPublicationValidation
        let componentValidation:
            Coordinator.AnonymousComponentPublicationValidation
        let transcriptInclusion:
            LocalAttempt.TranscriptInclusionValidation
        let signatureValidation:
            Coordinator.AnonymousBCHSignaturePublicationValidation
        let previousOutputSource: ExecutionFixture.PreviousOutputSource
        let finalizedTransaction: OpalFusion.Host.FinalizedTransaction
        let controlSigningKey: OpalCrypto.Secp256k1.SigningKey
        let controlEventSigningKey: OpalCrypto.Secp256k1.SigningKey
        let controlRecipients: [ControlBridge.Recipient]
        let localControlRecipientCapability: Transport.RecipientCapability
        let relaySelection: Alpha.PostManifestRelaySelectionValidation
        let codingLimits: Nostr.RelayMessageCodingLimits
    }

    private final class PublicationAuthorityProbe: Sendable {
        private struct Storage: Sendable {
            var expiries: [Bridge.Publication] = []
            var controlTimestamps: [ControlBridge.TimestampRequest] = []
            var anonymousTimestamps: [AnonymousBridge.TimestampRequest] = []
        }

        private let phaseStartUnixSeconds: UInt64
        private let storage = Mutex(Storage())

        init(phaseStartUnixSeconds: UInt64) {
            self.phaseStartUnixSeconds = phaseStartUnixSeconds
        }

        func expiry(for publication: Bridge.Publication) -> UInt64 {
            storage.withLock { $0.expiries.append(publication) }
            return MosaicMainnetAlphaPostManifestContributorTransportBridgeValidator
                .expiryUnixSeconds
        }

        func controlTimestamps(
            for request: ControlBridge.TimestampRequest
        ) throws -> Transport.LayerTimestamps {
            storage.withLock { $0.controlTimestamps.append(request) }
            return try timestamps()
        }

        func anonymousTimestamps(
            for request: AnonymousBridge.TimestampRequest
        ) throws -> Transport.LayerTimestamps {
            storage.withLock { $0.anonymousTimestamps.append(request) }
            return try timestamps()
        }

        func snapshot() -> (
            expiries: [Bridge.Publication],
            controlTimestamps: [ControlBridge.TimestampRequest],
            anonymousTimestamps: [AnonymousBridge.TimestampRequest]
        ) {
            storage.withLock {
                ($0.expiries, $0.controlTimestamps, $0.anonymousTimestamps)
            }
        }

        private func timestamps() throws -> Transport.LayerTimestamps {
            try .init(
                phaseStartUnixSeconds: phaseStartUnixSeconds,
                currentUnixSeconds:
                    MosaicMainnetAlphaPostManifestContributorTransportBridgeValidator
                        .currentUnixSeconds,
                sealCreatedAt:
                    MosaicMainnetAlphaPostManifestContributorTransportBridgeValidator
                        .currentUnixSeconds - 2,
                giftWrapCreatedAt:
                    MosaicMainnetAlphaPostManifestContributorTransportBridgeValidator
                        .currentUnixSeconds - 1
            )
        }
    }

    private actor PermitProbe {
        private(set) var requests: [
            AnonymousPublisher.PublicationPermitRequest
        ] = []

        func permit(
            _ request: AnonymousPublisher.PublicationPermitRequest
        ) {
            requests.append(request)
        }
    }

    /// Holds an operation past cancellation until the test explicitly releases it.
    private actor ExplicitReleaseGate {
        private var isArmed = false
        private var hasSuspended = false
        private var resumeContinuation: CheckedContinuation<Void, Never>?
        private let suspendedStream: AsyncStream<Void>
        private let suspendedContinuation: AsyncStream<Void>.Continuation
        private let cancellationStream: AsyncStream<Void>
        private let cancellationContinuation: AsyncStream<Void>.Continuation

        init() {
            (suspendedStream, suspendedContinuation) = AsyncStream<Void>
                .makeStream(bufferingPolicy: .bufferingNewest(1))
            (cancellationStream, cancellationContinuation) = AsyncStream<Void>
                .makeStream(bufferingPolicy: .bufferingNewest(1))
        }

        func arm() {
            isArmed = true
        }

        func suspendIfArmed() async {
            guard isArmed, !hasSuspended else { return }
            hasSuspended = true
            suspendedContinuation.yield()
            let cancellationContinuation = cancellationContinuation
            await withTaskCancellationHandler {
                await withCheckedContinuation { continuation in
                    resumeContinuation = continuation
                }
            } onCancel: {
                cancellationContinuation.yield()
            }
        }

        func waitUntilSuspended() async {
            guard !hasSuspended else { return }
            for await _ in suspendedStream { return }
        }

        func waitUntilCancellationRequested() async {
            for await _ in cancellationStream { return }
        }

        func resume() {
            resumeContinuation?.resume()
            resumeContinuation = nil
        }
    }

    private actor RouteFactory {
        private let endpoints: [Tracker.Endpoint]
        private(set) var controlRequestCounts: [Int] = []
        private(set) var anonymousRequestCounts: [Int] = []

        init(endpoints: [Tracker.Endpoint]) {
            self.endpoints = endpoints
        }

        func controlRoutes(
            for requests: [ControlPublisher.RecipientRouteRequest]
        ) -> [ControlPublisher.RecipientRouteGroup] {
            controlRequestCounts.append(requests.count)
            return requests.map { request in
                .init(
                    recipientEventIdentity: request.recipientEventIdentity,
                    routes: endpoints.map {
                        .init(
                            endpoint: $0,
                            connection: ImmediateAcknowledgementConnection()
                        )
                    }
                )
            }
        }

        func anonymousRoutes(
            for requests: [AnonymousPublisher.RecipientRouteRequest]
        ) -> [AnonymousPublisher.RecipientRouteGroup] {
            anonymousRequestCounts.append(requests.count)
            return requests.map { request in
                .init(
                    recipientEventIdentity: request.recipientEventIdentity,
                    routes: endpoints.map {
                        .init(
                            endpoint: $0,
                            connection: ImmediateAcknowledgementConnection()
                        )
                    }
                )
            }
        }
    }

    private actor ImmediateAcknowledgementConnection:
        OpalFusion.Mosaic.TorWebSocketConnectioning
    {
        private let stream: MessageStream
        private let continuation: MessageStream.Continuation
        private var isClosed = false

        init() {
            (stream, continuation) = MessageStream.makeStream()
        }

        func open(
            maximumIncomingMessageByteCount _: Int
        ) async throws -> MessageStream {
            guard !isClosed else { throw CancellationError() }
            return stream
        }

        func send(text: String) async throws {
            guard !isClosed else { throw CancellationError() }
            let object = try JSONSerialization.jsonObject(
                with: Data(text.utf8)
            )
            guard let array = object as? [Any],
                  array.count == 2,
                  array[0] as? String == "EVENT",
                  let event = array[1] as? [String: Any],
                  let identifier = event["id"] as? String else {
                throw ProbeFailure.injected
            }
            continuation.yield(
                .text(
                    Data(
                        ("[\"OK\",\"" + identifier
                            + "\",true,\"accepted\"]").utf8
                    )
                )
            )
        }

        func close() async {
            guard !isClosed else { return }
            isClosed = true
            continuation.finish()
        }
    }

    private static let sharedFixtureTask = Task {
        try await makeSharedFixture()
    }

    init() throws {
        try MosaicMainnetAlphaFixtures.requireAuthorizationEvaluators()
    }

    @Test(
        "Bind material to every ordered contributor transport callback",
        .timeLimit(.minutes(5))
    )
    func bindOrderedTransportCallbacks() async throws {
        let fixture = try await Self.sharedFixtureTask.value
        let routeFactory = RouteFactory(endpoints: selectedEndpoints)
        let permitProbe = PermitProbe()
        let authority = PublicationAuthorityProbe(
            phaseStartUnixSeconds: fixture.context.phaseStartUnixSeconds
        )
        let bridge = try makeBridge(
            fixture: fixture,
            routeFactory: routeFactory,
            permitProbe: permitProbe,
            authority: authority
        )
        let host = MosaicRuntimeCoordinatorHostProbe(
            lease: fixture.material.reservationLease,
            finalizedTransaction: fixture.finalizedTransaction
        )
        let execution = bridge.makeExecutionDependencies(
            transactionHost: host,
            previousOutputSource: fixture.previousOutputSource,
            makeLocalContributionMaterial: { eligibility, lease in
                #expect(eligibility == fixture.eligibility)
                #expect(lease == fixture.material.reservationLease)
                return fixture.material
            }
        )

        let inboundRoutes = selectedEndpoints.map {
            Alpha.PostManifestRelayRoute(
                endpoint: $0,
                connection: ImmediateAcknowledgementConnection()
            )
        }
        let inboundSubscriptions = try Dictionary(
            uniqueKeysWithValues: selectedEndpoints.enumerated().map {
                index,
                endpoint in
                (endpoint, try Nostr.SubscriptionIdentifier("inbound-\(index)"))
            }
        )
        let inbound = try await bridge.makeInboundControlRouteGroup(
            routes: inboundRoutes,
            subscriptionIdentifiers: inboundSubscriptions
        )
        #expect(inbound.recipient.channel == .control)
        #expect(
            inbound.recipient.recipientEventIdentity
                == fixture.localControlRecipientCapability
                    .recipientEventIdentity
        )
        #expect(inbound.routes.map(\.endpoint) == selectedEndpoints)
        #expect(
            inbound.routes.map { ObjectIdentifier($0.connection) }
                == inboundRoutes.map { ObjectIdentifier($0.connection) }
        )
        #expect(inbound.subscriptionIdentifiers == inboundSubscriptions)
        #expect(inbound.isBound(to: fixture.bootstrap))
        let foreignBootstrap = Alpha.PostManifestRuntimeDriver.Bootstrap(
            validatedAttempt: fixture.bootstrap.validatedAttempt,
            attemptIdentifier: .init(
                validatedBytes: Array(repeating: 0xFA, count: 32)
            ),
            generationIdentifier: fixture.bootstrap.generationIdentifier,
            materialIdentifier: fixture.bootstrap.materialIdentifier,
            localControlIdentity: fixture.bootstrap.localControlIdentity,
            proposalValidation: fixture.bootstrap.proposalValidation
        )
        #expect(!inbound.isBound(to: foreignBootstrap))

        let material = try await execution.makeLocalContributionMaterial(
            fixture.eligibility,
            fixture.material.reservationLease
        )
        #expect(material.materialIdentifier == fixture.material.materialIdentifier)
        try await execution.publishPlayerCommit(
            fixture.reservationValidation
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
                == Array(repeating: fixture.context.roster.candidateCount, count: 6)
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
                $0.expiryUnixSeconds == Self.expiryUnixSeconds
            }
        )
        #expect(
            authoritySnapshot.anonymousTimestamps.allSatisfy {
                $0.expiryUnixSeconds == Self.expiryUnixSeconds
            }
        )
        await bridge.requestStop()
        await bridge.requestStop()
        #expect(await bridge.waitForTermination() == .completed)
        await #expect(throws: Bridge.Failure.inputAfterTermination) {
            try await execution.publishLocalBCHSignatures(
                fixture.signatureValidation
            )
        }
        await #expect(throws: Bridge.Failure.inputAfterTermination) {
            _ = try await bridge.makeInboundControlRouteGroup(
                routes: inboundRoutes,
                subscriptionIdentifiers: inboundSubscriptions
            )
        }
    }

    @Test(
        "Reject wrong role, mailbox, order, and material before exposure",
        .timeLimit(.minutes(5))
    )
    func rejectInvalidBindingsBeforeExposure() async throws {
        let fixture = try await Self.sharedFixtureTask.value
        let routeFactory = RouteFactory(endpoints: selectedEndpoints)
        let permitProbe = PermitProbe()
        let authority = PublicationAuthorityProbe(
            phaseStartUnixSeconds: fixture.context.phaseStartUnixSeconds
        )

        let invalidBootstrap = Alpha.PostManifestRuntimeDriver.Bootstrap(
            validatedAttempt: fixture.bootstrap.validatedAttempt,
            attemptIdentifier: fixture.bootstrap.attemptIdentifier,
            generationIdentifier: fixture.bootstrap.generationIdentifier,
            materialIdentifier: fixture.bootstrap.materialIdentifier,
            localControlIdentity: .init(
                validatedBytes: Array(repeating: 0xFF, count: 32)
            ),
            proposalValidation: fixture.bootstrap.proposalValidation
        )
        #expect(
            throws: Bridge.InitializationError.invalidContext(
                .runtimeBootstrapMismatch
            )
        ) {
            _ = try makeBridge(
                fixture: fixture,
                routeFactory: routeFactory,
                permitProbe: permitProbe,
                authority: authority,
                bootstrap: invalidBootstrap
            )
        }

        #expect(throws: Bridge.InitializationError.localPeerIsNotContributor) {
            _ = try makeBridge(
                fixture: fixture,
                routeFactory: routeFactory,
                permitProbe: permitProbe,
                authority: authority,
                bootstrap: fixture.conductorBootstrap
            )
        }
        #expect(
            throws: Bridge.InitializationError.localControlRecipientMismatch
        ) {
            _ = try makeBridge(
                fixture: fixture,
                routeFactory: routeFactory,
                permitProbe: permitProbe,
                authority: authority,
                localControlRecipientCapability: .init(
                    channel: .control,
                    signingKey: try signingKey(120)
                )
            )
        }
        #expect(
            throws: Bridge.InitializationError.missingLocalControlRecipient
        ) {
            _ = try makeBridge(
                fixture: fixture,
                routeFactory: routeFactory,
                permitProbe: permitProbe,
                authority: authority,
                controlRecipients: fixture.controlRecipients.filter {
                    $0.controlIdentity != fixture.context.localControlIdentity
                }
            )
        }
        #expect(
            throws: Bridge.InitializationError.controlPublisher(
                .invalidOutputBufferLimit
            )
        ) {
            _ = try makeBridge(
                fixture: fixture,
                routeFactory: routeFactory,
                permitProbe: permitProbe,
                authority: authority,
                maximumPendingRelayOutputCount: 0
            )
        }
        #expect(
            throws: Bridge.InitializationError.controlBridge(
                .reusedControlAndEventIdentity
            )
        ) {
            _ = try makeBridge(
                fixture: fixture,
                routeFactory: routeFactory,
                permitProbe: permitProbe,
                authority: authority,
                controlEventSigningKey: fixture.controlSigningKey
            )
        }

        let idleBridge = try makeBridge(
            fixture: fixture,
            routeFactory: routeFactory,
            permitProbe: permitProbe,
            authority: authority
        )
        await idleBridge.requestStop()
        await idleBridge.requestStop()
        #expect(
            await idleBridge.waitForTermination()
                == .terminal(.cancelled)
        )
        await #expect(throws: Bridge.Failure.inputAfterTermination) {
            _ = try await idleBridge.makeInboundControlRouteGroup(
                routes: [],
                subscriptionIdentifiers: [:]
            )
        }

        let earlyBridge = try makeBridge(
            fixture: fixture,
            routeFactory: routeFactory,
            permitProbe: permitProbe,
            authority: authority
        )
        let host = MosaicRuntimeCoordinatorHostProbe(
            lease: fixture.material.reservationLease,
            finalizedTransaction: fixture.finalizedTransaction
        )
        let earlyExecution = earlyBridge.makeExecutionDependencies(
            transactionHost: host,
            previousOutputSource: fixture.previousOutputSource,
            makeLocalContributionMaterial: { _, _ in fixture.material }
        )
        await #expect(throws: Bridge.Failure.invalidPublicationOrder) {
            try await earlyExecution.publishPlayerCommit(
                fixture.reservationValidation
            )
        }
        #expect(
            await earlyBridge.state
                == .terminal(.invalidPublicationOrder)
        )

        let foreignBridge = try makeBridge(
            fixture: fixture,
            routeFactory: routeFactory,
            permitProbe: permitProbe,
            authority: authority
        )
        let foreignExecution = foreignBridge.makeExecutionDependencies(
            transactionHost: host,
            previousOutputSource: fixture.previousOutputSource,
            makeLocalContributionMaterial: { _, _ in fixture.foreignMaterial }
        )
        await #expect(throws: Bridge.Failure.materialBindingFailed) {
            try await foreignExecution.makeLocalContributionMaterial(
                fixture.eligibility,
                fixture.material.reservationLease
            )
        }
        #expect(
            await foreignBridge.state
                == .terminal(.materialBindingFailed)
        )

        let foreignContextBridge = try makeBridge(
            fixture: fixture,
            routeFactory: routeFactory,
            permitProbe: permitProbe,
            authority: authority
        )
        let foreignContextExecution = foreignContextBridge
            .makeExecutionDependencies(
                transactionHost: host,
                previousOutputSource: fixture.previousOutputSource,
                makeLocalContributionMaterial: { _, _ in
                    fixture.foreignMaterial
                }
            )
        await #expect(throws: Bridge.Failure.materialBindingFailed) {
            try await foreignContextExecution.makeLocalContributionMaterial(
                fixture.eligibility,
                fixture.foreignMaterial.reservationLease
            )
        }
        #expect(
            await foreignContextBridge.state
                == .terminal(.materialBindingFailed)
        )

        let mismatchedEligibilityBridge = try makeBridge(
            fixture: fixture,
            routeFactory: routeFactory,
            permitProbe: permitProbe,
            authority: authority
        )
        let materialCallCount = Mutex(0)
        let mismatchedEligibilityExecution = mismatchedEligibilityBridge
            .makeExecutionDependencies(
                transactionHost: host,
                previousOutputSource: fixture.previousOutputSource,
                makeLocalContributionMaterial: { _, _ in
                    materialCallCount.withLock { $0 += 1 }
                    return fixture.material
                }
            )
        let mismatchedEligibility = Coordinator.ReservationEligibility(
            context: .init(
                attemptIdentifier: .init(
                    validatedBytes: Array(repeating: 0xFA, count: 32)
                ),
                generationIdentifier: fixture.eligibility.context
                    .generationIdentifier,
                materialIdentifier: fixture.eligibility.context
                    .materialIdentifier,
                localControlIdentity: fixture.eligibility.context
                    .localControlIdentity,
                localRole: fixture.eligibility.context.localRole,
                roster: fixture.eligibility.context.roster,
                proposalRoundIdentifier: fixture.eligibility.context
                    .proposalRoundIdentifier
            ),
            manifest: fixture.manifest
        )
        await #expect(throws: Bridge.Failure.materialBindingFailed) {
            try await mismatchedEligibilityExecution
                .makeLocalContributionMaterial(
                    mismatchedEligibility,
                    fixture.material.reservationLease
                )
        }
        #expect(materialCallCount.withLock { $0 } == 0)
        #expect(await routeFactory.controlRequestCounts.isEmpty)
        #expect(await routeFactory.anonymousRequestCounts.isEmpty)
        #expect(await permitProbe.requests.isEmpty)

        let materialFailureBridge = try makeBridge(
            fixture: fixture,
            routeFactory: routeFactory,
            permitProbe: permitProbe,
            authority: authority
        )
        let materialFailureExecution = materialFailureBridge
            .makeExecutionDependencies(
                transactionHost: host,
                previousOutputSource: fixture.previousOutputSource,
                makeLocalContributionMaterial: { _, _ in
                    throw ProbeFailure.injected
                }
            )
        await #expect(throws: Bridge.Failure.materialConstructionFailed) {
            try await materialFailureExecution.makeLocalContributionMaterial(
                fixture.eligibility,
                fixture.material.reservationLease
            )
        }
        #expect(
            await materialFailureBridge.state
                == .terminal(.materialConstructionFailed)
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
        "Terminalize failed control and anonymous publications",
        .timeLimit(.minutes(5))
    )
    func terminalizePublicationFailures() async throws {
        let fixture = try await Self.sharedFixtureTask.value
        let routeFactory = RouteFactory(endpoints: selectedEndpoints)
        let permitProbe = PermitProbe()
        let authority = PublicationAuthorityProbe(
            phaseStartUnixSeconds: fixture.context.phaseStartUnixSeconds
        )
        let host = MosaicRuntimeCoordinatorHostProbe(
            lease: fixture.material.reservationLease,
            finalizedTransaction: fixture.finalizedTransaction
        )

        let controlBridge = try makeBridge(
            fixture: fixture,
            routeFactory: routeFactory,
            permitProbe: permitProbe,
            authority: authority,
            provideControlRoutes: { _ in
                throw ProbeFailure.injected
            }
        )
        let controlExecution = controlBridge.makeExecutionDependencies(
            transactionHost: host,
            previousOutputSource: fixture.previousOutputSource,
            makeLocalContributionMaterial: { _, _ in fixture.material }
        )
        _ = try await controlExecution.makeLocalContributionMaterial(
            fixture.eligibility,
            fixture.material.reservationLease
        )
        await #expect(
            throws: Bridge.Failure.publicationFailed(.playerCommit)
        ) {
            try await controlExecution.publishPlayerCommit(
                fixture.reservationValidation
            )
        }
        #expect(
            await controlBridge.state
                == .terminal(.publicationFailed(.playerCommit))
        )

        let anonymousBridge = try makeBridge(
            fixture: fixture,
            routeFactory: routeFactory,
            permitProbe: permitProbe,
            authority: authority,
            awaitAnonymousPublicationPermit: { _ in
                throw ProbeFailure.injected
            }
        )
        let anonymousExecution = anonymousBridge.makeExecutionDependencies(
            transactionHost: host,
            previousOutputSource: fixture.previousOutputSource,
            makeLocalContributionMaterial: { _, _ in fixture.material }
        )
        _ = try await anonymousExecution.makeLocalContributionMaterial(
            fixture.eligibility,
            fixture.material.reservationLease
        )
        try await anonymousExecution.publishPlayerCommit(
            fixture.reservationValidation
        )
        await #expect(
            throws: Bridge.Failure.publicationFailed(.anonymousComponents)
        ) {
            try await anonymousExecution.publishAnonymousComponents(
                fixture.componentValidation
            )
        }
        #expect(
            await anonymousBridge.state
                == .terminal(.publicationFailed(.anonymousComponents))
        )
    }

    @Test(
        "Drain concurrent relay publication before terminal state",
        .timeLimit(.minutes(5))
    )
    func drainConcurrentPublication() async throws {
        let fixture = try await Self.sharedFixtureTask.value
        let routeFactory = RouteFactory(endpoints: selectedEndpoints)
        let permitProbe = PermitProbe()
        let authority = PublicationAuthorityProbe(
            phaseStartUnixSeconds: fixture.context.phaseStartUnixSeconds
        )
        let host = MosaicRuntimeCoordinatorHostProbe(
            lease: fixture.material.reservationLease,
            finalizedTransaction: fixture.finalizedTransaction
        )

        let concurrentSuspension = ExplicitReleaseGate()
        await concurrentSuspension.arm()
        let concurrentBridge = try makeBridge(
            fixture: fixture,
            routeFactory: routeFactory,
            permitProbe: permitProbe,
            authority: authority,
            awaitAnonymousPublicationPermit: { _ in
                await concurrentSuspension.suspendIfArmed()
            }
        )
        let concurrentExecution = concurrentBridge.makeExecutionDependencies(
            transactionHost: host,
            previousOutputSource: fixture.previousOutputSource,
            makeLocalContributionMaterial: { _, _ in fixture.material }
        )
        _ = try await concurrentExecution.makeLocalContributionMaterial(
            fixture.eligibility,
            fixture.material.reservationLease
        )
        try await concurrentExecution.publishPlayerCommit(
            fixture.reservationValidation
        )
        let firstPublication = Task {
            try await concurrentExecution.publishAnonymousComponents(
                fixture.componentValidation
            )
        }
        await concurrentSuspension.waitUntilSuspended()
        #expect(
            await concurrentBridge.state
                == .publishing(.anonymousComponents)
        )
        await #expect(throws: Bridge.Failure.concurrentOperation) {
            try await concurrentExecution.publishPreSignAcknowledgement(
                fixture.transcriptInclusion
            )
        }
        await concurrentSuspension.waitUntilCancellationRequested()
        #expect(
            await concurrentBridge.state
                == .draining(.concurrentOperation)
        )
        await concurrentBridge.requestStop()
        await concurrentSuspension.resume()
        await #expect(throws: Bridge.Failure.concurrentOperation) {
            try await firstPublication.value
        }
        #expect(
            await concurrentBridge.waitForTermination()
                == .terminal(.concurrentOperation)
        )
    }

    @Test(
        "Drain stopped relay publication before terminal state",
        .timeLimit(.minutes(5))
    )
    func drainStoppedPublication() async throws {
        let fixture = try await Self.sharedFixtureTask.value
        let routeFactory = RouteFactory(endpoints: selectedEndpoints)
        let permitProbe = PermitProbe()
        let authority = PublicationAuthorityProbe(
            phaseStartUnixSeconds: fixture.context.phaseStartUnixSeconds
        )
        let host = MosaicRuntimeCoordinatorHostProbe(
            lease: fixture.material.reservationLease,
            finalizedTransaction: fixture.finalizedTransaction
        )
        let stopSuspension = ExplicitReleaseGate()
        await stopSuspension.arm()
        let stoppedBridge = try makeBridge(
            fixture: fixture,
            routeFactory: routeFactory,
            permitProbe: permitProbe,
            authority: authority,
            awaitAnonymousPublicationPermit: { _ in
                await stopSuspension.suspendIfArmed()
            }
        )
        let stoppedExecution = stoppedBridge.makeExecutionDependencies(
            transactionHost: host,
            previousOutputSource: fixture.previousOutputSource,
            makeLocalContributionMaterial: { _, _ in fixture.material }
        )
        _ = try await stoppedExecution.makeLocalContributionMaterial(
            fixture.eligibility,
            fixture.material.reservationLease
        )
        try await stoppedExecution.publishPlayerCommit(
            fixture.reservationValidation
        )
        let stoppedPublication = Task {
            try await stoppedExecution.publishAnonymousComponents(
                fixture.componentValidation
            )
        }
        await stopSuspension.waitUntilSuspended()
        #expect(
            await stoppedBridge.state
                == .publishing(.anonymousComponents)
        )
        await stoppedBridge.requestStop()
        await stopSuspension.waitUntilCancellationRequested()
        #expect(await stoppedBridge.state == .draining(.cancelled))
        await stopSuspension.resume()
        await #expect(throws: Bridge.Failure.cancelled) {
            try await stoppedPublication.value
        }
        #expect(
            await stoppedBridge.waitForTermination()
                == .terminal(.cancelled)
        )
        await #expect(throws: Bridge.Failure.inputAfterTermination) {
            try await stoppedExecution.publishAnonymousComponents(
                fixture.componentValidation
            )
        }
    }

    @Test(
        "Drain stopped material construction without cancelling wallet work",
        .timeLimit(.minutes(5))
    )
    func drainStoppedMaterialConstruction() async throws {
        let fixture = try await Self.sharedFixtureTask.value
        let routeFactory = RouteFactory(endpoints: selectedEndpoints)
        let permitProbe = PermitProbe()
        let authority = PublicationAuthorityProbe(
            phaseStartUnixSeconds: fixture.context.phaseStartUnixSeconds
        )
        let host = MosaicRuntimeCoordinatorHostProbe(
            lease: fixture.material.reservationLease,
            finalizedTransaction: fixture.finalizedTransaction
        )
        let materialGate = ExplicitReleaseGate()
        await materialGate.arm()
        let materialTaskWasCancelled = Mutex(false)
        let bridge = try makeBridge(
            fixture: fixture,
            routeFactory: routeFactory,
            permitProbe: permitProbe,
            authority: authority
        )
        let execution = bridge.makeExecutionDependencies(
            transactionHost: host,
            previousOutputSource: fixture.previousOutputSource,
            makeLocalContributionMaterial: { _, _ in
                await materialGate.suspendIfArmed()
                materialTaskWasCancelled.withLock {
                    $0 = Task.isCancelled
                }
                return fixture.material
            }
        )
        let materialTask = Task {
            try await execution.makeLocalContributionMaterial(
                fixture.eligibility,
                fixture.material.reservationLease
            )
        }
        await materialGate.waitUntilSuspended()
        await bridge.requestStop()
        #expect(await bridge.state == .draining(.cancelled))
        await materialGate.resume()
        await #expect(throws: Bridge.Failure.cancelled) {
            try await materialTask.value
        }
        #expect(!materialTaskWasCancelled.withLock { $0 })
        #expect(
            await bridge.waitForTermination() == .terminal(.cancelled)
        )
        #expect(await routeFactory.controlRequestCounts.isEmpty)
        #expect(await routeFactory.anonymousRequestCounts.isEmpty)
        #expect(await permitProbe.requests.isEmpty)
    }

    @Test(
        "Drain directly cancelled relay publication before terminal state",
        .timeLimit(.minutes(5))
    )
    func drainCancelledPublication() async throws {
        let fixture = try await Self.sharedFixtureTask.value
        let routeFactory = RouteFactory(endpoints: selectedEndpoints)
        let permitProbe = PermitProbe()
        let authority = PublicationAuthorityProbe(
            phaseStartUnixSeconds: fixture.context.phaseStartUnixSeconds
        )
        let host = MosaicRuntimeCoordinatorHostProbe(
            lease: fixture.material.reservationLease,
            finalizedTransaction: fixture.finalizedTransaction
        )
        let publicationGate = ExplicitReleaseGate()
        await publicationGate.arm()
        let bridge = try makeBridge(
            fixture: fixture,
            routeFactory: routeFactory,
            permitProbe: permitProbe,
            authority: authority,
            awaitAnonymousPublicationPermit: { _ in
                await publicationGate.suspendIfArmed()
            }
        )
        let execution = bridge.makeExecutionDependencies(
            transactionHost: host,
            previousOutputSource: fixture.previousOutputSource,
            makeLocalContributionMaterial: { _, _ in fixture.material }
        )
        _ = try await execution.makeLocalContributionMaterial(
            fixture.eligibility,
            fixture.material.reservationLease
        )
        try await execution.publishPlayerCommit(
            fixture.reservationValidation
        )
        let publicationTask = Task {
            try await execution.publishAnonymousComponents(
                fixture.componentValidation
            )
        }
        await publicationGate.waitUntilSuspended()
        publicationTask.cancel()
        await publicationGate.waitUntilCancellationRequested()
        #expect(
            await bridge.state == .publishing(.anonymousComponents)
        )
        await publicationGate.resume()
        await #expect(throws: Bridge.Failure.cancelled) {
            try await publicationTask.value
        }
        #expect(
            await bridge.waitForTermination() == .terminal(.cancelled)
        )
        await bridge.requestStop()
        #expect(await bridge.state == .terminal(.cancelled))
    }

    @Test(
        "Terminalize concurrent and cancelled material binding without reuse",
        .timeLimit(.minutes(5))
    )
    func terminalizeConcurrentAndCancelledBinding() async throws {
        let fixture = try await Self.sharedFixtureTask.value
        let routeFactory = RouteFactory(endpoints: selectedEndpoints)
        let permitProbe = PermitProbe()
        let authority = PublicationAuthorityProbe(
            phaseStartUnixSeconds: fixture.context.phaseStartUnixSeconds
        )
        let host = MosaicRuntimeCoordinatorHostProbe(
            lease: fixture.material.reservationLease,
            finalizedTransaction: fixture.finalizedTransaction
        )
        let suspension = MosaicRuntimeCoordinatorSuspensionProbe()
        await suspension.arm()
        let callCount = Mutex(0)
        let bridge = try makeBridge(
            fixture: fixture,
            routeFactory: routeFactory,
            permitProbe: permitProbe,
            authority: authority
        )
        let execution = bridge.makeExecutionDependencies(
            transactionHost: host,
            previousOutputSource: fixture.previousOutputSource,
            makeLocalContributionMaterial: { _, _ in
                callCount.withLock { $0 += 1 }
                await suspension.suspendIfArmed()
                return fixture.material
            }
        )
        let first = Task {
            try await execution.makeLocalContributionMaterial(
                fixture.eligibility,
                fixture.material.reservationLease
            )
        }
        await suspension.waitUntilSuspended()
        await #expect(throws: Bridge.Failure.concurrentOperation) {
            try await execution.makeLocalContributionMaterial(
                fixture.eligibility,
                fixture.material.reservationLease
            )
        }
        #expect(
            await bridge.state == .draining(.concurrentOperation)
        )
        await suspension.resume()
        await #expect(throws: Bridge.Failure.concurrentOperation) {
            try await first.value
        }
        #expect(callCount.withLock { $0 } == 1)
        #expect(await bridge.state == .terminal(.concurrentOperation))
        await #expect(throws: Bridge.Failure.inputAfterTermination) {
            try await execution.publishPlayerCommit(
                fixture.reservationValidation
            )
        }

        let cancellationSuspension = MosaicRuntimeCoordinatorSuspensionProbe()
        await cancellationSuspension.arm()
        let cancelledBridge = try makeBridge(
            fixture: fixture,
            routeFactory: routeFactory,
            permitProbe: permitProbe,
            authority: authority
        )
        let cancelledExecution = cancelledBridge.makeExecutionDependencies(
            transactionHost: host,
            previousOutputSource: fixture.previousOutputSource,
            makeLocalContributionMaterial: { _, _ in
                await cancellationSuspension.suspendIfArmed()
                return fixture.material
            }
        )
        let cancelled = Task {
            try await cancelledExecution.makeLocalContributionMaterial(
                fixture.eligibility,
                fixture.material.reservationLease
            )
        }
        await cancellationSuspension.waitUntilSuspended()
        cancelled.cancel()
        #expect(await cancelledBridge.state == .preparingMaterial)
        await cancellationSuspension.resume()
        await #expect(throws: Bridge.Failure.cancelled) {
            try await cancelled.value
        }
        #expect(await cancelledBridge.state == .terminal(.cancelled))
        #expect(await routeFactory.controlRequestCounts.isEmpty)
        #expect(await routeFactory.anonymousRequestCounts.isEmpty)
        #expect(await permitProbe.requests.isEmpty)
    }

    private static func makeSharedFixture() async throws -> SharedFixture {
        let prepared = try await ExecutionFixture.prepare()
        let admission = prepared.admission
        let manifest = admission.manifest
        let bootstrap = Alpha.PostManifestRuntimeDriver.Bootstrap(
            validatedAttempt: Fixture.makeValidatedAttempt(
                election: admission.election
            ),
            attemptIdentifier: admission.attemptIdentifier,
            generationIdentifier: admission.generationIdentifier,
            materialIdentifier: admission.materialIdentifier,
            localControlIdentity: admission.localControlIdentity,
            proposalValidation: admission.proposalValidation
        )
        let conductorBootstrap = Alpha.PostManifestRuntimeDriver.Bootstrap(
            validatedAttempt: Fixture.makeValidatedAttempt(
                election: admission.election
            ),
            attemptIdentifier: admission.attemptIdentifier,
            generationIdentifier: admission.generationIdentifier,
            materialIdentifier: admission.materialIdentifier,
            localControlIdentity: manifest.core.roster.conductor,
            proposalValidation: admission.proposalValidation
        )
        let context = try ControlBridge.Context(
            validating: manifest,
            against: bootstrap
        )
        let localMaterial = prepared.localMaterial
        let eligibility = Coordinator.ReservationEligibility(
            context: prepared.session.context,
            manifest: manifest
        )
        let reservationValidation = try RuntimeSession
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
        let componentTokens = prepared.localAuthorizationValidation
            .componentAuthorizationTokens
        let componentPublications = try localMaterial.slots.map { slot in
            Coordinator.LocalAnonymousComponentPublication(
                slot: slot.slot,
                recipientEventIdentity: slot.recipientEventIdentity,
                payload: try .init(
                    roundIdentifier: manifest.core.roundIdentifier,
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

        let controlScalar = try #require(
            MosaicMainnetAlphaFixtures.scalarByte(
                for: admission.localControlIdentity
            )
        )
        let controlSigningKey = try signingKey(controlScalar)
        let controlEventSigningKey = try signingKey(100)
        var recipientKeys: [
            Attempt.ControlIdentity: OpalCrypto.Secp256k1.SigningKey
        ] = [:]
        let controlRecipients = try manifest.core.roster.controlIdentities
            .enumerated().map { index, identity in
                let key = try signingKey(UInt8(30 + index))
                recipientKeys[identity] = key
                return ControlBridge.Recipient(
                    controlIdentity: identity,
                    eventVerificationKey: key.bip340VerificationKey
                )
            }
        let localRecipientKey = try #require(
            recipientKeys[admission.localControlIdentity]
        )
        let endpoints = selectedEndpoints
        let relaySelection = try Alpha
            .PostManifestRelaySelectionValidation(
                manifestRelaySetDigest: manifest.core.relaySetDigest,
                endpoints: endpoints,
                using: ExactRelaySelectionValidator(
                    expectedDigest: manifest.core.relaySetDigest,
                    expectedEndpoints: Set(endpoints)
                )
            )
        let codingLimits = try Nostr.RelayMessageCodingLimits(
            maximumFrameByteCount:
                Alpha.nip59MaximumPublicationFrameByteCount,
            maximumFiltersPerRequest: 1,
            maximumValuesPerFilter: 1,
            maximumMessageStringByteCount: 256,
            event: (try Transport.codingLimits).event
        )
        let foreignMaterial = try #require(
            prepared.materialized.materials.first {
                $0.key != localMaterial.contributor
            }?.value
        )
        return .init(
            bootstrap: bootstrap,
            conductorBootstrap: conductorBootstrap,
            manifest: manifest,
            context: context,
            eligibility: eligibility,
            material: localMaterial,
            foreignMaterial: foreignMaterial,
            reservationValidation: reservationValidation,
            componentValidation: componentValidation,
            transcriptInclusion: transcriptInclusion,
            signatureValidation: signatureValidation,
            previousOutputSource: prepared.previousOutputSource,
            finalizedTransaction: prepared.localFinalizedTransaction,
            controlSigningKey: controlSigningKey,
            controlEventSigningKey: controlEventSigningKey,
            controlRecipients: controlRecipients,
            localControlRecipientCapability: .init(
                channel: .control,
                signingKey: localRecipientKey
            ),
            relaySelection: relaySelection,
            codingLimits: codingLimits
        )
    }

    private func makeBridge(
        fixture: SharedFixture,
        routeFactory: RouteFactory,
        permitProbe: PermitProbe,
        authority: PublicationAuthorityProbe,
        bootstrap: Alpha.PostManifestRuntimeDriver.Bootstrap? = nil,
        controlEventSigningKey: OpalCrypto.Secp256k1.SigningKey? = nil,
        controlRecipients: [ControlBridge.Recipient]? = nil,
        localControlRecipientCapability: Transport.RecipientCapability? = nil,
        maximumPendingRelayOutputCount: Int = 4,
        makeExpiryUnixSeconds: (@Sendable (
            Bridge.Publication
        ) throws -> UInt64)? = nil,
        provideControlRoutes: ControlPublisher.RouteProvider? = nil,
        provideAnonymousRoutes: AnonymousPublisher.RouteProvider? = nil,
        awaitAnonymousPublicationPermit:
            AnonymousPublisher.PublicationPermitProvider? = nil
    ) throws -> Bridge {
        try .init(
            bootstrap: bootstrap ?? fixture.bootstrap,
            manifest: fixture.manifest,
            controlSigningKey: fixture.controlSigningKey,
            controlEventSigningKey:
                controlEventSigningKey ?? fixture.controlEventSigningKey,
            controlRecipients: controlRecipients ?? fixture.controlRecipients,
            localControlRecipientCapability:
                localControlRecipientCapability
                ?? fixture.localControlRecipientCapability,
            relaySelection: fixture.relaySelection,
            codingLimits: fixture.codingLimits,
            maximumPendingRelayOutputCount:
                maximumPendingRelayOutputCount,
            dependencies: .init(
                makeExpiryUnixSeconds:
                    makeExpiryUnixSeconds ?? authority.expiry,
                makeControlLayerTimestamps: authority.controlTimestamps,
                makeAnonymousLayerTimestamps: authority.anonymousTimestamps,
                makeControlSignatureAuxiliaryRandomness: {
                    try .init(
                        rawRepresentation: Data(
                            repeating: 0xA5,
                            count: 32
                        )
                    )
                },
                provideControlRoutes: provideControlRoutes ?? { requests in
                    await routeFactory.controlRoutes(for: requests)
                },
                provideAnonymousRoutes: provideAnonymousRoutes ?? { requests in
                    await routeFactory.anonymousRoutes(for: requests)
                },
                awaitAnonymousPublicationPermit:
                    awaitAnonymousPublicationPermit ?? { request in
                        await permitProbe.permit(request)
                    }
            )
        )
    }

    private func assertExpiryFailure(
        for publication: Bridge.Publication
    ) async throws {
        let fixture = try await Self.sharedFixtureTask.value
        let routeFactory = RouteFactory(endpoints: selectedEndpoints)
        let permitProbe = PermitProbe()
        let authority = PublicationAuthorityProbe(
            phaseStartUnixSeconds: fixture.context.phaseStartUnixSeconds
        )
        let bridge = try makeBridge(
            fixture: fixture,
            routeFactory: routeFactory,
            permitProbe: permitProbe,
            authority: authority,
            makeExpiryUnixSeconds: { requestedPublication in
                guard requestedPublication != publication else {
                    throw ProbeFailure.injected
                }
                return Self.expiryUnixSeconds
            }
        )
        let host = MosaicRuntimeCoordinatorHostProbe(
            lease: fixture.material.reservationLease,
            finalizedTransaction: fixture.finalizedTransaction
        )
        let execution = bridge.makeExecutionDependencies(
            transactionHost: host,
            previousOutputSource: fixture.previousOutputSource,
            makeLocalContributionMaterial: { _, _ in fixture.material }
        )
        _ = try await execution.makeLocalContributionMaterial(
            fixture.eligibility,
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
                fixture.reservationValidation
            )
        case .preSignAcknowledgement:
            try await execution.publishPlayerCommit(
                fixture.reservationValidation
            )
            try await execution.publishAnonymousComponents(
                fixture.componentValidation
            )
        case .localBCHSignatures:
            try await execution.publishPlayerCommit(
                fixture.reservationValidation
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
                fixture.reservationValidation
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

    private static var selectedEndpoints: [Tracker.Endpoint] {
        (1 ... Alpha.relayCount).map {
            .init(validatedIdentifier: "relay-\($0)")
        }
    }

    private var selectedEndpoints: [Tracker.Endpoint] {
        Self.selectedEndpoints
    }

    private static func signingKey(
        _ scalar: UInt8
    ) throws -> OpalCrypto.Secp256k1.SigningKey {
        try .init(rawRepresentation: scalarBytes(Int(scalar)))
    }

    private func signingKey(
        _ scalar: UInt8
    ) throws -> OpalCrypto.Secp256k1.SigningKey {
        try Self.signingKey(scalar)
    }

    private static func scalarBytes(_ scalar: Int) -> Data {
        precondition(scalar > 0)
        var value = UInt32(scalar).bigEndian
        var result = Data(repeating: 0, count: 28)
        withUnsafeBytes(of: &value) { result.append(contentsOf: $0) }
        return result
    }
}

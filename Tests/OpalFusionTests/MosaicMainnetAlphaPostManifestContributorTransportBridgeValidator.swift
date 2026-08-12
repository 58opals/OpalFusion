// MosaicMainnetAlphaPostManifestContributorTransportBridgeValidator.swift

import Foundation
import OpalCrypto
import Synchronization
import Testing
@testable import OpalFusion

@Suite("Mosaic mainnet-alpha contributor transport binding")
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
    static let expiryUnixSeconds: UInt64 = 1_800_000_200

    private enum ProbeFailure: Error {
        case injected
    }

    private struct AcceptReservationPublicationValidator:
        RuntimeSession.ReservationPublicationValidating
    {
        func validateReservationPublication(
            _: RuntimeSession.ReservationPublicationRequest
        ) throws {}
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

    struct SharedFixture: Sendable {
        let bootstrap: Alpha.PostManifestRuntimeDriver.Bootstrap
        let conductorBootstrap: Alpha.PostManifestRuntimeDriver.Bootstrap
        let manifest: Alpha.RoundManifest
        let context: ControlBridge.Context
        let eligibility: Coordinator.ReservationEligibility
        let reservationLease: OpalFusion.Host.MosaicReservationLease
        let reservationValidation:
            RuntimeSession.ReservationPublicationValidation
        let previousOutputSource: ExecutionFixture.PreviousOutputSource
        let finalizedTransaction: OpalFusion.Host.FinalizedTransaction
        let controlSigningKey: OpalCrypto.Secp256k1.SigningKey
        let controlEventSigningKey: OpalCrypto.Secp256k1.SigningKey
        let controlRecipients: [ControlBridge.Recipient]
        let localControlRecipientCapability: Transport.RecipientCapability
        let relaySelection: Alpha.PostManifestRelaySelectionValidation
        let codingLimits: Nostr.RelayMessageCodingLimits
    }

    final class PublicationAuthorityProbe: Sendable {
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

    actor PermitProbe {
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
    actor ExplicitReleaseGate {
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

    actor RouteFactory {
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

    actor ImmediateAcknowledgementConnection:
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
        try makeSharedFixture()
    }

    @Test("Bind inbound control routes to the exact bootstrap")
    func bindInboundControlRoutes() async throws {
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
        await bridge.requestStop()
        await bridge.requestStop()
        #expect(await bridge.waitForTermination() == .terminal(.cancelled))
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
            lease: fixture.reservationLease,
            finalizedTransaction: fixture.finalizedTransaction
        )
        let earlyExecution = earlyBridge.makeExecutionDependencies(
            transactionHost: host,
            previousOutputSource: fixture.previousOutputSource,
            makeLocalContributionMaterial: { _, _ in
                throw ProbeFailure.injected
            }
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
                    throw ProbeFailure.injected
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
                    fixture.reservationLease
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
                fixture.reservationLease
            )
        }
        #expect(
            await materialFailureBridge.state
                == .terminal(.materialConstructionFailed)
        )
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
            lease: fixture.reservationLease,
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
                throw ProbeFailure.injected
            }
        )
        let materialTask = Task {
            try await execution.makeLocalContributionMaterial(
                fixture.eligibility,
                fixture.reservationLease
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
            lease: fixture.reservationLease,
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
                throw ProbeFailure.injected
            }
        )
        let first = Task {
            try await execution.makeLocalContributionMaterial(
                fixture.eligibility,
                fixture.reservationLease
            )
        }
        await suspension.waitUntilSuspended()
        await #expect(throws: Bridge.Failure.concurrentOperation) {
            try await execution.makeLocalContributionMaterial(
                fixture.eligibility,
                fixture.reservationLease
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
                throw ProbeFailure.injected
            }
        )
        let cancelled = Task {
            try await cancelledExecution.makeLocalContributionMaterial(
                fixture.eligibility,
                fixture.reservationLease
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

    private static func makeSharedFixture() throws -> SharedFixture {
        let admission = try Fixture.makeHarness(
            localRole: .contributor,
            verificationKey:
                MosaicMainnetAlphaFixtures.rsaVerificationKey(),
            bchSignatureVerificationKey:
                MosaicMainnetAlphaFixtures
                    .bchSignatureRSAVerificationKey()
        )
        let session = try RuntimeSession(
            validatedAttempt: Fixture.makeValidatedAttempt(
                election: admission.election
            ),
            attemptIdentifier: admission.attemptIdentifier,
            generationIdentifier: admission.generationIdentifier,
            materialIdentifier: admission.materialIdentifier,
            localControlIdentity: admission.localControlIdentity,
            proposalValidation: admission.proposalValidation
        )
        let reservationLease = try makeReservationLease()
        let reservationValidation = try RuntimeSession
            .ReservationPublicationValidation(
                validating: .init(
                    attemptIdentifier: admission.attemptIdentifier,
                    generationIdentifier: admission.generationIdentifier,
                    materialIdentifier: admission.materialIdentifier,
                    contributor: admission.localControlIdentity,
                    manifest: admission.manifest,
                    reservationLease: reservationLease,
                    playerCommit: try Alpha.PlayerCommit(
                        roundIdentifier:
                            admission.manifest.core.roundIdentifier,
                        contributor: admission.localControlIdentity,
                        groupedCommitment:
                            MosaicOpalV0WireContractValidator
                                .makeMainnetGroupedCommitment(),
                        componentAuthorizationRequests:
                            MosaicMainnetAlphaFixtures
                                .makeAuthorizationRequests(),
                        bchSignatureAuthorizationRequests:
                            MosaicMainnetAlphaFixtures
                                .makeAuthorizationRequests(byteOffset: 0x40)
                    )
                ),
                using: AcceptReservationPublicationValidator()
            )
        return try makeSharedFixture(
            admission: admission,
            runtimeContext: session.context,
            reservationLease: reservationLease,
            reservationValidation: reservationValidation,
            previousOutputSource: .init(inputsByOutpoint: [:]),
            finalizedTransaction: .init(signedFusionTransactionBytes: [])
        )
    }

    static func makeSharedFixture(
        admission: Fixture.Harness,
        runtimeContext: RuntimeSession.Context,
        reservationLease: OpalFusion.Host.MosaicReservationLease,
        reservationValidation: RuntimeSession.ReservationPublicationValidation,
        previousOutputSource: ExecutionFixture.PreviousOutputSource,
        finalizedTransaction: OpalFusion.Host.FinalizedTransaction
    ) throws -> SharedFixture {
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
        let eligibility = Coordinator.ReservationEligibility(
            context: runtimeContext,
            manifest: manifest
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
        return .init(
            bootstrap: bootstrap,
            conductorBootstrap: conductorBootstrap,
            manifest: manifest,
            context: context,
            eligibility: eligibility,
            reservationLease: reservationLease,
            reservationValidation: reservationValidation,
            previousOutputSource: previousOutputSource,
            finalizedTransaction: finalizedTransaction,
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

    private static func makeReservationLease() throws
        -> OpalFusion.Host.MosaicReservationLease {
        try .init(
            reference: .init(
                identifier: UUID(
                    uuid: (
                        0, 0, 0, 0, 0, 0, 0, 0,
                        0, 0, 0, 0, 0, 0, 0, 65
                    )
                ),
                generation: 1
            ),
            expiresAt: Date(timeIntervalSince1970: 1_900_000_000),
            participantReservation: .init(
                inputs: [
                    .init(
                        outpointTransactionHashBytes:
                            [UInt8](repeating: 0x51, count: 32),
                        outpointIndex: 0,
                        amountSatoshis: 100_000,
                        lockingScriptBytes: [0x51]
                    ),
                ],
                outputs: [
                    .init(
                        lockingScriptBytes: [0x51],
                        amountSatoshis: 99_000
                    ),
                ]
            )
        )
    }

    func makeBridge(
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

    static var selectedEndpoints: [Tracker.Endpoint] {
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

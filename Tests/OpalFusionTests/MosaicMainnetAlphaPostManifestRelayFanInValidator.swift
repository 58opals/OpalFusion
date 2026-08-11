// MosaicMainnetAlphaPostManifestRelayFanInValidator.swift

import Foundation
import OpalCrypto
import Testing
@testable import OpalFusion

@Suite("Mosaic mainnet-alpha post-manifest relay fan-in")
struct MosaicMainnetAlphaPostManifestRelayFanInValidator {
    typealias Alpha = OpalFusion.Mosaic.OpalMainnetAlpha
    typealias FanIn = Alpha.PostManifestRelayFanIn
    typealias Fixture = MosaicMainnetAlphaAdmissionLedgerFixtures
    typealias Ingress = Alpha.PostManifestTransportIngress
    typealias Nostr = OpalFusion.Mosaic.NostrNamespace
    typealias Tracker = OpalFusion.Mosaic.RelayPublicationTracker
    typealias Transport = Alpha.PostManifestNIP59Transport

    private struct ExactRelaySelectionValidator:
        Alpha.PostManifestRelaySelectionValidating
    {
        let digest: [UInt8]
        let endpoints: Set<Tracker.Endpoint>

        func validateRelaySelection(
            manifestRelaySetDigest: [UInt8],
            endpoints: [Tracker.Endpoint]
        ) throws {
            guard manifestRelaySetDigest == digest,
                  Set(endpoints) == self.endpoints else {
                throw ProbeFailure.unexpectedInvocation
            }
        }
    }

    private struct RejectingPreviousOutputSource:
        OpalFusion.Host.MosaicPreviousOutputSource {
        func resolvePreviousOutputs(
            for _: [OpalFusion.Host.MosaicPreviousOutputRequest]
        ) async throws -> [OpalFusion.Host.MosaicPreviousOutput] {
            throw ProbeFailure.unexpectedInvocation
        }
    }

    private actor RejectingCompleteTransactionHost:
        OpalFusion.Host.MosaicCompleteTransactionHost {
        func reserveMosaicContribution(
            for _: OpalFusion.Host.MosaicReservationRequest
        ) async throws -> OpalFusion.Host.MosaicReservationLease {
            throw ProbeFailure.unexpectedInvocation
        }

        func finalizeMosaicTransaction(
            for _: OpalFusion.Host.MosaicTransactionSigningRequest
        ) async throws -> OpalFusion.Host.FinalizedTransaction {
            throw ProbeFailure.unexpectedInvocation
        }

        func releaseMosaicReservation(
            _: OpalFusion.Host.MosaicReservationReference
        ) async throws {
            throw ProbeFailure.unexpectedInvocation
        }

        func commitMosaicReservation(
            _: OpalFusion.Host.MosaicReservationReference,
            finalizedTransaction _: OpalFusion.Host.FinalizedTransaction
        ) async throws {
            throw ProbeFailure.unexpectedInvocation
        }

        func commitMosaicReservation(
            _: OpalFusion.Host.MosaicReservationReference,
            completeTransaction _: OpalFusion.Host.MosaicCompleteTransaction
        ) async throws {
            throw ProbeFailure.unexpectedInvocation
        }
    }

    private final class SubmissionProbe: @unchecked Sendable {
        struct Observation: Sendable, Equatable {
            let identifier: OpalCrypto.Signature.Digest
            let decision: Ingress.Decision
        }

        private let lock = NSLock()
        private var waiters: [
            (
                count: Int,
                continuation: CheckedContinuation<Void, Never>
            )
        ] = []
        private var storedObservations: [Observation] = []

        var observations: [Observation] {
            withLock { storedObservations }
        }

        func record(
            _ identifier: OpalCrypto.Signature.Digest,
            _ decision: Ingress.Decision
        ) {
            let satisfied = withLock {
                storedObservations.append(
                    .init(identifier: identifier, decision: decision)
                )
                let satisfied = waiters.filter {
                    storedObservations.count >= $0.count
                }
                waiters.removeAll {
                    storedObservations.count >= $0.count
                }
                return satisfied
            }
            for waiter in satisfied {
                waiter.continuation.resume()
            }
        }

        func waitUntilCount(_ count: Int) async {
            await withCheckedContinuation { continuation in
                let shouldResume = withLock {
                    guard storedObservations.count < count else {
                        return true
                    }
                    waiters.append((count, continuation))
                    return false
                }
                if shouldResume {
                    continuation.resume()
                }
            }
        }

        private func withLock<Result>(
            _ operation: () throws -> Result
        ) rethrows -> Result {
            lock.lock()
            defer { lock.unlock() }
            return try operation()
        }
    }

    private actor CompletionProbe {
        private(set) var isCompleted = false

        func markCompleted() {
            isCompleted = true
        }
    }

    private final class BlockingClockGate: @unchecked Sendable {
        private let condition = NSCondition()
        private var blockedWaiter: CheckedContinuation<Void, Never>?
        private var isBlocked = false
        private var isReleased = false

        func block() {
            condition.lock()
            guard !isBlocked else {
                condition.unlock()
                return
            }
            isBlocked = true
            let waiter = blockedWaiter
            blockedWaiter = nil
            condition.unlock()
            waiter?.resume()

            condition.lock()
            while !isReleased {
                condition.wait()
            }
            condition.unlock()
        }

        func waitUntilBlocked() async {
            await withCheckedContinuation { continuation in
                condition.lock()
                guard !isBlocked else {
                    condition.unlock()
                    continuation.resume()
                    return
                }
                blockedWaiter = continuation
                condition.unlock()
            }
        }

        func resume() {
            condition.lock()
            isReleased = true
            condition.broadcast()
            condition.unlock()
        }
    }

    private final class CancellationGate: @unchecked Sendable {
        private let lock = NSLock()
        private var cancellation: CheckedContinuation<Void, any Error>?
        private var startWaiter: CheckedContinuation<Void, Never>?
        private var didStart = false
        private var isCancelled = false

        func suspendUntilCancelled() async throws {
            try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuation in
                    let state = withLock { () -> (
                        CheckedContinuation<Void, Never>?,
                        Bool
                    ) in
                        didStart = true
                        let waiter = startWaiter
                        startWaiter = nil
                        guard !isCancelled else {
                            return (waiter, true)
                        }
                        cancellation = continuation
                        return (waiter, false)
                    }
                    state.0?.resume()
                    if state.1 {
                        continuation.resume(throwing: CancellationError())
                    }
                }
            } onCancel: {
                cancel()
            }
        }

        func waitUntilStarted() async {
            await withCheckedContinuation { continuation in
                let shouldResume = withLock {
                    guard !didStart else { return true }
                    startWaiter = continuation
                    return false
                }
                if shouldResume {
                    continuation.resume()
                }
            }
        }

        func cancel() {
            let continuation: CheckedContinuation<Void, any Error>? = withLock {
                guard !isCancelled else { return nil }
                isCancelled = true
                let continuation = cancellation
                cancellation = nil
                return continuation
            }
            continuation?.resume(throwing: CancellationError())
        }

        private func withLock<Result>(
            _ operation: () throws -> Result
        ) rethrows -> Result {
            lock.lock()
            defer { lock.unlock() }
            return try operation()
        }
    }

    private actor CancellationResponsiveConnection:
        OpalFusion.Mosaic.TorWebSocketConnectioning
    {
        private let cancellationGate = CancellationGate()
        private(set) var closeCount = 0

        func open(
            maximumIncomingMessageByteCount _: Int
        ) async throws -> MessageStream {
            try await cancellationGate.suspendUntilCancelled()
            throw ProbeFailure.unexpectedInvocation
        }

        func send(text _: String) async throws {
            throw ProbeFailure.unexpectedInvocation
        }

        func close() {
            guard closeCount == 0 else { return }
            closeCount = 1
            cancellationGate.cancel()
        }

        func waitUntilOpenSuspends() async {
            await cancellationGate.waitUntilStarted()
        }
    }

    private struct Harness {
        let fanIn: FanIn
        let connections: [ScriptedMosaicTorWebSocketConnection]
        let subscriptions: [
            Tracker.Endpoint: Nostr.SubscriptionIdentifier
        ]
        let recipient: OpalCrypto.Secp256k1.SigningKey
        let submissionProbe: SubmissionProbe
        let ledger: Fixture.Harness
    }

    private struct MultiRecipientHarness {
        let fanIn: FanIn
        let controlConnections: [ScriptedMosaicTorWebSocketConnection]
        let anonymousConnections: [ScriptedMosaicTorWebSocketConnection]
        let controlSubscriptions: [
            Tracker.Endpoint: Nostr.SubscriptionIdentifier
        ]
        let anonymousSubscriptions: [
            Tracker.Endpoint: Nostr.SubscriptionIdentifier
        ]
        let controlRecipient: OpalCrypto.Secp256k1.SigningKey
        let anonymousRecipient: OpalCrypto.Secp256k1.SigningKey
        let submissionProbe: SubmissionProbe
        let ledger: Fixture.Harness
    }

    @Test("Reject mismatched routes subscriptions and limits")
    func rejectInvalidConstruction() async throws {
        let ledger = try Fixture.makeHarness(localRole: .conductor)
        let connections = makeConnections()
        let subscriptions = try makeSubscriptions()

        #expect(
            throws: FanIn.InitializationError.invalidRelayCount(actual: 2)
        ) {
            _ = try makeFanIn(
                ledger: ledger,
                connections: Array(connections.prefix(2)),
                subscriptions: subscriptions
            )
        }
        #expect(throws: FanIn.InitializationError.duplicateConnection) {
            _ = try makeFanIn(
                ledger: ledger,
                connections: [
                    connections[0], connections[1], connections[0],
                ],
                subscriptions: subscriptions
            )
        }
        var duplicateSubscriptions = subscriptions
        duplicateSubscriptions[endpoint(3)] = subscriptions[endpoint(1)]
        #expect(
            throws: FanIn.InitializationError
                .duplicateSubscriptionIdentifier
        ) {
            _ = try makeFanIn(
                ledger: ledger,
                connections: connections,
                subscriptions: duplicateSubscriptions
            )
        }
        #expect(
            throws: FanIn.InitializationError.invalidEventBufferLimit
        ) {
            _ = try makeFanIn(
                ledger: ledger,
                connections: connections,
                subscriptions: subscriptions,
                maximumPendingEventCount: 0
            )
        }
        #expect(
            throws: FanIn.InitializationError
                .relaySelectionManifestMismatch
        ) {
            _ = try makeFanIn(
                ledger: ledger,
                connections: connections,
                subscriptions: subscriptions,
                relaySetDigest: [UInt8](repeating: 0x45, count: 32)
            )
        }
        #expect(
            throws: FanIn.InitializationError.incompatibleCodingLimits
        ) {
            _ = try makeFanIn(
                ledger: ledger,
                connections: connections,
                subscriptions: subscriptions,
                maximumFrameByteCount: 256
            )
        }
        for connection in connections {
            #expect(await connection.openCount == 0)
        }
    }

    @Test(
        "Reject invalid recipient route groups before opening a route",
        .timeLimit(.minutes(1))
    )
    func rejectInvalidRecipientRouteGroups() async throws {
        let ledger = try Fixture.makeHarness(localRole: .conductor)
        let controlConnections = makeConnections()
        let anonymousConnections = makeConnections()
        let controlSubscriptions = try makeSubscriptions(prefix: "control")
        let anonymousSubscriptions = try makeSubscriptions(prefix: "anonymous")
        let controlRecipient = try signingKey(21)
        let anonymousRecipient = try signingKey(22)
        let controlGroup = try recipientRouteGroup(
            attemptBinding: .init(bootstrap: bootstrap(ledger)),
            recipient: controlRecipient,
            channel: .control,
            connections: controlConnections,
            subscriptions: controlSubscriptions
        )
        let anonymousGroup = try recipientRouteGroup(
            attemptBinding: .init(bootstrap: bootstrap(ledger)),
            recipient: anonymousRecipient,
            channel: .anonymous,
            connections: anonymousConnections,
            subscriptions: anonymousSubscriptions
        )

        #expect(
            throws: FanIn.InitializationError
                .invalidRecipientGroupCount(actual: 0)
        ) {
            _ = try makeFanIn(
                ledger: ledger,
                recipientRouteGroups: []
            )
        }
        let duplicateRecipientGroup = try recipientRouteGroup(
            attemptBinding: .init(bootstrap: bootstrap(ledger)),
            recipient: controlRecipient,
            channel: .anonymous,
            connections: anonymousConnections,
            subscriptions: anonymousSubscriptions
        )
        #expect(throws: FanIn.InitializationError.invalidRecipientSet) {
            _ = try makeFanIn(
                ledger: ledger,
                recipientRouteGroups: [
                    controlGroup,
                    duplicateRecipientGroup,
                ]
            )
        }
        let secondControlGroup = try recipientRouteGroup(
            attemptBinding: .init(bootstrap: bootstrap(ledger)),
            recipient: anonymousRecipient,
            channel: .control,
            connections: anonymousConnections,
            subscriptions: anonymousSubscriptions
        )
        #expect(throws: FanIn.InitializationError.invalidRecipientChannels) {
            _ = try makeFanIn(
                ledger: ledger,
                recipientRouteGroups: [controlGroup, secondControlGroup]
            )
        }
        #expect(throws: FanIn.InitializationError.invalidRecipientChannels) {
            _ = try makeFanIn(
                ledger: ledger,
                recipientRouteGroups: [anonymousGroup]
            )
        }
        let maximumGroupCount = 1
            + ledger.manifest.core.roster.contributors.count
                * Alpha.componentCountPerContributor
        #expect(throws: FanIn.InitializationError.invalidRecipientSet) {
            _ = try makeFanIn(
                ledger: ledger,
                recipientRouteGroups: Array(
                    repeating: controlGroup,
                    count: maximumGroupCount
                )
            )
        }
        #expect(
            throws: FanIn.InitializationError.invalidRecipientGroupCount(
                actual: maximumGroupCount + 1
            )
        ) {
            _ = try makeFanIn(
                ledger: ledger,
                recipientRouteGroups: Array(
                    repeating: controlGroup,
                    count: maximumGroupCount + 1
                )
            )
        }
        let contributorLedger = try Fixture.makeHarness(
            localRole: .contributor
        )
        #expect(throws: FanIn.InitializationError.invalidRecipientChannels) {
            _ = try makeFanIn(
                ledger: contributorLedger,
                recipientRouteGroups: [anonymousGroup],
                roleDependencies: contributorDependencies
            )
        }
        let reusedConnectionGroup = try recipientRouteGroup(
            attemptBinding: .init(bootstrap: bootstrap(ledger)),
            recipient: anonymousRecipient,
            channel: .anonymous,
            connections: [
                controlConnections[0],
                anonymousConnections[1],
                anonymousConnections[2],
            ],
            subscriptions: anonymousSubscriptions
        )
        #expect(throws: FanIn.InitializationError.duplicateConnection) {
            _ = try makeFanIn(
                ledger: ledger,
                recipientRouteGroups: [controlGroup, reusedConnectionGroup]
            )
        }
        var reusedSubscriptions = anonymousSubscriptions
        reusedSubscriptions[endpoint(1)] = controlSubscriptions[endpoint(1)]
        let reusedSubscriptionGroup = try recipientRouteGroup(
            attemptBinding: .init(bootstrap: bootstrap(ledger)),
            recipient: anonymousRecipient,
            channel: .anonymous,
            connections: anonymousConnections,
            subscriptions: reusedSubscriptions
        )
        #expect(
            throws: FanIn.InitializationError
                .duplicateSubscriptionIdentifier
        ) {
            _ = try makeFanIn(
                ledger: ledger,
                recipientRouteGroups: [
                    controlGroup,
                    reusedSubscriptionGroup,
                ]
            )
        }

        let currentBootstrap = bootstrap(ledger)
        let foreignBootstrap = Alpha.PostManifestRuntimeDriver.Bootstrap(
            validatedAttempt: currentBootstrap.validatedAttempt,
            attemptIdentifier: .init(validatedBytes: [0xFA]),
            generationIdentifier: currentBootstrap.generationIdentifier,
            materialIdentifier: currentBootstrap.materialIdentifier,
            localControlIdentity: currentBootstrap.localControlIdentity,
            proposalValidation: currentBootstrap.proposalValidation
        )
        let foreignBindingGroup = try recipientRouteGroup(
            attemptBinding: .init(bootstrap: foreignBootstrap),
            recipient: try signingKey(23),
            channel: .control,
            connections: makeConnections(),
            subscriptions: try makeSubscriptions(prefix: "foreign-binding")
        )
        #expect(
            throws: FanIn.InitializationError
                .recipientAttemptBindingMismatch
        ) {
            _ = try makeFanIn(
                ledger: ledger,
                recipientRouteGroups: [foreignBindingGroup]
            )
        }

        let claimedGroup = try recipientRouteGroup(
            attemptBinding: .init(bootstrap: currentBootstrap),
            recipient: try signingKey(24),
            channel: .control,
            connections: makeConnections(),
            subscriptions: try makeSubscriptions(prefix: "claimed-binding")
        )
        _ = try makeFanIn(
            ledger: ledger,
            recipientRouteGroups: [claimedGroup]
        )
        #expect(
            throws: FanIn.InitializationError
                .recipientAttemptBindingMismatch
        ) {
            _ = try makeFanIn(
                ledger: ledger,
                recipientRouteGroups: [claimedGroup]
            )
        }

        for connection in controlConnections + anonymousConnections {
            #expect(await connection.openCount == 0)
        }
    }

    @Test(
        "Start every recipient route group before forwarding into one runtime",
        .timeLimit(.minutes(1))
    )
    func routeMultipleRecipientsThroughOneRuntime() async throws {
        let harness = try makeMultiRecipientHarness()
        let ledger = harness.ledger
        let controlConnections = harness.controlConnections
        let anonymousConnections = harness.anonymousConnections
        let controlSubscriptions = harness.controlSubscriptions
        let anonymousSubscriptions = harness.anonymousSubscriptions
        let controlRecipient = harness.controlRecipient
        let anonymousRecipient = harness.anonymousRecipient
        let probe = harness.submissionProbe
        let fanIn = harness.fanIn
        let controlEvent = try controlGiftWrap(
            manifestRun(ledger).reservation.envelope,
            ledger: ledger,
            recipient: controlRecipient
        )
        let anonymousEvent = try anonymousGiftWrap(
            ledger: ledger,
            recipient: anonymousRecipient
        )
        await anonymousConnections[2].suspendNextSend()

        let starting = Task { try await fanIn.start() }
        await anonymousConnections[2].waitUntilSendSuspends()
        await controlConnections[0].waitUntilSentTextCount(1)
        await controlConnections[0].receive(
            try relayEventFrame(
                subscription: try #require(
                    controlSubscriptions[endpoint(1)]
                ),
                event: controlEvent
            )
        )
        #expect(probe.observations.isEmpty)

        await anonymousConnections[2].resumeSend()
        try await starting.value
        await probe.waitUntilCount(1)
        await anonymousConnections[0].receive(
            try relayEventFrame(
                subscription: try #require(
                    anonymousSubscriptions[endpoint(1)]
                ),
                event: anonymousEvent
            )
        )
        await probe.waitUntilCount(2)

        #expect(
            probe.observations.map(\.identifier)
                == [controlEvent.identifier, anonymousEvent.identifier]
        )
        #expect(probe.observations.map(\.decision) == [.accepted, .accepted])
        #expect(await fanIn.state == .running)
        let limits = try relayLimits(
            subscriptionIdentifiers: Array(controlSubscriptions.values)
                + Array(anonymousSubscriptions.values)
        )
        for (connections, subscriptions, recipient) in [
            (controlConnections, controlSubscriptions, controlRecipient),
            (anonymousConnections, anonymousSubscriptions, anonymousRecipient),
        ] {
            for (index, connection) in connections.enumerated() {
                let identifier = try #require(
                    subscriptions[endpoint(index + 1)]
                )
                #expect(
                    await connection.sentTexts
                        == [try expectedRequestFrame(
                            recipient: recipient,
                            identifier: identifier,
                            limits: limits
                        )]
                )
            }
        }

        await fanIn.stop()
        #expect(await fanIn.waitForTermination() == .stopped)
        for connection in controlConnections + anonymousConnections {
            #expect(await connection.closeCount == 1)
        }
    }

    @Test(
        "Reject a valid event delivered through another recipient route",
        .timeLimit(.minutes(1))
    )
    func rejectCrossRecipientRouteDelivery() async throws {
        let harness = try makeMultiRecipientHarness()
        let event = try anonymousGiftWrap(
            ledger: harness.ledger,
            recipient: harness.anonymousRecipient
        )
        try await harness.fanIn.start()

        await harness.controlConnections[0].receive(
            try relayEventFrame(
                subscription: try #require(
                    harness.controlSubscriptions[endpoint(1)]
                ),
                event: event
            )
        )

        #expect(
            await harness.fanIn.waitForTermination()
                == .failed(.sourceFailed)
        )
        #expect(harness.submissionProbe.observations.isEmpty)
        for connection in harness.controlConnections
            + harness.anonymousConnections {
            #expect(await connection.closeCount == 1)
        }
    }

    @Test(
        "Fail when startup input exceeds the shared event FIFO",
        .timeLimit(.minutes(1))
    )
    func failOnSharedStartupBufferOverflow() async throws {
        let connections = makeConnections()
        await connections[2].suspendNextSend()
        let harness = try makeHarness(
            connections: connections,
            maximumPendingEventCount: 1
        )
        let event = try manifestReservationGiftWrap(harness)
        let identifier = try #require(
            harness.subscriptions[endpoint(1)]
        )

        let starting = Task { try await harness.fanIn.start() }
        await connections[2].waitUntilSendSuspends()
        await connections[0].waitUntilSentTextCount(1)
        await connections[0].receive(
            try relayEventFrame(subscription: identifier, event: event)
        )
        await connections[0].receive(
            try relayEventFrame(subscription: identifier, event: event)
        )
        await connections[0].waitUntilClosed()
        await connections[2].resumeSend()

        await #expect(throws: FanIn.Failure.sourceFailed) {
            try await starting.value
        }
        #expect(harness.submissionProbe.observations.isEmpty)
        for connection in connections {
            #expect(await connection.closeCount == 1)
        }
    }

    @Test(
        "Subscribe every route before forwarding buffered input",
        .timeLimit(.minutes(1))
    )
    func startAllRoutesBeforeForwarding() async throws {
        let connections = makeConnections()
        await connections[2].suspendNextSend()
        let harness = try makeHarness(
            connections: connections,
            maximumPendingEventCount: 2
        )
        let event = try manifestReservationGiftWrap(harness)
        let identifier = try #require(
            harness.subscriptions[endpoint(1)]
        )

        let starting = Task { try await harness.fanIn.start() }
        await connections[2].waitUntilSendSuspends()
        await connections[0].waitUntilSentTextCount(1)
        #expect(await harness.fanIn.state == .starting)
        await connections[0].receive(
            try relayEventFrame(
                subscription: identifier,
                event: event
            )
        )
        await connections[0].receive(
            try relayEventFrame(subscription: identifier, event: event)
        )
        await connections[0].receive(
            textFrame(
                "[\"EOSE\"," + Nostr.EventCodec.encodeString(identifier.value)
                    + "]"
            )
        )
        #expect(harness.submissionProbe.observations.isEmpty)

        await connections[2].resumeSend()
        try await starting.value
        await harness.submissionProbe.waitUntilCount(2)
        #expect(
            harness.submissionProbe.observations
                == [
                    .init(identifier: event.identifier, decision: .accepted),
                    .init(identifier: event.identifier, decision: .accepted),
                ]
        )
        for (index, connection) in connections.enumerated() {
            let identifier = try #require(
                harness.subscriptions[endpoint(index + 1)]
            )
            #expect(
                await connection.sentTexts
                    == [try expectedRequestFrame(
                        recipient: harness.recipient,
                        identifier: identifier,
                        limits: relayLimits(subscriptions: harness.subscriptions)
                    )]
            )
        }

        await harness.fanIn.stop()
        #expect(await harness.fanIn.state == .terminal(.stopped))
        await #expect(throws: FanIn.Failure.alreadyUsed) {
            try await harness.fanIn.start()
        }
    }

    @Test(
        "Cancel a suspended startup and close every route once",
        .timeLimit(.minutes(1))
    )
    func cancelSuspendedStartup() async throws {
        let connections = makeConnections()
        await connections[2].suspendNextOpen()
        let harness = try makeHarness(connections: connections)

        let starting = Task { try await harness.fanIn.start() }
        await connections[2].waitUntilOpenSuspends()
        starting.cancel()

        await #expect(throws: FanIn.Failure.cancelled) {
            try await starting.value
        }
        #expect(await harness.fanIn.state == .terminal(.stopped))
        await #expect(throws: FanIn.Failure.alreadyUsed) {
            try await harness.fanIn.start()
        }
        for connection in connections {
            #expect(await connection.closeCount == 1)
        }
    }

    @Test(
        "Classify a cancellation-responsive route as cancellation",
        .timeLimit(.minutes(1))
    )
    func cancelResponsiveStartup() async throws {
        let ledger = try Fixture.makeHarness(localRole: .conductor)
        let subscriptions = try makeSubscriptions()
        let responsive = CancellationResponsiveConnection()
        let peers = makeConnections()
        let fanIn = try makeFanIn(
            ledger: ledger,
            connections: [responsive, peers[0], peers[1]],
            subscriptions: subscriptions
        )

        let starting = Task { try await fanIn.start() }
        await responsive.waitUntilOpenSuspends()
        starting.cancel()

        await #expect(throws: FanIn.Failure.cancelled) {
            try await starting.value
        }
        #expect(await fanIn.state == .terminal(.stopped))
        #expect(await responsive.closeCount == 1)
        #expect(await peers[0].closeCount == 1)
        #expect(await peers[1].closeCount == 1)
    }

    @Test("Stop before start without opening a route")
    func stopBeforeStart() async throws {
        let harness = try makeHarness()

        await harness.fanIn.stop()

        #expect(await harness.fanIn.state == .terminal(.stopped))
        await #expect(throws: FanIn.Failure.alreadyUsed) {
            try await harness.fanIn.start()
        }
        for connection in harness.connections {
            #expect(await connection.openCount == 0)
            #expect(await connection.closeCount == 1)
        }
    }

    @Test(
        "Wait for suspended ingress startup before cancellation completes",
        .timeLimit(.minutes(1))
    )
    func cancelSuspendedIngressStartup() async throws {
        let suspension = MosaicRuntimeCoordinatorSuspensionProbe()
        await suspension.arm()
        let harness = try makeHarness(beforeDriverStart: {
            await suspension.suspendIfArmed()
        })

        let starting = Task { try await harness.fanIn.start() }
        await suspension.waitUntilSuspended()
        starting.cancel()
        await harness.connections[0].waitUntilClosed()

        let completion = CompletionProbe()
        let termination = Task {
            let result = await harness.fanIn.waitForTermination()
            await completion.markCompleted()
            return result
        }
        #expect(await harness.fanIn.state == .stopping)
        #expect(!(await completion.isCompleted))

        await suspension.resume()
        await #expect(throws: FanIn.Failure.cancelled) {
            try await starting.value
        }
        #expect(await termination.value == .stopped)
        #expect(await harness.fanIn.state == .terminal(.stopped))
        for connection in harness.connections {
            #expect(await connection.closeCount == 1)
        }
    }

    @Test(
        "Close a suspended route as soon as another startup fails",
        .timeLimit(.minutes(1))
    )
    func failFastDuringRouteStartup() async throws {
        let connections = makeConnections()
        await connections[0].suspendNextOpen()
        await connections[0].failNextSend()
        await connections[2].suspendNextOpen()
        await connections[2].suspendNextClose()
        let harness = try makeHarness(connections: connections)

        let starting = Task { try await harness.fanIn.start() }
        await connections[0].waitUntilOpenSuspends()
        await connections[2].waitUntilOpenSuspends()
        await connections[0].resumeOpen()
        await connections[2].waitUntilCloseSuspends()

        starting.cancel()
        let stopping = Task { await harness.fanIn.stop() }
        let completion = CompletionProbe()
        let termination = Task {
            let result = await harness.fanIn.waitForTermination()
            await completion.markCompleted()
            return result
        }
        #expect(await harness.fanIn.state == .stopping)
        #expect(!(await completion.isCompleted))
        await connections[2].resumeClose()

        await #expect(throws: FanIn.Failure.sourceFailed) {
            try await starting.value
        }
        await stopping.value
        #expect(await termination.value == .failed(.sourceFailed))
        #expect(
            await harness.fanIn.state
                == .terminal(.failed(.sourceFailed))
        )
        for connection in connections {
            #expect(await connection.closeCount == 1)
        }
    }

    @Test(
        "Fail all-or-nothing startup when one subscription send fails",
        .timeLimit(.minutes(1))
    )
    func failSubscriptionStartup() async throws {
        let connections = makeConnections()
        await connections[1].failNextSend()
        let harness = try makeHarness(connections: connections)

        await #expect(throws: FanIn.Failure.sourceFailed) {
            try await harness.fanIn.start()
        }
        #expect(
            await harness.fanIn.state
                == .terminal(.failed(.sourceFailed))
        )
        #expect(harness.submissionProbe.observations.isEmpty)
        for connection in connections {
            #expect(await connection.closeCount == 1)
        }
    }

    @Test(
        "Forward every identical relay copy without coalescing",
        .timeLimit(.minutes(1))
    )
    func forwardEveryRelayCopy() async throws {
        let harness = try makeHarness()
        let event = try manifestReservationGiftWrap(harness)
        try await harness.fanIn.start()

        for index in 0 ..< Alpha.relayCount {
            await harness.connections[index].receive(
                try relayEventFrame(
                    subscription: try #require(
                        harness.subscriptions[endpoint(index + 1)]
                    ),
                    event: event
                )
            )
        }
        await harness.submissionProbe.waitUntilCount(Alpha.relayCount)

        #expect(
            harness.submissionProbe.observations.map(\.identifier)
                == [event.identifier, event.identifier, event.identifier]
        )
        #expect(
            harness.submissionProbe.observations.map(\.decision)
                == [.accepted, .accepted, .accepted]
        )
        #expect(await harness.fanIn.state == .running)

        await harness.fanIn.stop()
    }

    @Test(
        "Ignore EOSE and NOTICE without suppressing later EVENT input",
        .timeLimit(.minutes(1))
    )
    func ignoreNonterminalRelayMessages() async throws {
        let harness = try makeHarness()
        let identifier = try #require(
            harness.subscriptions[endpoint(1)]
        )
        let event = try manifestReservationGiftWrap(harness)
        try await harness.fanIn.start()

        await harness.connections[0].receive(
            textFrame(
                "[\"EOSE\"," + Nostr.EventCodec.encodeString(identifier.value)
                    + "]"
            )
        )
        await harness.connections[0].receive(
            textFrame("[\"NOTICE\",\"stored history complete\"]")
        )
        await harness.connections[0].receive(
            try relayEventFrame(subscription: identifier, event: event)
        )
        await harness.submissionProbe.waitUntilCount(1)

        #expect(await harness.fanIn.state == .running)
        #expect(
            harness.submissionProbe.observations
                == [.init(identifier: event.identifier, decision: .accepted)]
        )
        await harness.fanIn.stop()
    }

    @Test(
        "Fail closed when any selected relay source ends",
        .timeLimit(.minutes(1)),
        arguments: [false, true]
    )
    func failOnAnySourceLoss(throwsFailure: Bool) async throws {
        let harness = try makeHarness()
        try await harness.fanIn.start()

        if throwsFailure {
            await harness.connections[0].failInput()
        } else {
            await harness.connections[0].finishInput()
        }

        #expect(
            await harness.fanIn.waitForTermination()
                == .failed(.sourceFailed)
        )
        #expect(
            await harness.fanIn.state
                == .terminal(.failed(.sourceFailed))
        )
        for connection in harness.connections {
            #expect(await connection.closeCount == 1)
        }
    }

    @Test(
        "Drain accepted FIFO input before source failure",
        .timeLimit(.minutes(1))
    )
    func drainBeforeSourceFailure() async throws {
        let probe = SubmissionProbe()
        let harness = try makeHarness(submissionProbe: probe)
        let event = try manifestReservationGiftWrap(harness)
        let identifier = try #require(
            harness.subscriptions[endpoint(1)]
        )
        try await harness.fanIn.start()

        await harness.connections[0].receive(
            try relayEventFrame(subscription: identifier, event: event)
        )
        await harness.connections[0].receive(
            try relayEventFrame(subscription: identifier, event: event)
        )
        await harness.connections[0].failInput()

        #expect(
            await harness.fanIn.waitForTermination()
                == .failed(.sourceFailed)
        )
        #expect(probe.observations.count == 2)
        #expect(
            probe.observations.map(\.identifier)
                == [event.identifier, event.identifier]
        )
    }

    @Test(
        "Fail closed after draining the bounded aggregate FIFO",
        .timeLimit(.minutes(1))
    )
    func failOnAggregateBufferOverflow() async throws {
        let clockGate = BlockingClockGate()
        let probe = SubmissionProbe()
        let harness = try makeHarness(
            submissionProbe: probe,
            maximumPendingEventCount: 1,
            clockGate: clockGate
        )
        let event = try manifestReservationGiftWrap(harness)
        try await harness.fanIn.start()
        defer { clockGate.resume() }

        await harness.connections[0].receive(
            try relayEventFrame(
                subscription: try #require(
                    harness.subscriptions[endpoint(1)]
                ),
                event: event
            )
        )
        await clockGate.waitUntilBlocked()
        for index in 1 ..< Alpha.relayCount {
            await harness.connections[index].receive(
                try relayEventFrame(
                    subscription: try #require(
                        harness.subscriptions[endpoint(index + 1)]
                    ),
                    event: event
                )
            )
        }
        await harness.connections[0].waitUntilClosed()
        #expect(await harness.fanIn.state == .stopping)

        clockGate.resume()
        #expect(
            await harness.fanIn.waitForTermination()
                == .failed(.sourceFailed)
        )
        #expect(probe.observations.count == 2)
        #expect(
            probe.observations.map(\.decision)
                == [.accepted, .accepted]
        )
        for connection in harness.connections {
            #expect(await connection.closeCount == 1)
        }
    }

    @Test(
        "Explicit stop preserves cancellation precedence",
        .timeLimit(.minutes(1))
    )
    func stopDrainsAndWins() async throws {
        let probe = SubmissionProbe()
        let harness = try makeHarness(submissionProbe: probe)
        let event = try manifestReservationGiftWrap(harness)
        let identifier = try #require(
            harness.subscriptions[endpoint(1)]
        )
        try await harness.fanIn.start()

        await harness.connections[0].receive(
            try relayEventFrame(subscription: identifier, event: event)
        )
        await probe.waitUntilCount(1)
        let stopping = Task { await harness.fanIn.stop() }
        await harness.connections[1].waitUntilClosed()

        await stopping.value
        #expect(probe.observations.count == 1)
        #expect(await harness.fanIn.waitForTermination() == .stopped)
        await harness.connections[1].failInput()
        #expect(await harness.fanIn.state == .terminal(.stopped))
        for connection in harness.connections {
            #expect(await connection.closeCount == 1)
        }
    }

    @Test(
        "Preserve runtime termination while closing every route",
        .timeLimit(.minutes(1))
    )
    func runtimeTerminationWins() async throws {
        let harness = try makeHarness()
        let run = try manifestRun(harness.ledger)
        let identifier = try #require(
            harness.subscriptions[endpoint(1)]
        )
        try await harness.fanIn.start()

        let envelopes = [run.reservation] + run.fragments
        for envelope in envelopes {
            await harness.connections[0].receive(
                try relayEventFrame(
                    subscription: identifier,
                    event: try controlGiftWrap(
                        envelope.envelope,
                        ledger: harness.ledger,
                        recipient: harness.recipient
                    )
                )
            )
        }
        await harness.connections[0].finishInput()

        let runtimeState = Alpha.PostManifestRuntimeDriver.State.conductor(
            .terminal(.failed(.authorizationKeyMismatch))
        )
        #expect(
            await harness.fanIn.waitForTermination()
                == .runtime(runtimeState)
        )
        #expect(await harness.fanIn.state == .terminal(.runtime(runtimeState)))
        for connection in harness.connections {
            #expect(await connection.closeCount == 1)
        }
    }

    private func makeHarness(
        connections: [ScriptedMosaicTorWebSocketConnection]? = nil,
        submissionProbe: SubmissionProbe = .init(),
        maximumPendingEventCount: Int = 8,
        beforeDriverStart: @escaping @Sendable () async -> Void = {},
        clockGate: BlockingClockGate? = nil
    ) throws -> Harness {
        let ledger = try Fixture.makeHarness(localRole: .conductor)
        let connections = connections ?? makeConnections()
        let subscriptions = try makeSubscriptions()
        let recipient = try signingKey(21)
        let fanIn = try makeFanIn(
            ledger: ledger,
            connections: connections,
            subscriptions: subscriptions,
            recipient: recipient,
            submissionProbe: submissionProbe,
            maximumPendingEventCount: maximumPendingEventCount,
            beforeDriverStart: beforeDriverStart,
            clockGate: clockGate
        )
        return .init(
            fanIn: fanIn,
            connections: connections,
            subscriptions: subscriptions,
            recipient: recipient,
            submissionProbe: submissionProbe,
            ledger: ledger
        )
    }

    private func makeMultiRecipientHarness(
        submissionProbe: SubmissionProbe = .init()
    ) throws -> MultiRecipientHarness {
        let ledger = try Fixture.makeHarness(localRole: .conductor)
        let controlConnections = makeConnections()
        let anonymousConnections = makeConnections()
        let controlSubscriptions = try makeSubscriptions(prefix: "control")
        let anonymousSubscriptions = try makeSubscriptions(
            prefix: "anonymous"
        )
        let controlRecipient = try signingKey(21)
        let anonymousRecipient = try signingKey(22)
        let controlGroup = try recipientRouteGroup(
            attemptBinding: .init(bootstrap: bootstrap(ledger)),
            recipient: controlRecipient,
            channel: .control,
            connections: controlConnections,
            subscriptions: controlSubscriptions
        )
        let anonymousGroup = try recipientRouteGroup(
            attemptBinding: .init(bootstrap: bootstrap(ledger)),
            recipient: anonymousRecipient,
            channel: .anonymous,
            connections: anonymousConnections,
            subscriptions: anonymousSubscriptions
        )
        let fanIn = try makeFanIn(
            ledger: ledger,
            recipientRouteGroups: [controlGroup, anonymousGroup],
            submissionProbe: submissionProbe
        )
        return .init(
            fanIn: fanIn,
            controlConnections: controlConnections,
            anonymousConnections: anonymousConnections,
            controlSubscriptions: controlSubscriptions,
            anonymousSubscriptions: anonymousSubscriptions,
            controlRecipient: controlRecipient,
            anonymousRecipient: anonymousRecipient,
            submissionProbe: submissionProbe,
            ledger: ledger
        )
    }

    private func makeFanIn(
        ledger: Fixture.Harness,
        connections: [any OpalFusion.Mosaic.TorWebSocketConnectioning],
        subscriptions: [
            Tracker.Endpoint: Nostr.SubscriptionIdentifier
        ],
        recipient: OpalCrypto.Secp256k1.SigningKey? = nil,
        submissionProbe: SubmissionProbe = .init(),
        maximumPendingEventCount: Int = 8,
        maximumFrameByteCount: Int? = nil,
        relaySetDigest: [UInt8]? = nil,
        beforeDriverStart: @escaping @Sendable () async -> Void = {},
        clockGate: BlockingClockGate? = nil
    ) throws -> FanIn {
        let recipient = try recipient ?? signingKey(21)
        let relaySetDigest = relaySetDigest
            ?? ledger.manifest.core.relaySetDigest
        let group = try recipientRouteGroup(
            attemptBinding: .init(bootstrap: bootstrap(ledger)),
            recipient: recipient,
            channel: .control,
            connections: connections,
            subscriptions: subscriptions
        )
        return try makeFanIn(
            ledger: ledger,
            recipientRouteGroups: [group],
            submissionProbe: submissionProbe,
            maximumPendingEventCount: maximumPendingEventCount,
            maximumFrameByteCount: maximumFrameByteCount,
            relaySetDigest: relaySetDigest,
            beforeDriverStart: beforeDriverStart,
            clockGate: clockGate
        )
    }

    private func makeFanIn(
        ledger: Fixture.Harness,
        recipientRouteGroups: [FanIn.RecipientRouteGroup],
        roleDependencies: Alpha.PostManifestRuntimeDriver.RoleDependencies? = nil,
        submissionProbe: SubmissionProbe = .init(),
        maximumPendingEventCount: Int = 8,
        maximumFrameByteCount: Int? = nil,
        relaySetDigest: [UInt8]? = nil,
        beforeDriverStart: @escaping @Sendable () async -> Void = {},
        clockGate: BlockingClockGate? = nil
    ) throws -> FanIn {
        let limits = try relayLimits(
            subscriptionIdentifiers: recipientRouteGroups.flatMap {
                $0.subscriptionIdentifiers.values
            },
            maximumFrameByteCount: maximumFrameByteCount
        )
        return try .init(
            bootstrap: bootstrap(ledger),
            roleDependencies: roleDependencies ?? conductorDependencies,
            recipientRouteGroups: recipientRouteGroups,
            relaySelection: try .init(
                manifestRelaySetDigest:
                    relaySetDigest ?? ledger.manifest.core.relaySetDigest,
                endpoints: (1 ... Alpha.relayCount).map(endpoint),
                using: ExactRelaySelectionValidator(
                    digest:
                        relaySetDigest ?? ledger.manifest.core.relaySetDigest,
                    endpoints: Set((1 ... Alpha.relayCount).map(endpoint))
                )
            ),
            ingressDependencies: .init(
                currentUnixSeconds: {
                    clockGate?.block()
                    return ledger.manifest.core.deadlines.phaseStart + 1
                },
                beforeDriverStart: beforeDriverStart
            ),
            codingLimits: limits,
            maximumPendingEventCount: maximumPendingEventCount,
            dependencies: .init(submissionObserver: {
                identifier,
                decision in
                submissionProbe.record(identifier, decision)
            })
        )
    }

    private func recipientRouteGroup(
        attemptBinding: FanIn.AttemptBinding,
        recipient: OpalCrypto.Secp256k1.SigningKey,
        channel: Transport.Channel,
        connections: [any OpalFusion.Mosaic.TorWebSocketConnectioning],
        subscriptions: [
            Tracker.Endpoint: Nostr.SubscriptionIdentifier
        ]
    ) throws -> FanIn.RecipientRouteGroup {
        let selectedEndpoints = (1 ... Alpha.relayCount).map(endpoint)
        return .init(
            attemptBinding: attemptBinding,
            recipient: .init(channel: channel, signingKey: recipient),
            routes: zip(selectedEndpoints, connections).map {
                .init(endpoint: $0.0, connection: $0.1)
            },
            subscriptionIdentifiers: subscriptions
        )
    }

    private var conductorDependencies:
        Alpha.PostManifestRuntimeDriver.RoleDependencies {
        .conductor(
            .init(
                componentAuthorizationEvaluator: .unavailable,
                bchSignatureAuthorizationEvaluator: .unavailable,
                previousOutputSource: RejectingPreviousOutputSource(),
                maximumPendingInputCount: 8,
                handoffPublication: { _ in
                    throw ProbeFailure.unexpectedInvocation
                }
            )
        )
    }

    private var contributorDependencies:
        Alpha.PostManifestRuntimeDriver.RoleDependencies {
        let host = RejectingCompleteTransactionHost()
        return .contributor(
            .init(
                execution: .init(
                    transactionHost: host,
                    previousOutputSource: RejectingPreviousOutputSource(),
                    makeLocalContributionMaterial: { _, _ in
                        throw ProbeFailure.unexpectedInvocation
                    },
                    publishPlayerCommit: { _ in
                        throw ProbeFailure.unexpectedInvocation
                    },
                    publishAnonymousComponents: { _ in
                        throw ProbeFailure.unexpectedInvocation
                    },
                    publishPreSignAcknowledgement: { _ in
                        throw ProbeFailure.unexpectedInvocation
                    },
                    publishLocalBCHSignatures: { _ in
                        throw ProbeFailure.unexpectedInvocation
                    }
                ),
                expectedReservationExpiration: .distantFuture,
                maximumPendingInputCount: 8,
                makeReservationRequest: { _ in
                    throw ProbeFailure.unexpectedInvocation
                }
            )
        )
    }

    private func bootstrap(
        _ ledger: Fixture.Harness
    ) -> Alpha.PostManifestRuntimeDriver.Bootstrap {
        .init(
            validatedAttempt: Fixture.makeValidatedAttempt(
                election: ledger.election
            ),
            attemptIdentifier: ledger.attemptIdentifier,
            generationIdentifier: ledger.generationIdentifier,
            materialIdentifier: ledger.materialIdentifier,
            localControlIdentity: ledger.localControlIdentity,
            proposalValidation: ledger.proposalValidation
        )
    }

    private func manifestRun(
        _ ledger: Fixture.Harness
    ) throws -> Fixture.AggregateRun {
        try Fixture.aggregateRun(
            canonicalBytes: ledger.manifest.canonicalBytes,
            kind: .completeManifest,
            sender: ledger.election.result.roster.conductor,
            phase: .manifestAgreement,
            sequence: 0,
            harness: ledger
        )
    }

    private func manifestReservationGiftWrap(
        _ harness: Harness
    ) throws -> Nostr.Event {
        try controlGiftWrap(
            manifestRun(harness.ledger).reservation.envelope,
            ledger: harness.ledger,
            recipient: harness.recipient
        )
    }

    private func controlGiftWrap(
        _ envelope: Alpha.ControlEnvelope,
        ledger: Fixture.Harness,
        recipient: OpalCrypto.Secp256k1.SigningKey
    ) throws -> Nostr.Event {
        try Transport.makeControlGiftWrap(
            envelope,
            context: .init(
                attemptIdentifier: ledger.attemptIdentifier,
                generationIdentifier: ledger.generationIdentifier,
                phaseStartUnixSeconds:
                    ledger.manifest.core.deadlines.phaseStart
            ),
            timestamps: .init(
                phaseStartUnixSeconds:
                    ledger.manifest.core.deadlines.phaseStart,
                currentUnixSeconds:
                    ledger.manifest.core.deadlines.phaseStart + 1,
                sealCreatedAt: ledger.manifest.core.deadlines.phaseStart,
                giftWrapCreatedAt: ledger.manifest.core.deadlines.phaseStart
            ),
            senderEventSigningKey: try eventSigningKey(
                matching: envelope.senderEventIdentity
            ),
            recipientPublicKey: recipient.bip340VerificationKey
        )
    }

    private func anonymousGiftWrap(
        ledger: Fixture.Harness,
        recipient: OpalCrypto.Secp256k1.SigningKey
    ) throws -> Nostr.Event {
        let sender = try signingKey(23)
        let envelope = try Alpha.AnonymousEnvelope(
            roundIdentifier: ledger.manifest.core.roundIdentifier,
            phase: .anonymousComponentSubmission,
            senderCommunicationPublicKey: Array(
                sender.publicKey.compressedRepresentation
            ),
            recipientEventIdentity: Array(
                recipient.bip340VerificationKey.rawRepresentation
            ),
            sequence: 0,
            payloadType: .anonymousComponent,
            expiryUnixSeconds: ledger.manifest.core.deadlines.bchSigning + 1,
            payload: [0x00]
        )
        return try Transport.makeAnonymousGiftWrap(
            envelope,
            context: .init(
                attemptIdentifier: ledger.attemptIdentifier,
                generationIdentifier: ledger.generationIdentifier,
                phaseStartUnixSeconds:
                    ledger.manifest.core.deadlines.phaseStart
            ),
            timestamps: .init(
                phaseStartUnixSeconds:
                    ledger.manifest.core.deadlines.phaseStart,
                currentUnixSeconds:
                    ledger.manifest.core.deadlines.phaseStart + 1,
                sealCreatedAt: ledger.manifest.core.deadlines.phaseStart,
                giftWrapCreatedAt: ledger.manifest.core.deadlines.phaseStart
            ),
            senderCommunicationSigningKey: sender,
            recipientPublicKey: recipient.bip340VerificationKey
        )
    }

    private func makeConnections()
        -> [ScriptedMosaicTorWebSocketConnection] {
        (0 ..< Alpha.relayCount).map { _ in
            ScriptedMosaicTorWebSocketConnection()
        }
    }

    private func makeSubscriptions(
        prefix: String = "alpha5-fanin"
    ) throws -> [
        Tracker.Endpoint: Nostr.SubscriptionIdentifier
    ] {
        try Dictionary(
            uniqueKeysWithValues: (1 ... Alpha.relayCount).map {
                (endpoint($0), try .init("\(prefix)-\($0)"))
            }
        )
    }

    private func relayLimits(
        subscriptions: [
            Tracker.Endpoint: Nostr.SubscriptionIdentifier
        ],
        maximumFrameByteCount: Int? = nil
    ) throws -> Nostr.RelayMessageCodingLimits {
        try relayLimits(
            subscriptionIdentifiers: Array(subscriptions.values),
            maximumFrameByteCount: maximumFrameByteCount
        )
    }

    private func relayLimits(
        subscriptionIdentifiers: [Nostr.SubscriptionIdentifier],
        maximumFrameByteCount: Int? = nil
    ) throws -> Nostr.RelayMessageCodingLimits {
        let identifierWidth = try subscriptionIdentifiers.map {
            try JSONEncoder().encode($0.value).count
        }.max() ?? 0
        let derivedMaximum = Data("[\"EVENT\",".utf8).count
            + identifierWidth + 1
            + Alpha.nip59MaximumGiftWrapJSONByteCount + 1
        return try .init(
            maximumFrameByteCount: maximumFrameByteCount ?? derivedMaximum,
            maximumFiltersPerRequest: 1,
            maximumValuesPerFilter: 1,
            maximumMessageStringByteCount: 256,
            event: (try Transport.codingLimits).event
        )
    }

    private func expectedRequestFrame(
        recipient: OpalCrypto.Secp256k1.SigningKey,
        identifier: Nostr.SubscriptionIdentifier,
        limits: Nostr.RelayMessageCodingLimits
    ) throws -> String {
        let subscription = try Nostr.RelaySubscription(
            identifier: identifier,
            filters: [try Transport.relayFilter(
                recipientPublicKey: recipient.bip340VerificationKey
            )]
        )
        return String(
            decoding: try Nostr.RelayMessageCodec.encode(
                .request(subscription),
                limits: limits
            ),
            as: UTF8.self
        )
    }

    private func relayEventFrame(
        subscription: Nostr.SubscriptionIdentifier,
        event: Nostr.Event
    ) throws -> OpalFusion.Mosaic.TorWebSocketMessage {
        let encoded = try Nostr.EventCodec.encode(
            event,
            limits: (try Transport.codingLimits).event
        )
        return textFrame(
            "[\"EVENT\"," + Nostr.EventCodec.encodeString(subscription.value)
                + "," + String(decoding: encoded, as: UTF8.self) + "]"
        )
    }

    private func textFrame(
        _ value: String
    ) -> OpalFusion.Mosaic.TorWebSocketMessage {
        .text(Data(value.utf8))
    }

    private func endpoint(_ index: Int) -> Tracker.Endpoint {
        .init(validatedIdentifier: "fanin-relay-\(index)")
    }

    private func eventSigningKey(
        matching identity: [UInt8]
    ) throws -> OpalCrypto.Secp256k1.SigningKey {
        for scalar in [UInt8(9), UInt8(10)] {
            let candidate = try signingKey(scalar)
            if Array(candidate.bip340VerificationKey.rawRepresentation)
                == identity {
                return candidate
            }
        }
        throw ProbeFailure.unexpectedInvocation
    }

    private func signingKey(
        _ scalarByte: UInt8
    ) throws -> OpalCrypto.Secp256k1.SigningKey {
        try .init(
            rawRepresentation: Data(repeating: 0, count: 31)
                + Data([scalarByte])
        )
    }

    private enum ProbeFailure: Error {
        case unexpectedInvocation
    }
}

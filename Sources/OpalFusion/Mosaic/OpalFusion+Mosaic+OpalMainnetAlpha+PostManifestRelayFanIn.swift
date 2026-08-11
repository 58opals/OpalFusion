// OpalFusion+Mosaic+OpalMainnetAlpha+PostManifestRelayFanIn.swift

import Foundation

extension OpalFusion.Mosaic.OpalMainnetAlpha {
    /// Fans one attempt's provisioned recipient mailboxes through isolated three-route groups.
    ///
    /// The route owner supplies every immutable recipient capability, distinct Tor-only
    /// connection, and fresh subscription identifier. This actor constructs one shared ingress,
    /// runtime, and replay authority; starts every route-group subscription before consuming;
    /// binds each EVENT recipient back to that route; preserves each route's source order while
    /// serializing every signed EVENT copy; and treats loss of any selected source as terminal.
    /// Recipient allocation, endpoint provisioning,
    /// reconnect, persistence, duplicate merging, and concrete Tor circuit isolation remain
    /// external.
    actor PostManifestRelayFanIn {
        private typealias Session = OpalFusion.Mosaic.NIP01RelaySession

        private struct SessionRoute: Sendable {
            let recipientEventIdentity: Data
            let subscription: Nostr.RelaySubscription
            let session: Session
        }

        private struct StartedRoute: Sendable {
            let route: SessionRoute
            let output: Session.OutputStream
        }

        private enum StartResult: Sendable {
            case started(StartedRoute)
            case failed
            case cancelled
        }

        private enum ShutdownCause: Sendable {
            case stopped
            case sourceFailed
            case runtime(Driver.State)
        }

        private let routes: [SessionRoute]
        private let ingress: Ingress
        private let dependencies: Dependencies
        private let eventStream: AsyncStream<Nostr.Event>
        private var eventContinuation: AsyncStream<Nostr.Event>.Continuation
        private var consumerTask: Task<Void, Never>?
        private var readerTasks: [Task<Void, Never>] = []
        private var runtimeTask: Task<Void, Never>?
        private var shutdownTask: Task<Void, Never>?
        private var hasCompletedIngressStartup = false
        private var ingressStartupWaiters: [
            CheckedContinuation<Void, Never>
        ] = []
        private var terminationWaiters: [
            CheckedContinuation<Termination, Never>
        ] = []

        private(set) var state: State = .idle

        init(
            bootstrap: Driver.Bootstrap,
            roleDependencies: Driver.RoleDependencies,
            recipientRouteGroups: [RecipientRouteGroup],
            relaySelection: RelaySelectionValidation,
            ingressDependencies: Ingress.Dependencies,
            codingLimits: Nostr.RelayMessageCodingLimits,
            maximumPendingEventCount: Int,
            dependencies: Dependencies = .init()
        ) throws(InitializationError) {
            guard !recipientRouteGroups.isEmpty else {
                throw .invalidRecipientGroupCount(actual: 0)
            }
            let maximumAnonymousRecipientCount = bootstrap.proposalValidation
                .core.roster.contributors.count
                * OpalFusion.Mosaic.OpalMainnetAlpha
                    .componentCountPerContributor
            let maximumRecipientGroupCount = 1
                + (roleDependencies.role == .conductor
                    ? maximumAnonymousRecipientCount
                    : 0)
            guard recipientRouteGroups.count <= maximumRecipientGroupCount else {
                throw .invalidRecipientGroupCount(
                    actual: recipientRouteGroups.count
                )
            }
            let recipients = recipientRouteGroups.map(\.recipient)
            let recipientSet: Ingress.RecipientSet
            do {
                recipientSet = try .init(recipients)
            } catch {
                throw .invalidRecipientSet
            }
            let controlRecipientCount = recipients.reduce(into: 0) {
                count,
                recipient in
                guard recipient.channel == .control else { return }
                count += 1
            }
            switch roleDependencies.role {
            case .contributor:
                guard recipients.count == 1,
                      controlRecipientCount == 1 else {
                    throw .invalidRecipientChannels
                }
            case .conductor:
                guard controlRecipientCount == 1 else {
                    throw .invalidRecipientChannels
                }
            }
            guard maximumPendingEventCount > 0 else {
                throw .invalidEventBufferLimit
            }

            let transportLimits: Nostr.NIP59EnvelopeCodec.CodingLimits
            do {
                transportLimits = try Transport.codingLimits
            } catch {
                throw .incompatibleCodingLimits
            }
            guard codingLimits.event == transportLimits.event else {
                throw .incompatibleCodingLimits
            }

            guard relaySelection.manifestRelaySetDigest
                    == bootstrap.proposalValidation.core.relaySetDigest else {
                throw .relaySelectionManifestMismatch
            }
            var connections: Set<ObjectIdentifier> = []
            var distinctSubscriptions: Set<Nostr.SubscriptionIdentifier> = []
            var sessionRoutes: [SessionRoute] = []
            do {
                sessionRoutes.reserveCapacity(
                    recipientRouteGroups.count
                        * OpalFusion.Mosaic.OpalMainnetAlpha.relayCount
                )
                for group in recipientRouteGroups {
                    guard group.routes.count
                            == OpalFusion.Mosaic.OpalMainnetAlpha.relayCount else {
                        throw InitializationError.invalidRelayCount(
                            actual: group.routes.count
                        )
                    }
                    var endpoints: Set<RelayEndpoint> = []
                    for route in group.routes {
                        guard endpoints.insert(route.endpoint).inserted else {
                            throw InitializationError.duplicateRelay(route.endpoint)
                        }
                        guard connections.insert(
                            ObjectIdentifier(route.connection as AnyObject)
                        ).inserted else {
                            throw InitializationError.duplicateConnection
                        }
                    }
                    guard endpoints == Set(relaySelection.endpoints) else {
                        throw InitializationError.relaySelectionMismatch
                    }
                    guard group.subscriptionIdentifiers.count
                            == OpalFusion.Mosaic.OpalMainnetAlpha.relayCount else {
                        throw InitializationError.invalidSubscriptionCount(
                            actual: group.subscriptionIdentifiers.count
                        )
                    }
                    guard Set(group.subscriptionIdentifiers.keys) == endpoints else {
                        throw InitializationError.subscriptionSetMismatch
                    }
                    for identifier in group.subscriptionIdentifiers.values {
                        guard distinctSubscriptions.insert(identifier).inserted else {
                            throw InitializationError
                                .duplicateSubscriptionIdentifier
                        }
                    }
                    let filter = try Transport.relayFilter(
                        recipientPublicKey:
                            group.recipient.signingKey.bip340VerificationKey
                    )
                    for route in group.routes {
                        guard let identifier = group.subscriptionIdentifiers[
                            route.endpoint
                        ] else {
                            throw InitializationError.subscriptionSetMismatch
                        }
                        let subscription = try Nostr.RelaySubscription(
                            identifier: identifier,
                            filters: [filter]
                        )
                        _ = try Nostr.RelayMessageCodec.encode(
                            .request(subscription),
                            limits: codingLimits
                        )
                        let encodedIdentifier = try JSONEncoder().encode(
                            identifier.value
                        )
                        let maximumInboundEventFrameByteCount = Data(
                            "[\"EVENT\",".utf8
                        ).count + encodedIdentifier.count + 1
                            + OpalFusion.Mosaic.OpalMainnetAlpha
                                .nip59MaximumGiftWrapJSONByteCount + 1
                        guard codingLimits.maximumFrameByteCount
                                >= maximumInboundEventFrameByteCount else {
                            throw InitializationError.incompatibleCodingLimits
                        }
                        sessionRoutes.append(
                            .init(
                                recipientEventIdentity:
                                    group.recipient.recipientEventIdentity,
                                subscription: subscription,
                                session: try Session(
                                    connection: route.connection,
                                    codingLimits: codingLimits,
                                    // The caller-owned count bounds the shared FIFO. Each route
                                    // retains at most one frame while all subscriptions start.
                                    maximumPendingOutputCount: 1
                                )
                            )
                        )
                    }
                }
            } catch let error as InitializationError {
                throw error
            } catch {
                throw .invalidSubscription
            }

            do {
                ingress = try .init(
                    bootstrap: bootstrap,
                    roleDependencies: roleDependencies,
                    recipientSet: recipientSet,
                    dependencies: ingressDependencies
                )
            } catch let error {
                throw .ingress(error)
            }

            self.routes = sessionRoutes
            self.dependencies = dependencies
            let (eventStream, eventContinuation) = AsyncStream<Nostr.Event>
                .makeStream(
                    bufferingPolicy: .bufferingOldest(
                        maximumPendingEventCount
                    )
                )
            self.eventStream = eventStream
            self.eventContinuation = eventContinuation
        }

        /// Starts the private ingress and every recipient subscription exactly once.
        func start() async throws {
            guard state == .idle else { throw Failure.alreadyUsed }
            state = .starting

            try await withTaskCancellationHandler {
                let didStartIngress = await ingress.start()
                completeIngressStartup()
                guard state == .starting else {
                    await shutdownTask?.value
                    throw failureForTerminalState()
                }
                guard !Task.isCancelled else {
                    let shutdown = beginShutdown(.stopped)
                    await shutdown.value
                    throw Failure.cancelled
                }
                guard didStartIngress,
                      await ingress.state == .running else {
                    let runtimeState = await ingress.waitForTermination()
                    if let runtimeState {
                        await finishWithoutStartedRoutes(
                            .runtime(runtimeState)
                        )
                    } else {
                        await finishWithoutStartedRoutes(.sourceFailed)
                    }
                    throw Failure.runtimeTerminated
                }

                runtimeTask = Task { [weak self, ingress] in
                    guard let self else { return }
                    guard let runtimeState = await ingress.waitForTermination()
                    else { return }
                    await self.runtimeDidTerminate(runtimeState)
                }

                let results = await startRoutes()
                var startedRoutes: [StartedRoute] = []
                var didFail = false
                for result in results {
                    switch result {
                    case let .started(started):
                        startedRoutes.append(started)
                    case .failed:
                        didFail = true
                    case .cancelled:
                        break
                    }
                }
                for started in startedRoutes where !didFail {
                    guard await started.route.session.state == .running else {
                        didFail = true
                        break
                    }
                }

                guard state == .starting else {
                    await shutdownTask?.value
                    throw failureForTerminalState()
                }
                guard !Task.isCancelled else {
                    let shutdown = beginShutdown(.stopped)
                    await shutdown.value
                    throw Failure.cancelled
                }
                guard !didFail,
                      startedRoutes.count == routes.count else {
                    let shutdown = beginShutdown(.sourceFailed)
                    await shutdown.value
                    throw Failure.sourceFailed
                }

                consumerTask = Task { [weak self] in
                    guard let self else { return }
                    await self.consumeEvents()
                }
                state = .running
            } onCancel: {
                Task { await self.stop() }
            }
        }

        /// Stops once, drains events already accepted by the bounded fan-in, and closes all routes.
        func stop() async {
            guard case .terminal = state else {
                if state == .idle {
                    completeIngressStartup()
                }
                let shutdown = beginShutdown(.stopped)
                await shutdown.value
                return
            }
        }

        @discardableResult
        func waitForTermination() async -> Termination? {
            switch state {
            case .idle:
                return nil
            case let .terminal(termination):
                return termination
            case .starting, .running, .stopping:
                return await withCheckedContinuation { continuation in
                    terminationWaiters.append(continuation)
                }
            }
        }

        private func startRoutes() async -> [StartResult] {
            await withTaskGroup(of: StartResult.self) { group in
                for route in routes {
                    group.addTask {
                        do {
                            let output = try await route.session.start()
                            let started = StartedRoute(
                                route: route,
                                output: output
                            )
                            await self.startReading(started)
                            try await route.session.subscribe(
                                route.subscription
                            )
                            return .started(started)
                        } catch {
                            guard !Task.isCancelled else {
                                return .cancelled
                            }
                            return .failed
                        }
                    }
                }
                var results: [StartResult] = []
                var didClaimFailure = false
                for await result in group {
                    results.append(result)
                    guard case .failed = result,
                          !Task.isCancelled,
                          !didClaimFailure else {
                        continue
                    }
                    didClaimFailure = true
                    _ = beginShutdown(.sourceFailed)
                    group.cancelAll()
                }
                return results
            }
        }

        private func startReading(_ started: StartedRoute) async {
            guard state == .starting else { return }
            await withCheckedContinuation { continuation in
                let task = Task {
                    await self.consume(
                        started,
                        startupContinuation: continuation
                    )
                }
                readerTasks.append(task)
            }
        }

        private func consume(
            _ started: StartedRoute,
            startupContinuation: CheckedContinuation<Void, Never>
        ) async {
            var iterator = started.output.makeAsyncIterator()
            startupContinuation.resume()
            do {
                while let message = try await iterator.next() {
                    guard state == .starting || state == .running else {
                        return
                    }
                    switch message {
                    case let .event(identifier, event):
                        guard identifier
                                == started.route.subscription.identifier,
                              (try? Transport.recipientEventIdentity(in: event))
                                == started.route.recipientEventIdentity else {
                            sourceDidFail()
                            return
                        }
                        switch eventContinuation.yield(event) {
                        case .enqueued:
                            break
                        case .dropped, .terminated:
                            sourceDidFail()
                            return
                        @unknown default:
                            sourceDidFail()
                            return
                        }
                    case .endOfStoredEvents, .notice:
                        continue
                    case .subscriptionClosed, .acknowledgement:
                        sourceDidFail()
                        return
                    }
                }
                guard state == .starting || state == .running else {
                    return
                }
                sourceDidFail()
            } catch {
                guard state == .starting || state == .running else {
                    return
                }
                sourceDidFail()
            }
        }

        private func consumeEvents() async {
            for await event in eventStream {
                let decision = await ingress.submit(event)
                dependencies.submissionObserver(
                    event.identifier,
                    decision
                )
            }
        }

        private func sourceDidFail() {
            guard state == .starting || state == .running else { return }
            _ = beginShutdown(.sourceFailed)
        }

        private func runtimeDidTerminate(_ runtimeState: Driver.State) {
            switch state {
            case .starting, .running:
                _ = beginShutdown(.runtime(runtimeState))
            case .idle, .stopping, .terminal:
                return
            }
        }

        private func beginShutdown(
            _ cause: ShutdownCause
        ) -> Task<Void, Never> {
            if let shutdownTask { return shutdownTask }
            state = .stopping
            let shutdownTask = Task { [weak self] in
                guard let self else { return }
                await self.executeShutdown(cause)
            }
            self.shutdownTask = shutdownTask
            return shutdownTask
        }

        private func executeShutdown(_ cause: ShutdownCause) async {
            await stopAllSessions()
            let readerTasks = readerTasks
            for readerTask in readerTasks {
                await readerTask.value
            }
            eventContinuation.finish()
            await consumerTask?.value

            switch cause {
            case .stopped:
                await ingress.stop()
            case .sourceFailed:
                _ = await ingress.inputSourceDidTerminate(.failed)
            case .runtime:
                break
            }
            await waitForIngressStartup()

            let termination: Termination
            switch cause {
            case .stopped:
                _ = await ingress.waitForTermination()
                termination = .stopped
            case .sourceFailed:
                if let runtimeState = await ingress.waitForTermination(),
                   !isSourceFailure(runtimeState) {
                    termination = .runtime(runtimeState)
                } else {
                    termination = .failed(.sourceFailed)
                }
            case let .runtime(runtimeState):
                termination = .runtime(runtimeState)
            }
            await runtimeTask?.value
            completeShutdown(termination)
        }

        private func stopAllSessions() async {
            let sessions = routes.map(\.session)
            await withTaskGroup(of: Void.self) { group in
                for session in sessions {
                    group.addTask {
                        await session.stop()
                        await session.waitForTermination()
                    }
                }
            }
        }

        private func waitForIngressStartup() async {
            guard !hasCompletedIngressStartup else { return }
            await withCheckedContinuation { continuation in
                ingressStartupWaiters.append(continuation)
            }
        }

        private func completeIngressStartup() {
            hasCompletedIngressStartup = true
            let waiters = ingressStartupWaiters
            ingressStartupWaiters.removeAll()
            for waiter in waiters {
                waiter.resume()
            }
        }

        private func isSourceFailure(_ runtimeState: Driver.State) -> Bool {
            switch runtimeState {
            case .conductor(
                .terminal(.failed(.inputSourceTerminated(.failed)))
            ), .contributor(
                .terminal(.failed(.inputSourceTerminated(.failed)))
            ):
                true
            default:
                false
            }
        }

        private func finishWithoutStartedRoutes(
            _ cause: ShutdownCause
        ) async {
            let shutdown = beginShutdown(cause)
            await shutdown.value
        }

        private func failureForTerminalState() -> Failure {
            switch state {
            case .terminal(.stopped):
                .cancelled
            case .terminal(.runtime):
                .runtimeTerminated
            case .terminal(.failed), .idle, .starting, .running, .stopping:
                .sourceFailed
            }
        }

        private func completeShutdown(_ termination: Termination) {
            state = .terminal(termination)
            let waiters = terminationWaiters
            terminationWaiters.removeAll()
            for waiter in waiters {
                waiter.resume(returning: termination)
            }
        }
    }
}

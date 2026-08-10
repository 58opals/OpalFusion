// OpalFusion+Mosaic+OpalMainnetAlpha+PostManifestRelayFanIn.swift

import Foundation

extension OpalFusion.Mosaic.OpalMainnetAlpha {
    /// Fans one recipient's signed post-manifest gift wraps in from exactly three Tor routes.
    ///
    /// The route owner supplies distinct opaque endpoints, Tor-only connections, and fresh
    /// connection-local subscription identifiers. This actor starts every subscription before
    /// consuming, preserves each relay's source order while serializing every signed EVENT copy,
    /// and treats loss of any selected source as terminal. Endpoint provisioning, reconnect,
    /// persistence, recipient-key ownership, duplicate merging, and concrete Tor isolation remain
    /// external.
    actor PostManifestRelayFanIn {
        private typealias Session = OpalFusion.Mosaic.NIP01RelaySession

        private struct SessionRoute: Sendable {
            let endpoint: RelayEndpoint
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
            recipient: Transport.RecipientCapability,
            ingressDependencies: Ingress.Dependencies,
            routes: [RelayRoute],
            relaySelection: RelaySelectionValidation,
            subscriptionIdentifiers: [
                RelayEndpoint: Nostr.SubscriptionIdentifier
            ],
            codingLimits: Nostr.RelayMessageCodingLimits,
            maximumPendingEventCount: Int,
            dependencies: Dependencies = .init()
        ) throws(InitializationError) {
            guard routes.count
                    == OpalFusion.Mosaic.OpalMainnetAlpha.relayCount else {
                throw .invalidRelayCount(actual: routes.count)
            }

            var endpoints: Set<RelayEndpoint> = []
            var connections: Set<ObjectIdentifier> = []
            for route in routes {
                guard endpoints.insert(route.endpoint).inserted else {
                    throw .duplicateRelay(route.endpoint)
                }
                guard connections.insert(
                    ObjectIdentifier(route.connection as AnyObject)
                ).inserted else {
                    throw .duplicateConnection
                }
            }
            guard endpoints == Set(relaySelection.endpoints) else {
                throw .relaySelectionMismatch
            }
            guard relaySelection.manifestRelaySetDigest
                    == bootstrap.proposalValidation.core.relaySetDigest else {
                throw .relaySelectionManifestMismatch
            }
            guard subscriptionIdentifiers.count
                    == OpalFusion.Mosaic.OpalMainnetAlpha.relayCount else {
                throw .invalidSubscriptionCount(
                    actual: subscriptionIdentifiers.count
                )
            }
            guard Set(subscriptionIdentifiers.keys) == endpoints else {
                throw .subscriptionSetMismatch
            }
            var distinctSubscriptions: Set<Nostr.SubscriptionIdentifier> = []
            for identifier in subscriptionIdentifiers.values {
                guard distinctSubscriptions.insert(identifier).inserted else {
                    throw .duplicateSubscriptionIdentifier
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

            let filter: Nostr.RelayFilter
            do {
                filter = try Transport.relayFilter(
                    recipientPublicKey:
                        recipient.signingKey.bip340VerificationKey
                )
            } catch {
                throw .invalidSubscription
            }

            var sessionRoutes: [SessionRoute] = []
            do {
                for route in routes {
                    guard let identifier = subscriptionIdentifiers[
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
                            endpoint: route.endpoint,
                            subscription: subscription,
                            session: try Session(
                                connection: route.connection,
                                codingLimits: codingLimits,
                                maximumPendingOutputCount:
                                    maximumPendingEventCount
                            )
                        )
                    )
                }
            } catch let error as InitializationError {
                throw error
            } catch {
                throw .invalidSubscription
            }

            let recipientSet = Ingress.RecipientSet(recipient)
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

        /// Starts the private ingress and all three subscriptions exactly once.
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
                      startedRoutes.count
                        == OpalFusion.Mosaic.OpalMainnetAlpha.relayCount else {
                    let shutdown = beginShutdown(.sourceFailed)
                    await shutdown.value
                    throw Failure.sourceFailed
                }

                consumerTask = Task { [weak self] in
                    guard let self else { return }
                    await self.consumeEvents()
                }
                state = .running
                readerTasks = startedRoutes.map { started in
                    Task { [weak self] in
                        guard let self else { return }
                        await self.consume(started)
                    }
                }
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
                            try await route.session.subscribe(
                                route.subscription
                            )
                            return .started(
                                .init(route: route, output: output)
                            )
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

        private func consume(_ started: StartedRoute) async {
            do {
                for try await message in started.output {
                    guard state == .running else { return }
                    switch message {
                    case let .event(identifier, event):
                        guard identifier
                                == started.route.subscription.identifier else {
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
                guard state == .running else { return }
                sourceDidFail()
            } catch {
                guard state == .running else { return }
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
            guard state == .running else { return }
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

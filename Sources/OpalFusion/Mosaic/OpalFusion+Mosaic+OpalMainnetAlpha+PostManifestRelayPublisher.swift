// OpalFusion+Mosaic+OpalMainnetAlpha+PostManifestRelayPublisher.swift

import OpalCrypto

extension OpalFusion.Mosaic.OpalMainnetAlpha {
    /// Publishes one already-signed alpha.5 gift wrap over exactly three Tor-only routes.
    ///
    /// The publisher is deliberately one-shot. It attempts the byte-identical event on every
    /// injected route, accepts any two positive NIP-01 acknowledgements, never reconnects or
    /// falls back, and closes all three sessions before returning.
    actor PostManifestRelayPublisher {
        private typealias Session = OpalFusion.Mosaic.NIP01RelaySession
        private typealias Tracker = OpalFusion.Mosaic.RelayPublicationTracker

        private struct SessionRoute: Sendable {
            let endpoint: RelayEndpoint
            let session: Session
        }

        private struct StartedRoute: Sendable {
            let route: SessionRoute
            let output: Session.OutputStream
        }

        private enum StartResult: Sendable {
            case started(StartedRoute)
            case rejected(RelayEndpoint)
        }

        private struct RelayResponse: Sendable {
            let endpoint: RelayEndpoint
            let response: Tracker.Response
        }

        private let routes: [SessionRoute]
        private var sessionShutdownTask: Task<Void, Never>?
        private var shutdownWaiters: [CheckedContinuation<Void, Never>] = []

        private(set) var state: State = .idle

        init(
            routes: [PostManifestRelayRoute],
            relaySelection: PostManifestRelaySelectionValidation,
            codingLimits: Nostr.RelayMessageCodingLimits,
            maximumPendingRelayOutputCount: Int
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
            guard Set(routes.map(\.endpoint))
                    == Set(relaySelection.endpoints) else {
                throw .relaySelectionMismatch
            }

            guard maximumPendingRelayOutputCount > 0 else {
                throw .invalidOutputBufferLimit
            }
            do {
                let transportLimits = try OpalFusion.Mosaic.OpalMainnetAlpha
                    .PostManifestNIP59Transport.codingLimits
                guard codingLimits.event == transportLimits.event,
                      codingLimits.maximumFrameByteCount
                        >= OpalFusion.Mosaic.OpalMainnetAlpha
                            .nip59MaximumPublicationFrameByteCount else {
                    throw InitializationError.incompatibleCodingLimits
                }
            } catch let error as InitializationError {
                throw error
            } catch {
                throw .incompatibleCodingLimits
            }

            do {
                self.routes = try routes.map {
                    SessionRoute(
                        endpoint: $0.endpoint,
                        session: try Session(
                            connection: $0.connection,
                            codingLimits: codingLimits,
                            maximumPendingOutputCount:
                                maximumPendingRelayOutputCount
                        )
                    )
                }
            } catch {
                throw .invalidOutputBufferLimit
            }
        }

        /// Attempts one signed gift wrap on all routes and returns after two accepted ACKs.
        func publish(_ giftWrap: GiftWrap) async throws {
            guard state == .idle else { throw Failure.alreadyUsed }
            let event = giftWrap.event
            state = .publishing(event.identifier)

            try await withTaskCancellationHandler {
                let accepted = await executePublication(event)
                if Task.isCancelled {
                    await stop()
                    throw Failure.cancelled
                }
                guard state == .publishing(event.identifier) else {
                    await stop()
                    throw Failure.cancelled
                }
                if accepted {
                    await finish(.accepted(event.identifier))
                    guard state
                            == .terminal(.accepted(event.identifier)) else {
                        throw Failure.cancelled
                    }
                    return
                }
                await finish(.failed(.publicationRejected))
                guard state
                        == .terminal(.failed(.publicationRejected)) else {
                    throw Failure.cancelled
                }
                throw Failure.publicationRejected
            } onCancel: {
                Task { await self.stop() }
            }
        }

        /// Stops the one-shot publisher and unblocks every pending route operation.
        func stop() async {
            switch state {
            case .idle, .publishing:
                state = .stopping
                await stopSessions()
                completeShutdown(.stopped)
            case .stopping:
                await waitForShutdown()
            case .terminal:
                return
            }
        }

        private func executePublication(_ event: Nostr.Event) async -> Bool {
            var tracker: Tracker
            do {
                tracker = try Tracker(endpoints: routes.map(\.endpoint))
                for route in routes {
                    try tracker.markAttempted(route.endpoint)
                }
            } catch {
                return false
            }

            let startResults = await startRoutes()
            guard state == .publishing(event.identifier) else { return false }

            var startedRoutes: [StartedRoute] = []
            for result in startResults {
                switch result {
                case let .started(started):
                    startedRoutes.append(started)
                case let .rejected(endpoint):
                    do {
                        try tracker.record(.rejected, from: endpoint)
                    } catch {
                        return false
                    }
                }
            }
            guard tracker.status != .failed else {
                await stopSessions()
                return false
            }

            let (responses, responseContinuation) = AsyncStream<RelayResponse>
                .makeStream(bufferingPolicy: .bufferingOldest(routes.count))
            let responseTasks = startedRoutes.map { started in
                Task {
                    let response = await Self.awaitResponse(
                        from: started.output,
                        eventIdentifier: event.identifier
                    )
                    responseContinuation.yield(
                        RelayResponse(
                            endpoint: started.route.endpoint,
                            response: response
                        )
                    )
                }
            }

            await send(event, to: startedRoutes)
            guard state == .publishing(event.identifier) else {
                await shutdownResponseTasks(
                    responseTasks,
                    continuation: responseContinuation
                )
                return false
            }
            if tracker.status == .failed {
                await shutdownResponseTasks(
                    responseTasks,
                    continuation: responseContinuation
                )
                return false
            }

            for await result in responses {
                do {
                    try tracker.record(result.response, from: result.endpoint)
                } catch {
                    await shutdownResponseTasks(
                        responseTasks,
                        continuation: responseContinuation
                    )
                    return false
                }
                switch tracker.status {
                case .accepted:
                    await shutdownResponseTasks(
                        responseTasks,
                        continuation: responseContinuation
                    )
                    return true
                case .failed:
                    await shutdownResponseTasks(
                        responseTasks,
                        continuation: responseContinuation
                    )
                    return false
                case .awaitingResponses:
                    continue
                }
            }

            await shutdownResponseTasks(
                responseTasks,
                continuation: responseContinuation
            )
            return false
        }

        private func startRoutes() async -> [StartResult] {
            await withTaskGroup(of: StartResult.self) { group in
                for route in routes {
                    group.addTask {
                        do {
                            return .started(
                                StartedRoute(
                                    route: route,
                                    output: try await route.session.start()
                                )
                            )
                        } catch {
                            return .rejected(route.endpoint)
                        }
                    }
                }
                var results: [StartResult] = []
                for await result in group {
                    results.append(result)
                }
                return results
            }
        }

        private func send(
            _ event: Nostr.Event,
            to startedRoutes: [StartedRoute]
        ) async {
            await withTaskGroup(of: Void.self) { group in
                for started in startedRoutes {
                    group.addTask {
                        try? await started.route.session.publish(event)
                    }
                }
            }
        }

        private static func awaitResponse(
            from output: Session.OutputStream,
            eventIdentifier: OpalCrypto.Signature.Digest
        ) async -> Tracker.Response {
            do {
                for try await message in output {
                    try Task.checkCancellation()
                    guard case let .acknowledgement(
                        identifier,
                        accepted,
                        _
                    ) = message else {
                        continue
                    }
                    guard identifier == eventIdentifier else {
                        return .rejected
                    }
                    return accepted ? .accepted : .rejected
                }
            } catch {
                return .rejected
            }
            return .rejected
        }

        private func shutdownResponseTasks(
            _ tasks: [Task<Void, Never>],
            continuation: AsyncStream<RelayResponse>.Continuation
        ) async {
            await stopSessions()
            continuation.finish()
            for task in tasks {
                task.cancel()
                await task.value
            }
        }

        private func stopSessions() async {
            let shutdownTask: Task<Void, Never>
            if let sessionShutdownTask {
                shutdownTask = sessionShutdownTask
            } else {
                let sessions = routes.map(\.session)
                shutdownTask = Task {
                    await withTaskGroup(of: Void.self) { group in
                        for session in sessions {
                            group.addTask {
                                await session.stop()
                                await session.waitForTermination()
                            }
                        }
                    }
                }
                sessionShutdownTask = shutdownTask
            }
            await shutdownTask.value
        }

        private func finish(_ termination: Termination) async {
            switch state {
            case .idle, .publishing:
                state = .stopping
                await stopSessions()
                completeShutdown(termination)
            case .stopping:
                await waitForShutdown()
            case .terminal:
                return
            }
        }

        private func waitForShutdown() async {
            guard case .terminal = state else {
                await withCheckedContinuation { continuation in
                    shutdownWaiters.append(continuation)
                }
                return
            }
        }

        private func completeShutdown(_ termination: Termination) {
            state = .terminal(termination)
            let waiters = shutdownWaiters
            shutdownWaiters.removeAll()
            for waiter in waiters {
                waiter.resume()
            }
        }
    }
}

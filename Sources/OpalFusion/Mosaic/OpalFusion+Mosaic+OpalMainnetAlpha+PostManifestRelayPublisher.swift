// OpalFusion+Mosaic+OpalMainnetAlpha+PostManifestRelayPublisher.swift

import Foundation
import OpalCrypto

extension OpalFusion.Mosaic.OpalMainnetAlpha {
    /// Publishes one already-signed alpha.5 gift wrap over exactly three Tor-only routes.
    ///
    /// The publisher is deliberately one-shot. Before opening a route it write-ahead records the
    /// canonical signed event and every endpoint attempt. It accepts any two matching positive
    /// NIP-01 acknowledgements, never reconnects or falls back, and closes all sessions before
    /// returning. A transport interruption remains recoverable from the durable journal.
    actor PostManifestRelayPublisher {
        typealias Journal = PostManifestRelayPublicationJournal
        private typealias Session = OpalFusion.Mosaic.NIP01RelaySession

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
            case unavailable(RelayEndpoint)
        }

        private enum RelayResult: Sendable {
            case acknowledgement(
                RelayEndpoint,
                Journal.RelayAcknowledgement
            )
            case unavailable(RelayEndpoint)
        }

        private let routes: [SessionRoute]
        let publicationJournal: Journal
        let codingLimits: Nostr.RelayMessageCodingLimits
        private var activeContinuation: Journal.Continuation?
        private var sessionShutdownTask: Task<Void, Never>?
        private var shutdownWaiters: [CheckedContinuation<Void, Never>] = []

        private(set) var state: State = .idle

        init(
            routes: [PostManifestRelayRoute],
            relaySelection: PostManifestRelaySelectionValidation,
            publicationJournal: Journal,
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
            guard publicationJournal.isBound(to: relaySelection) else {
                throw .publicationJournalMismatch
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
            self.publicationJournal = publicationJournal
            self.codingLimits = codingLimits
        }

        /// Write-ahead records and attempts one signed gift wrap on all unresolved routes.
        func publish(
            _ giftWrap: GiftWrap,
            binding: Journal.PublicationBinding
        ) async throws {
            guard state == .idle else { throw Failure.alreadyUsed }
            let identifier = giftWrap.event.identifier
            state = .publishing(identifier)

            let continuation: Journal.Continuation
            do {
                continuation = try publicationJournal.prepare(
                    giftWrap,
                    binding: binding
                )
            } catch {
                await finish(.failed(.journalFailed))
                throw Failure.journalFailed
            }
            activeContinuation = continuation
            try await publishPrepared(
                giftWrap.event,
                continuation: continuation
            )
        }

        /// Stops the one-shot publisher and unblocks every pending route operation.
        func stop() async {
            switch state {
            case .idle:
                state = .stopping
                await stopSessions()
                completeShutdown(.stopped)

            case .publishing:
                state = .stopping
                let journalFailed: Bool
                if let activeContinuation {
                    do {
                        let current = try publicationJournal
                            .currentContinuation(matching: activeContinuation)
                        switch current.status {
                        case .awaitingAcknowledgements:
                            try publicationJournal.recordCompletion(
                                .cancelled,
                                eventIdentifier:
                                    current.publication.eventIdentifier
                            )
                        case .transportAccepted:
                            try publicationJournal.recordCompletion(
                                .transportAccepted,
                                eventIdentifier:
                                    current.publication.eventIdentifier
                            )
                        case .transportRejected:
                            try publicationJournal.recordCompletion(
                                .transportRejected,
                                eventIdentifier:
                                    current.publication.eventIdentifier
                            )
                        case .completed:
                            break
                        }
                        journalFailed = false
                    } catch {
                        journalFailed = true
                    }
                } else {
                    journalFailed = false
                }
                await stopSessions()
                completeShutdown(
                    journalFailed ? .failed(.journalFailed) : .stopped
                )

            case .stopping:
                await waitForShutdown()

            case .terminal:
                return
            }
        }

        func publishPrepared(
            _ event: Nostr.Event,
            continuation: Journal.Continuation
        ) async throws {
            try await withTaskCancellationHandler {
                do {
                    try await executePublication(
                        event,
                        continuation: continuation
                    )
                } catch let failure as Failure {
                    if Task.isCancelled
                        || state != .publishing(event.identifier) {
                        await stop()
                        if state == .terminal(.failed(.journalFailed)) {
                            throw Failure.journalFailed
                        }
                        throw Failure.cancelled
                    }
                    await finish(.failed(failure))
                    throw failure
                } catch {
                    await finish(.failed(.journalFailed))
                    throw Failure.journalFailed
                }

                if Task.isCancelled
                    || state != .publishing(event.identifier) {
                    await stop()
                    if state == .terminal(.failed(.journalFailed)) {
                        throw Failure.journalFailed
                    }
                    throw Failure.cancelled
                }
                await finish(.accepted(event.identifier))
                guard state == .terminal(.accepted(event.identifier)) else {
                    throw Failure.cancelled
                }
            } onCancel: {
                Task { await self.stop() }
            }
        }

        func resumePrepared(
            _ event: Nostr.Event,
            continuation: Journal.Continuation
        ) async throws {
            guard state == .idle else { throw Failure.alreadyUsed }
            guard continuation.publication.eventIdentifier
                    == event.identifier.rawRepresentation else {
                throw Failure.continuationMismatch
            }
            state = .publishing(event.identifier)
            activeContinuation = continuation
            try await publishPrepared(event, continuation: continuation)
        }

        private func executePublication(
            _ event: Nostr.Event,
            continuation: Journal.Continuation
        ) async throws(Failure) {
            var current: Journal.Continuation
            do {
                current = try publicationJournal.currentContinuation(
                    matching: continuation
                )
            } catch {
                throw .continuationMismatch
            }
            guard current.publication.eventIdentifier
                    == event.identifier.rawRepresentation else {
                throw .continuationMismatch
            }

            switch current.status {
            case .completed(.transportAccepted):
                return
            case .completed(.transportRejected):
                throw .publicationRejected
            case .completed(.cancelled):
                throw .cancelled
            case .transportAccepted:
                try recordCompletion(
                    .transportAccepted,
                    eventIdentifier: current.publication.eventIdentifier
                )
                return
            case .transportRejected:
                try recordCompletion(
                    .transportRejected,
                    eventIdentifier: current.publication.eventIdentifier
                )
                throw .publicationRejected
            case .awaitingAcknowledgements:
                break
            }

            let unresolvedEndpoints = current.unresolvedEndpoints
            do {
                for endpoint in unresolvedEndpoints {
                    try publicationJournal.recordAttempt(
                        eventIdentifier: current.publication.eventIdentifier,
                        endpoint: endpoint
                    )
                }
            } catch {
                throw .journalFailed
            }

            let startResults = await startRoutes(
                endpoints: Set(unresolvedEndpoints)
            )
            guard state == .publishing(event.identifier) else {
                throw .cancelled
            }

            let startedRoutes: [StartedRoute] = startResults.compactMap {
                result in
                guard case let .started(started) = result else { return nil }
                return started
            }
            guard !startedRoutes.isEmpty else {
                await stopSessions()
                guard state == .publishing(event.identifier) else {
                    throw .cancelled
                }
                throw .publicationInterrupted
            }
            let (results, resultContinuation) = AsyncStream<RelayResult>
                .makeStream(
                    bufferingPolicy: .bufferingOldest(startedRoutes.count)
                )
            let responseTasks = startedRoutes.map { started in
                Task {
                    _ = resultContinuation.yield(
                        await Self.awaitResponse(
                            from: started.output,
                            endpoint: started.route.endpoint,
                            eventIdentifier: event.identifier
                        )
                    )
                }
            }

            await send(event, to: startedRoutes)
            guard state == .publishing(event.identifier) else {
                await shutdownResponseTasks(
                    responseTasks,
                    continuation: resultContinuation
                )
                throw .cancelled
            }

            var receivedResultCount = 0
            for await result in results {
                receivedResultCount += 1
                switch result {
                case let .acknowledgement(endpoint, acknowledgement):
                    do {
                        try publicationJournal.recordAcknowledgement(
                            acknowledgement,
                            eventIdentifier:
                                current.publication.eventIdentifier,
                            endpoint: endpoint
                        )
                        current = try publicationJournal.currentContinuation(
                            matching: current
                        )
                    } catch {
                        await shutdownResponseTasks(
                            responseTasks,
                            continuation: resultContinuation
                        )
                        throw Failure.journalFailed
                    }
                case .unavailable:
                    break
                }

                switch current.status {
                case .transportAccepted:
                    try recordCompletion(
                        .transportAccepted,
                        eventIdentifier: current.publication.eventIdentifier
                    )
                    await shutdownResponseTasks(
                        responseTasks,
                        continuation: resultContinuation
                    )
                    guard state == .publishing(event.identifier) else {
                        throw .cancelled
                    }
                    return

                case .transportRejected:
                    try recordCompletion(
                        .transportRejected,
                        eventIdentifier: current.publication.eventIdentifier
                    )
                    await shutdownResponseTasks(
                        responseTasks,
                        continuation: resultContinuation
                    )
                    guard state == .publishing(event.identifier) else {
                        throw .cancelled
                    }
                    throw .publicationRejected

                case .awaitingAcknowledgements:
                    break

                case .completed:
                    throw .continuationMismatch
                }
                if receivedResultCount == startedRoutes.count { break }
            }

            await shutdownResponseTasks(
                responseTasks,
                continuation: resultContinuation
            )
            guard state == .publishing(event.identifier) else {
                throw .cancelled
            }
            throw .publicationInterrupted
        }

        private func recordCompletion(
            _ completion: Journal.Completion,
            eventIdentifier: Data
        ) throws(Failure) {
            do {
                try publicationJournal.recordCompletion(
                    completion,
                    eventIdentifier: eventIdentifier
                )
            } catch {
                throw .journalFailed
            }
        }

        private func startRoutes(
            endpoints: Set<RelayEndpoint>
        ) async -> [StartResult] {
            await withTaskGroup(of: StartResult.self) { group in
                for route in routes where endpoints.contains(route.endpoint) {
                    group.addTask {
                        do {
                            return .started(
                                StartedRoute(
                                    route: route,
                                    output: try await route.session.start()
                                )
                            )
                        } catch {
                            return .unavailable(route.endpoint)
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
            endpoint: RelayEndpoint,
            eventIdentifier: OpalCrypto.Signature.Digest
        ) async -> RelayResult {
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
                    guard identifier == eventIdentifier else { continue }
                    return .acknowledgement(
                        endpoint,
                        accepted ? .accepted : .rejected
                    )
                }
            } catch {
                return .unavailable(endpoint)
            }
            return .unavailable(endpoint)
        }

        private func shutdownResponseTasks(
            _ tasks: [Task<Void, Never>],
            continuation: AsyncStream<RelayResult>.Continuation
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
            activeContinuation = nil
            let waiters = shutdownWaiters
            shutdownWaiters.removeAll()
            for waiter in waiters {
                waiter.resume()
            }
        }
    }
}

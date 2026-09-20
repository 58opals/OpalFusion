// OpalFusion+MosaicPrivateAlphaRuntime+PrivateDeploymentInbox.swift

#if os(macOS)
import Foundation

extension OpalFusion.MosaicPrivateAlphaRuntime {
    /// Bounded public formation fan-in. Semantic admission remains with the durable owner.
    @_spi(MosaicPrivateAlpha)
    public actor PrivateDeploymentInbox {
        @_spi(MosaicPrivateAlpha)
        public struct Inbound: Sendable {
            @_spi(MosaicPrivateAlpha) public let payloadKind: UInt8
            @_spi(MosaicPrivateAlpha) public let event: PrivateDeploymentEvent
        }
        @_spi(MosaicPrivateAlpha)
        public enum InboxFailure: Error, Sendable, Equatable {
            case invalidConfiguration, invalidRouteAllocation, sourceLost, boundedBufferExceeded
        }
        @_spi(MosaicPrivateAlpha)
        public typealias EventStream = AsyncThrowingStream<Inbound, any Error>

        private typealias Nostr = OpalFusion.Mosaic.NostrNamespace
        private typealias Session = OpalFusion.Mosaic.NIP01RelaySession
        private let preparation: DiscoveryPreparation
        private let binding: Binding
        private let capabilities: PrivateDeploymentRelayCapabilities
        private let currentUnixSeconds: @Sendable () -> UInt64
        private let stream: EventStream
        private let continuation: EventStream.Continuation
        private var started = false
        private var terminal = false
        private var sessions: [Session] = []
        private var consumers: [Task<Void, Never>] = []
        private var identifiers: Set<Data> = []
        private let maximumEventCount: Int

        @_spi(MosaicPrivateAlpha)
        public init(
            preparation: DiscoveryPreparation,
            binding: Binding,
            capabilities: PrivateDeploymentRelayCapabilities,
            maximumEventCount: Int = 256,
            currentUnixSeconds: @escaping @Sendable () -> UInt64 = {
                UInt64(Date().timeIntervalSince1970)
            }
        ) throws {
            guard (1 ... 1_024).contains(maximumEventCount) else {
                throw InboxFailure.invalidConfiguration
            }
            try capabilities.validateResourceLimits()
            self.preparation = preparation
            self.binding = binding
            self.capabilities = capabilities
            self.maximumEventCount = maximumEventCount
            self.currentUnixSeconds = currentUnixSeconds
            (stream, continuation) = EventStream.makeStream(bufferingPolicy: .bufferingOldest(maximumEventCount))
        }

        @_spi(MosaicPrivateAlpha)
        public func start() async throws -> EventStream {
            guard !started, !terminal else { throw InboxFailure.invalidConfiguration }
            started = true
            continuation.onTermination = { [weak self] _ in Task { await self?.stop() } }
            let request = PrivateDeploymentRouteRequest(binding: binding, relayEndpointIdentifiers: preparation.relayEndpointIdentifiers)
            let routes: [PostManifestProvisionedRoute]
            do { routes = try await capabilities.provisionRoutes(request) }
            catch {
                await terminate(InboxFailure.invalidRouteAllocation)
                throw error
            }
            guard !Task.isCancelled, !terminal else {
                for route in routes { await route.connection.close() }
                await terminate(nil)
                throw CancellationError()
            }
            guard routes.count == 3,
                  Set(routes.map(\.relayEndpointIdentifier)) == Set(preparation.relayEndpointIdentifiers),
                  Set(routes.map(\.isolationIdentifier)).count == 3,
                  Set(routes.map { ObjectIdentifier($0.connection as AnyObject) }).count == 3 else {
                for route in routes { await route.connection.close() }
                await terminate(InboxFailure.invalidRouteAllocation)
                throw InboxFailure.invalidRouteAllocation
            }
            do {
                return try await withTaskCancellationHandler {
                    let limits = try Self.codingLimits()
                    let filter = try Nostr.RelayFilter(
                        kinds: Array(26_540 ... 26_548),
                        since: preparation.epochStartUnixSeconds,
                        until: preparation.epochStartUnixSeconds + 240,
                        limit: maximumEventCount
                    )
                    let pending = capabilities.maximumPendingRelayOutputCount
                    // Open independently: one slow route must not consume every peer's phase window.
                    let prepared = try await withThrowingTaskGroup(of: (Session, Session.OutputStream).self) { group in
                        for route in routes {
                            group.addTask {
                                let session = try Session(connection: TorWebSocketConnectionAdapter(route.connection, maximumPendingMessageCount: pending), codingLimits: limits, maximumPendingOutputCount: pending)
                                do {
                                    let output = try await session.start()
                                    try await session.subscribe(.init(identifier: .init(UUID().uuidString), filters: [filter]))
                                    return (session, output)
                                } catch {
                                    await session.stop()
                                    throw error
                                }
                            }
                        }
                        var results: [(Session, Session.OutputStream)] = []
                        do {
                            for try await result in group { results.append(result) }
                            return results
                        } catch {
                            group.cancelAll()
                            for route in routes { await route.connection.close() }
                            for result in results { await result.0.stop() }
                            throw error
                        }
                    }
                    guard !terminal, !Task.isCancelled else {
                        for result in prepared { await result.0.stop() }
                        throw CancellationError()
                    }
                    sessions = prepared.map(\.0)
                    consumers = prepared.map { result in Task { [weak self] in await self?.consume(result.1) } }
                    return stream
                } onCancel: {
                    Task { for route in routes { await route.connection.close() } }
                }
            } catch {
                for route in routes { await route.connection.close() }
                await terminate(InboxFailure.sourceLost)
                throw error
            }
        }

        @_spi(MosaicPrivateAlpha)
        public func stop() async {
            await terminate(nil)
            for consumer in consumers { await consumer.value }
        }

        private func consume(_ output: Session.OutputStream) async {
            do {
                for try await message in output {
                    try Task.checkCancellation()
                    switch message {
                    case let .event(_, event): try accept(event)
                    case .endOfStoredEvents, .notice: break
                    case .subscriptionClosed, .acknowledgement: throw InboxFailure.sourceLost
                    }
                }
                if !Task.isCancelled { await terminate(InboxFailure.sourceLost) }
            } catch is CancellationError { } catch {
                await terminate(error as? InboxFailure ?? .sourceLost)
            }
        }

        private func accept(_ event: Nostr.Event) throws {
            guard !terminal else { return }
            let payload = try OpalFusion.Mosaic.OpalMainnetAlpha.PreManifestNostrCodec.decodeCanonicalEnvelope(event)
            // Other epochs are untrusted relay noise. The owner validates pool, roster and deadlines.
            guard payload.discoveryEpochStartUnixSeconds == preparation.epochStartUnixSeconds else { return }
            guard identifiers.insert(event.identifier.rawRepresentation).inserted else { return }
            guard identifiers.count <= maximumEventCount else { throw InboxFailure.boundedBufferExceeded }
            let received = try PrivateDeploymentEvent(
                canonicalEventBytes: Nostr.EventCodec.encode(event, limits: Self.codingLimits().event),
                acceptedAtUnixSeconds: currentUnixSeconds()
            )
            if case .dropped = continuation.yield(.init(payloadKind: payload.payloadKind.rawValue, event: received)) {
                throw InboxFailure.boundedBufferExceeded
            }
        }

        private func terminate(_ failure: InboxFailure?) async {
            guard !terminal else { return }
            terminal = true
            for consumer in consumers { consumer.cancel() }
            let closing = sessions
            sessions = []
            for session in closing { await session.stop() }
            if let failure { continuation.finish(throwing: failure) } else { continuation.finish() }
        }

        private static func codingLimits() throws -> Nostr.RelayMessageCodingLimits {
            try .init(maximumFrameByteCount: 200_512, maximumFiltersPerRequest: 1,
                      maximumValuesPerFilter: 16, maximumMessageStringByteCount: 200_000,
                      event: .init(maximumEventJSONByteCount: 200_000, maximumTagCount: 1,
                                   maximumTagElementCount: 2, maximumStringByteCount: 150_000))
        }
    }
}
#endif

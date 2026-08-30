// OpalFusion+MosaicPrivateAlphaRuntime+TransportBootstrapInbox.swift

#if os(macOS)
import Foundation
import OpalCrypto

extension OpalFusion.MosaicPrivateAlphaRuntime {
    /// Exact-three relay fan-in for one authenticated bootstrap recipient.
    ///
    /// Any source loss is terminal. A caller reconnects by constructing a new inbox with the
    /// durable replay entries emitted before semantic admission.
    @_spi(MosaicPrivateAlpha)
    public actor TransportBootstrapInbox {
        @_spi(MosaicPrivateAlpha)
        public typealias EventStream = AsyncThrowingStream<
            TransportBootstrapInboundEvent,
            Swift.Error
        >

        private enum State {
            case idle
            case running
            case terminal
        }

        private let proof: PrivateDeploymentProof
        private let binding: Binding
        private let recipientEventIdentity: Data
        private let capabilities: TransportBootstrapRelayCapabilities
        private let eventStream: EventStream
        private var continuation: EventStream.Continuation
        private var state: State = .idle
        private var sessions: [String: OpalFusion.Mosaic.NIP01RelaySession]
            = [:]
        private var tasks: [Task<Void, Never>] = []
        private var terminationTasks: [Task<Void, Never>] = []
        private var messageIdentifiers: Set<Data>
        private var messageByWrapperIdentity: [Data: Data]

        @_spi(MosaicPrivateAlpha)
        public init(
            proof: PrivateDeploymentProof,
            binding: Binding,
            recipientEventIdentity: Data,
            capabilities: TransportBootstrapRelayCapabilities,
            replayEntries: [TransportBootstrapReplayEntry] = []
        ) throws {
            guard (try? OpalCrypto.Signature.BIP340.VerificationKey(
                rawRepresentation: recipientEventIdentity
            )) != nil else {
                throw TransportBootstrapFailure.invalidRecipient
            }
            try capabilities.validateResourceLimits()

            var messageIdentifiers: Set<Data> = []
            var messageByWrapperIdentity: [Data: Data] = [:]
            for entry in replayEntries {
                guard entry.wrapperEventIdentity.count == 32,
                      entry.messageIdentifier.count == 32 else {
                    throw TransportBootstrapFailure.invalidEvent
                }
                if let existing = messageByWrapperIdentity[
                    entry.wrapperEventIdentity
                ], existing != entry.messageIdentifier {
                    throw TransportBootstrapFailure.wrapperIdentityReuse
                }
                guard messageIdentifiers.insert(
                    entry.messageIdentifier
                ).inserted,
                    messageByWrapperIdentity.updateValue(
                        entry.messageIdentifier,
                        forKey: entry.wrapperEventIdentity
                    ) == nil else {
                    throw TransportBootstrapFailure.invalidEvent
                }
            }

            let (stream, continuation) = EventStream.makeStream(
                bufferingPolicy: .bufferingOldest(
                    capabilities.maximumPendingEventCount
                )
            )
            self.proof = proof
            self.binding = binding
            self.recipientEventIdentity = recipientEventIdentity
            self.capabilities = capabilities
            self.eventStream = stream
            self.continuation = continuation
            self.messageIdentifiers = messageIdentifiers
            self.messageByWrapperIdentity = messageByWrapperIdentity
        }

        @_spi(MosaicPrivateAlpha)
        public func start() async throws -> EventStream {
            guard case .idle = state else {
                throw TransportBootstrapFailure.invalidRelayAllocation
            }
            state = .running
            continuation.onTermination = { [weak self] _ in
                Task { await self?.stop() }
            }

            let request = TransportBootstrapRouteRequest(
                binding: binding,
                purpose: .inbound,
                recipientEventIdentity: recipientEventIdentity,
                relayEndpointIdentifiers: proof.relayEndpointIdentifiers
            )
            let routes: [PostManifestProvisionedRoute]
            do {
                routes = try await capabilities.provisionValidatedRoutes(
                    for: request
                )
            } catch {
                let failure: TransportBootstrapFailure
                if Task.isCancelled {
                    failure = .cancelled
                } else {
                    failure = error as? TransportBootstrapFailure
                        ?? .invalidRelayAllocation
                }
                await terminate(
                    throwing: failure
                )
                throw failure
            }

            do {
                return try await withTaskCancellationHandler {
                    guard !Task.isCancelled else {
                        throw TransportBootstrapFailure.cancelled
                    }
                    let codingLimits = try Self.codingLimits()
                    let recipientKey = try OpalCrypto.Signature.BIP340
                        .VerificationKey(
                            rawRepresentation: recipientEventIdentity
                        )
                    let filter = try OpalFusion.Mosaic.NostrNamespace
                        .RelayFilter(
                            kinds: [OpalFusion.Mosaic.NostrNamespace
                                .NIP59EnvelopeCodec.DeliveryKind.regular.rawValue],
                            recipientPublicKeys: [recipientKey],
                            since: proof.phaseStartUnixSeconds,
                            until: proof
                                .walletReservationDeadlineUnixSeconds
                        )

                    var prepared: [(
                        endpoint: String,
                        session: OpalFusion.Mosaic.NIP01RelaySession,
                        output: OpalFusion.Mosaic.NIP01RelaySession.OutputStream
                    )] = []
                    for route in routes {
                        let session = try OpalFusion.Mosaic.NIP01RelaySession(
                            connection: try TorWebSocketConnectionAdapter(
                                route.connection,
                                maximumPendingMessageCount:
                                    capabilities.maximumPendingEventCount
                            ),
                            codingLimits: codingLimits,
                            maximumPendingOutputCount:
                                capabilities.maximumPendingRelayOutputCount
                        )
                        let output = try await session.start()
                        let identifier = try OpalFusion.Mosaic.NostrNamespace
                            .SubscriptionIdentifier(
                                capabilities.makeSubscriptionIdentifier(
                                    request,
                                    route.relayEndpointIdentifier
                                )
                            )
                        try await session.subscribe(
                            try .init(identifier: identifier, filters: [filter])
                        )
                        sessions[route.relayEndpointIdentifier] = session
                        prepared.append((
                            route.relayEndpointIdentifier,
                            session,
                            output
                        ))
                    }
                    guard !Task.isCancelled else {
                        throw TransportBootstrapFailure.cancelled
                    }
                    for source in prepared {
                        tasks.append(Task { [weak self] in
                            await self?.consume(
                                source.output,
                                endpoint: source.endpoint
                            )
                        })
                    }
                    return eventStream
                } onCancel: {
                    Task {
                        for route in routes {
                            await route.connection.close()
                        }
                    }
                }
            } catch {
                for route in routes { await route.connection.close() }
                let failure: TransportBootstrapFailure
                if Task.isCancelled {
                    failure = .cancelled
                } else {
                    failure = error as? TransportBootstrapFailure
                        ?? .invalidRelayAllocation
                }
                await terminate(
                    throwing: failure
                )
                throw failure
            }
        }

        @_spi(MosaicPrivateAlpha)
        public func stop() async {
            if case .terminal = state {
                await waitForTermination()
            } else {
                await terminate(throwing: nil)
                await waitForTermination()
            }
        }

        @_spi(MosaicPrivateAlpha)
        public func waitForTermination() async {
            let tasks: [Task<Void, Never>]
            if case .terminal = state {
                tasks = terminationTasks
            } else {
                tasks = self.tasks
            }
            for task in tasks { await task.value }
        }

        private func consume(
            _ output: OpalFusion.Mosaic.NIP01RelaySession.OutputStream,
            endpoint: String
        ) async {
            do {
                for try await message in output {
                    try Task.checkCancellation()
                    switch message {
                    case let .event(_, event):
                        try accept(event)
                    case .endOfStoredEvents, .notice:
                        break
                    case .subscriptionClosed, .acknowledgement:
                        throw TransportBootstrapFailure.sourceLost
                    }
                }
                guard !Task.isCancelled else { return }
                await sourceLost(endpoint: endpoint)
            } catch is CancellationError {
                return
            } catch let failure as TransportBootstrapFailure {
                await terminate(throwing: failure)
            } catch {
                await sourceLost(endpoint: endpoint)
            }
        }

        private func accept(
            _ event: OpalFusion.Mosaic.NostrNamespace.Event
        ) throws {
            guard case .running = state else { return }
            let recipient: Data
            do {
                recipient = try OpalFusion.Mosaic.OpalMainnetAlpha
                    .PostManifestNIP59Transport.recipientEventIdentity(
                        in: event
                    )
            } catch {
                throw TransportBootstrapFailure.invalidEvent
            }
            guard recipient == recipientEventIdentity else {
                throw TransportBootstrapFailure.invalidRecipient
            }
            let wrapperIdentity = event.publicKey.rawRepresentation
            let messageIdentifier = event.identifier.rawRepresentation
            if let existing = messageByWrapperIdentity[wrapperIdentity] {
                guard existing == messageIdentifier else {
                    throw TransportBootstrapFailure.wrapperIdentityReuse
                }
                guard messageIdentifiers.contains(messageIdentifier) else {
                    throw TransportBootstrapFailure.invalidEvent
                }
                return
            }
            guard !messageIdentifiers.contains(messageIdentifier) else {
                throw TransportBootstrapFailure.invalidEvent
            }

            let canonical: Data
            do {
                canonical = try OpalFusion.Mosaic.NostrNamespace.EventCodec
                    .encode(
                        event,
                        limits: try OpalFusion.MosaicPrivateAlphaRuntime
                            .transportBootstrapCodingLimits().event
                    )
            } catch {
                throw TransportBootstrapFailure.invalidEvent
            }
            messageByWrapperIdentity[wrapperIdentity] = messageIdentifier
            guard messageIdentifiers.insert(messageIdentifier).inserted else {
                throw TransportBootstrapFailure.invalidEvent
            }
            let result = continuation.yield(
                .init(
                    canonicalEventBytes: canonical,
                    replayEntry: .init(
                        wrapperEventIdentity: wrapperIdentity,
                        messageIdentifier: messageIdentifier
                    )
                )
            )
            switch result {
            case .enqueued:
                break
            case .dropped:
                throw TransportBootstrapFailure.boundedBufferExceeded
            case .terminated:
                break
            @unknown default:
                throw TransportBootstrapFailure.boundedBufferExceeded
            }
        }

        private func sourceLost(endpoint _: String) async {
            guard case .running = state else { return }
            await terminate(throwing: .sourceLost)
        }

        private func terminate(
            throwing failure: TransportBootstrapFailure?
        ) async {
            guard case .terminal = state else {
                state = .terminal
                let tasks = tasks
                terminationTasks = tasks
                self.tasks.removeAll()
                for task in tasks { task.cancel() }
                let sessions = Array(sessions.values)
                self.sessions.removeAll()
                for session in sessions { await session.stop() }
                if let failure {
                    continuation.finish(throwing: failure)
                } else {
                    continuation.finish()
                }
                return
            }
        }

        private static func codingLimits()
            throws -> OpalFusion.Mosaic.NostrNamespace
                .RelayMessageCodingLimits {
            let limits = try OpalFusion.MosaicPrivateAlphaRuntime
                .transportBootstrapCodingLimits()
            return try .init(
                maximumFrameByteCount: 200_512,
                maximumFiltersPerRequest: 1,
                maximumValuesPerFilter: 1,
                maximumMessageStringByteCount: 200_000,
                event: limits.event
            )
        }
    }
}
#endif

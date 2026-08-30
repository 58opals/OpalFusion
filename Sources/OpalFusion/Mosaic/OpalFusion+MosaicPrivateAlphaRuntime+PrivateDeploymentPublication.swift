// OpalFusion+MosaicPrivateAlphaRuntime+PrivateDeploymentPublication.swift

#if os(macOS)
import Foundation

extension OpalFusion.MosaicPrivateAlphaRuntime {
    /// Exact signed public event durably recorded before any relay route can be requested.
    @_spi(MosaicPrivateAlpha)
    public struct PrivateDeploymentPublication: Equatable, Sendable {
        @_spi(MosaicPrivateAlpha) public let operationIdentifier: Data
        @_spi(MosaicPrivateAlpha) public let canonicalEventBytes: Data
        @_spi(MosaicPrivateAlpha) public let relayEndpointIdentifiers: [String]
        let binding: Binding
        private let gate: PrivateDeploymentPublicationGate

        init(
            binding: Binding,
            event: PrivateDeploymentEvent,
            relayEndpointIdentifiers: [String]
        ) throws {
            self.binding = binding
            canonicalEventBytes = event.canonicalEventBytes
            self.relayEndpointIdentifiers = relayEndpointIdentifiers
            gate = .init()
            operationIdentifier = try Self.makeOperationIdentifier(
                binding: binding,
                event: event,
                relayEndpointIdentifiers: relayEndpointIdentifiers
            )
        }

        /// Publishes only the recorded event over newly supplied Tor routes for the exact set.
        @_spi(MosaicPrivateAlpha)
        public consuming func publish(
            using capabilities: PrivateDeploymentRelayCapabilities
        ) async throws -> PrivateDeploymentPublicationReceipt {
            typealias Runtime = OpalFusion.MosaicPrivateAlphaRuntime
            typealias Nostr = OpalFusion.Mosaic.NostrNamespace
            guard await gate.claim() else {
                throw Runtime.Failure.invalidStateTransition
            }
            try capabilities.validateResourceLimits()
            let request = PrivateDeploymentRouteRequest(
                binding: binding,
                relayEndpointIdentifiers: relayEndpointIdentifiers
            )
            let routes = try await capabilities.provisionRoutes(request)
            guard routes.count
                    == OpalFusion.Mosaic.OpalMainnetAlpha.relayCount,
                  Set(routes.map(\.relayEndpointIdentifier))
                    == Set(relayEndpointIdentifiers),
                  Set(routes.map(\.relayEndpointIdentifier)).count
                    == routes.count,
                  Set(routes.map(\.isolationIdentifier)).count
                    == routes.count,
                  Set(routes.map {
                      ObjectIdentifier($0.connection as AnyObject)
                  }).count == routes.count else {
                for route in routes { await route.connection.close() }
                throw Runtime.Failure.invalidStateTransition
            }
            let event = try PrivateDeploymentEvent(
                canonicalEventBytes: canonicalEventBytes,
                acceptedAtUnixSeconds: 0
            ).decodeCanonicalNostrEvent()
            let eventLimits = try Nostr.EventCodingLimits(
                maximumEventJSONByteCount: 200_000,
                maximumTagCount: 1,
                maximumTagElementCount: 2,
                maximumStringByteCount: 150_000
            )
            let codingLimits = try Nostr.RelayMessageCodingLimits(
                maximumFrameByteCount: 200_512,
                maximumFiltersPerRequest: 1,
                maximumValuesPerFilter: 1,
                maximumMessageStringByteCount: 200_000,
                event: eventLimits
            )
            let maximumOutput = capabilities.maximumPendingRelayOutputCount
            let acceptedCount = await withTaskGroup(of: Bool.self) { group in
                for route in routes {
                    group.addTask {
                        let session: OpalFusion.Mosaic.NIP01RelaySession
                        do {
                            session = try .init(
                                connection: try Runtime
                                    .TorWebSocketConnectionAdapter(
                                        route.connection,
                                        maximumPendingMessageCount:
                                            maximumOutput
                                    ),
                                codingLimits: codingLimits,
                                maximumPendingOutputCount: maximumOutput
                            )
                            let output = try await session.start()
                            try await session.publish(event)
                            var wasAccepted = false
                            for try await message in output {
                                try Task.checkCancellation()
                                guard case let .acknowledgement(
                                    identifier,
                                    accepted,
                                    _
                                ) = message,
                                identifier == event.identifier else {
                                    continue
                                }
                                wasAccepted = accepted
                                break
                            }
                            await session.stop()
                            await session.waitForTermination()
                            return wasAccepted
                        } catch {
                            await route.connection.close()
                            return false
                        }
                    }
                }
                var accepted = 0
                for await result in group {
                    if result { accepted += 1 }
                    if accepted >= 2 { group.cancelAll() }
                }
                return accepted
            }
            guard acceptedCount >= 2 else {
                throw Runtime.Failure.invalidStateTransition
            }
            return .init(operationIdentifier: operationIdentifier)
        }

        @_spi(MosaicPrivateAlpha)
        public static func == (
            lhs: Self,
            rhs: Self
        ) -> Bool {
            lhs.operationIdentifier == rhs.operationIdentifier
                && lhs.canonicalEventBytes == rhs.canonicalEventBytes
                && lhs.relayEndpointIdentifiers
                    == rhs.relayEndpointIdentifiers
        }

        static func makeOperationIdentifier(
            binding: Binding,
            event: PrivateDeploymentEvent,
            relayEndpointIdentifiers: [String]
        ) throws -> Data {
            var encoder = OpalFusion.Mosaic.CanonicalEncoder()
            try encoder.writeText(
                "OpalFusion/MosaicPrivateAlpha/publication/1"
            )
            try encoder.writeFixedBytes(
                Array(binding.attemptIdentifier), byteCount: 32
            )
            try encoder.writeFixedBytes(
                Array(binding.generationIdentifier), byteCount: 32
            )
            try encoder.writeFixedBytes(
                Array(binding.materialIdentifier), byteCount: 32
            )
            try encoder.writeBytes(Array(try event.canonicalRecoveryBytes()))
            try encoder.writeVector(relayEndpointIdentifiers) {
                encoder,
                endpoint in
                try encoder.writeText(endpoint)
            }
            return RecoveryState.sha256(Data(encoder.encodedBytes))
        }
    }
}
#endif

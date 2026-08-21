// OpalFusion+MosaicPrivateAlphaRuntime+TransportBootstrapPublication+Publishing.swift

#if os(macOS)
import Foundation

extension OpalFusion.MosaicPrivateAlphaRuntime
    .TransportBootstrapPublication {
    @_spi(MosaicPrivateAlpha)
    public func publish(
        using capabilities: OpalFusion.MosaicPrivateAlphaRuntime
            .TransportBootstrapPublicationCapabilities
    ) async throws -> OpalFusion.MosaicPrivateAlphaRuntime
        .TransportBootstrapPublicationReceipt {
        typealias Runtime = OpalFusion.MosaicPrivateAlphaRuntime
        typealias Nostr = OpalFusion.Mosaic.NostrNamespace

        try capabilities.relays.validateResourceLimits()
        let priorAccepted = try await durableAcceptedEndpoints(
            using: capabilities
        )
        if priorAccepted.count >= OpalFusion.Mosaic.OpalMainnetAlpha
            .relayAcceptanceQuorum {
            return .init(
                operationIdentifier: operationIdentifier,
                acceptedRelayEndpointIdentifiers: priorAccepted
            )
        }
        let endpointsToPublish = relayEndpointIdentifiers.filter {
            !priorAccepted.contains($0)
        }
        let request = Runtime.TransportBootstrapRouteRequest(
            binding: binding,
            purpose: .outbound,
            recipientEventIdentity: recipientEventIdentity,
            relayEndpointIdentifiers: endpointsToPublish
        )
        let routes: [Runtime.PostManifestProvisionedRoute]
        do {
            routes = try await capabilities.relays.provisionValidatedRoutes(
                for: request
            )
        } catch {
            if Task.isCancelled {
                throw Runtime.TransportBootstrapFailure.cancelled
            }
            throw error
        }
        guard !Task.isCancelled else {
            for route in routes { await route.connection.close() }
            throw Runtime.TransportBootstrapFailure.cancelled
        }

        let limits = try Runtime.transportBootstrapCodingLimits()
        let event: Nostr.Event
        do {
            event = try Nostr.EventCodec.decode(
                canonicalEventBytes,
                limits: limits.event
            )
        } catch {
            for route in routes { await route.connection.close() }
            throw Runtime.TransportBootstrapFailure.invalidEvent
        }
        let codingLimits = try Nostr.RelayMessageCodingLimits(
            maximumFrameByteCount: max(
                200_512,
                OpalFusion.Mosaic.OpalMainnetAlpha
                    .nip59MaximumPublicationFrameByteCount
            ),
            maximumFiltersPerRequest: 1,
            maximumValuesPerFilter: 1,
            maximumMessageStringByteCount: 200_000,
            event: limits.event
        )

        await withTaskCancellationHandler {
            await withTaskGroup(of: Void.self) { group in
                for route in routes {
                    group.addTask {
                        let endpoint = route.relayEndpointIdentifier
                        var session: OpalFusion.Mosaic.NIP01RelaySession?
                        do {
                            let startedSession = try OpalFusion.Mosaic
                                .NIP01RelaySession(
                                    connection: Runtime
                                        .TorWebSocketConnectionAdapter(
                                            route.connection
                                ),
                            codingLimits: codingLimits,
                            maximumPendingOutputCount:
                                    capabilities.relays
                                        .maximumPendingRelayOutputCount
                                )
                            session = startedSession
                            let output = try await startedSession.start()
                            try await startedSession.publish(event)
                            var accepted = false
                            for try await message in output {
                                try Task.checkCancellation()
                                guard case let .acknowledgement(
                                    identifier,
                                    wasAccepted,
                                    _
                                ) = message,
                                identifier == event.identifier else {
                                    continue
                                }
                                accepted = wasAccepted
                                break
                            }
                            await startedSession.stop()
                            await startedSession.waitForTermination()
                            if accepted {
                                try await capabilities
                                    .recordAcceptedRelayEndpointIdentifier(
                                        operationIdentifier,
                                        endpoint
                                    )
                            }
                        } catch {
                            if let session {
                                await session.stop()
                                await session.waitForTermination()
                            } else {
                                await route.connection.close()
                            }
                            return
                        }
                    }
                }
                for await _ in group {}
            }
        } onCancel: {
            Task {
                for route in routes {
                    await route.connection.close()
                }
            }
        }
        guard !Task.isCancelled else {
            throw Runtime.TransportBootstrapFailure.cancelled
        }
        let accepted = try await durableAcceptedEndpoints(
            using: capabilities
        )
        guard accepted.count >= 2 else {
            throw Runtime.TransportBootstrapFailure.publicationRejected
        }
        return .init(
            operationIdentifier: operationIdentifier,
            acceptedRelayEndpointIdentifiers: accepted
        )
    }

    private func durableAcceptedEndpoints(
        using capabilities: OpalFusion.MosaicPrivateAlphaRuntime
            .TransportBootstrapPublicationCapabilities
    ) async throws -> [String] {
        let accepted: [String]
        do {
            accepted = try await capabilities
                .loadAcceptedRelayEndpointIdentifiers(operationIdentifier)
        } catch {
            if Task.isCancelled {
                throw OpalFusion.MosaicPrivateAlphaRuntime
                    .TransportBootstrapFailure.cancelled
            }
            throw error
        }
        guard !Task.isCancelled else {
            throw OpalFusion.MosaicPrivateAlphaRuntime
                .TransportBootstrapFailure.cancelled
        }
        guard Set(accepted).count == accepted.count,
              Set(accepted).isSubset(
                  of: Set(relayEndpointIdentifiers)
              ) else {
            throw OpalFusion.MosaicPrivateAlphaRuntime
                .TransportBootstrapFailure.invalidRelayAllocation
        }
        return accepted.sorted()
    }
}
#endif

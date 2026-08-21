// OpalFusion+MosaicPrivateAlphaRuntime+TransportBootstrapRelayCapabilities.swift

#if os(macOS)
extension OpalFusion.MosaicPrivateAlphaRuntime {
    /// App-owned exact-route provisioning for the bootstrap inbox and publisher.
    @_spi(MosaicPrivateAlpha)
    public struct TransportBootstrapRelayCapabilities: Sendable {
        static let maximumAllowedPendingCount = 4_096

        let provisionRoutes: @Sendable (TransportBootstrapRouteRequest)
            async throws -> [PostManifestProvisionedRoute]
        let makeSubscriptionIdentifier: @Sendable (
            TransportBootstrapRouteRequest,
            String
        ) throws -> String
        let maximumPendingEventCount: Int
        let maximumPendingRelayOutputCount: Int

        @_spi(MosaicPrivateAlpha)
        public init(
            provisionRoutes: @escaping @Sendable (
                TransportBootstrapRouteRequest
            ) async throws -> [PostManifestProvisionedRoute],
            makeSubscriptionIdentifier: @escaping @Sendable (
                TransportBootstrapRouteRequest,
                String
            ) throws -> String,
            maximumPendingEventCount: Int = 256,
            maximumPendingRelayOutputCount: Int = 64
        ) {
            self.provisionRoutes = provisionRoutes
            self.makeSubscriptionIdentifier = makeSubscriptionIdentifier
            self.maximumPendingEventCount = maximumPendingEventCount
            self.maximumPendingRelayOutputCount =
                maximumPendingRelayOutputCount
        }

        func validateResourceLimits() throws {
            guard (1 ... Self.maximumAllowedPendingCount)
                    .contains(maximumPendingEventCount),
                  (1 ... Self.maximumAllowedPendingCount)
                    .contains(maximumPendingRelayOutputCount) else {
                throw TransportBootstrapFailure.invalidRelayAllocation
            }
        }

        func provisionValidatedRoutes(
            for request: TransportBootstrapRouteRequest
        ) async throws -> [PostManifestProvisionedRoute] {
            let routes = try await provisionRoutes(request)
            let endpoints = routes.map(\.relayEndpointIdentifier)
            guard !request.relayEndpointIdentifiers.isEmpty,
                  request.relayEndpointIdentifiers.count
                    <= OpalFusion.Mosaic.OpalMainnetAlpha.relayCount,
                  routes.count == request.relayEndpointIdentifiers.count,
                  Set(endpoints) == Set(
                      request.relayEndpointIdentifiers
                  ),
                  Set(endpoints).count == routes.count,
                  Set(routes.map(\.isolationIdentifier)).count
                    == routes.count,
                  Set(routes.map {
                      ObjectIdentifier($0.connection as AnyObject)
                  }).count == routes.count else {
                for route in routes { await route.connection.close() }
                throw TransportBootstrapFailure.invalidRelayAllocation
            }
            return routes
        }
    }
}
#endif

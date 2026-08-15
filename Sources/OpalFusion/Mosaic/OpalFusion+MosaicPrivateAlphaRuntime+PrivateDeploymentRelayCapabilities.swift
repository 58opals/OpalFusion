// OpalFusion+MosaicPrivateAlphaRuntime+PrivateDeploymentRelayCapabilities.swift

#if os(macOS)
extension OpalFusion.MosaicPrivateAlphaRuntime {
    /// App-provisioned Tor routes for Fusion's exact proof-derived public relay request.
    @_spi(MosaicPrivateAlpha)
    public struct PrivateDeploymentRelayCapabilities: Sendable {
        static let maximumAllowedPendingRelayOutputCount = 4_096

        let provisionRoutes: @Sendable (PrivateDeploymentRouteRequest)
            async throws -> [PostManifestProvisionedRoute]
        let maximumPendingRelayOutputCount: Int

        @_spi(MosaicPrivateAlpha)
        public init(
            provisionRoutes: @escaping @Sendable (
                PrivateDeploymentRouteRequest
            ) async throws -> [PostManifestProvisionedRoute],
            maximumPendingRelayOutputCount: Int = 64
        ) {
            self.provisionRoutes = provisionRoutes
            self.maximumPendingRelayOutputCount =
                maximumPendingRelayOutputCount
        }

        func validateResourceLimits() throws {
            guard (1 ... Self.maximumAllowedPendingRelayOutputCount)
                    .contains(maximumPendingRelayOutputCount) else {
                throw Failure.invalidStateTransition
            }
        }
    }
}
#endif

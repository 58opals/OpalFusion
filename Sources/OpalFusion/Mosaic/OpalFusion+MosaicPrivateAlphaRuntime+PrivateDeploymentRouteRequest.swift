// OpalFusion+MosaicPrivateAlphaRuntime+PrivateDeploymentRouteRequest.swift

#if os(macOS)
extension OpalFusion.MosaicPrivateAlphaRuntime {
    /// Package-derived public relay-set request with no recipient-routing identity.
    @_spi(MosaicPrivateAlpha)
    public struct PrivateDeploymentRouteRequest: Equatable, Sendable {
        @_spi(MosaicPrivateAlpha) public let binding: Binding
        @_spi(MosaicPrivateAlpha) public let relayEndpointIdentifiers: [String]

        init(binding: Binding, relayEndpointIdentifiers: [String]) {
            self.binding = binding
            self.relayEndpointIdentifiers = relayEndpointIdentifiers
        }
    }
}
#endif

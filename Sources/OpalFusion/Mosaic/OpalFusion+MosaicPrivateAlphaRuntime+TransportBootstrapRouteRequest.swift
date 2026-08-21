// OpalFusion+MosaicPrivateAlphaRuntime+TransportBootstrapRouteRequest.swift

#if os(macOS)
import Foundation

extension OpalFusion.MosaicPrivateAlphaRuntime {
    @_spi(MosaicPrivateAlpha)
    public struct TransportBootstrapRouteRequest: Sendable, Equatable {
        @_spi(MosaicPrivateAlpha) public let binding: Binding
        @_spi(MosaicPrivateAlpha) public let purpose:
            TransportBootstrapRoutePurpose
        @_spi(MosaicPrivateAlpha) public let recipientEventIdentity: Data
        @_spi(MosaicPrivateAlpha) public let relayEndpointIdentifiers: [String]

        init(
            binding: Binding,
            purpose: TransportBootstrapRoutePurpose,
            recipientEventIdentity: Data,
            relayEndpointIdentifiers: [String]
        ) {
            self.binding = binding
            self.purpose = purpose
            self.recipientEventIdentity = recipientEventIdentity
            self.relayEndpointIdentifiers = relayEndpointIdentifiers
        }
    }
}
#endif

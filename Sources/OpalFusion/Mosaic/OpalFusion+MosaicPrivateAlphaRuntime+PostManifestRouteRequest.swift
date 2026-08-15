// OpalFusion+MosaicPrivateAlphaRuntime+PostManifestRouteRequest.swift

#if os(macOS)
import Foundation

extension OpalFusion.MosaicPrivateAlphaRuntime {
    /// Package-derived request for isolated Tor routes to the exact manifest relay set.
    @_spi(MosaicPrivateAlpha)
    public struct PostManifestRouteRequest: Sendable, Equatable {
        @_spi(MosaicPrivateAlpha) public let binding: Binding
        @_spi(MosaicPrivateAlpha) public let purpose:
            PostManifestRoutePurpose
        @_spi(MosaicPrivateAlpha) public let recipientEventIdentity: Data
        @_spi(MosaicPrivateAlpha) public let relayEndpointIdentifiers: [String]

        init(
            binding: Binding,
            purpose: PostManifestRoutePurpose,
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

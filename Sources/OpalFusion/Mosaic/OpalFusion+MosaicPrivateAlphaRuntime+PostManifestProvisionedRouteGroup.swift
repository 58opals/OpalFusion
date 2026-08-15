// OpalFusion+MosaicPrivateAlphaRuntime+PostManifestProvisionedRouteGroup.swift

#if os(macOS)
import Foundation

extension OpalFusion.MosaicPrivateAlphaRuntime {
    @_spi(MosaicPrivateAlpha)
    public struct PostManifestProvisionedRouteGroup: Sendable {
        @_spi(MosaicPrivateAlpha) public let recipientEventIdentity: Data
        @_spi(MosaicPrivateAlpha) public let routes:
            [PostManifestProvisionedRoute]

        @_spi(MosaicPrivateAlpha)
        public init(
            recipientEventIdentity: Data,
            routes: [PostManifestProvisionedRoute]
        ) {
            self.recipientEventIdentity = recipientEventIdentity
            self.routes = routes
        }
    }
}
#endif

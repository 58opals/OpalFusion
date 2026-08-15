// OpalFusion+MosaicPrivateAlphaRuntime+PostManifestProvisionedRoute.swift

#if os(macOS)
import Foundation

extension OpalFusion.MosaicPrivateAlphaRuntime {
    /// One endpoint-bound Tor connection with app-attested circuit isolation identity.
    @_spi(MosaicPrivateAlpha)
    public struct PostManifestProvisionedRoute: Sendable {
        @_spi(MosaicPrivateAlpha) public let relayEndpointIdentifier: String
        @_spi(MosaicPrivateAlpha) public let connection:
            any OpalFusion.MosaicPrivateAlphaRuntime.TorWebSocketConnection
        @_spi(MosaicPrivateAlpha) public let isolationIdentifier: UUID

        @_spi(MosaicPrivateAlpha)
        public init(
            relayEndpointIdentifier: String,
            connection: any OpalFusion.MosaicPrivateAlphaRuntime
                .TorWebSocketConnection,
            isolationIdentifier: UUID
        ) {
            self.relayEndpointIdentifier = relayEndpointIdentifier
            self.connection = connection
            self.isolationIdentifier = isolationIdentifier
        }
    }
}
#endif

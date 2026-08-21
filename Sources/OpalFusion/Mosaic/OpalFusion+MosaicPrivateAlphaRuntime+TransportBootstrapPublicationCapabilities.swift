// OpalFusion+MosaicPrivateAlphaRuntime+TransportBootstrapPublicationCapabilities.swift

#if os(macOS)
import Foundation

extension OpalFusion.MosaicPrivateAlphaRuntime {
    /// App-owned routes plus atomic durable acceptance recording for bootstrap publication.
    @_spi(MosaicPrivateAlpha)
    public struct TransportBootstrapPublicationCapabilities: Sendable {
        let relays: TransportBootstrapRelayCapabilities
        let loadAcceptedRelayEndpointIdentifiers: @Sendable (Data)
            async throws -> [String]
        let recordAcceptedRelayEndpointIdentifier: @Sendable (
            Data,
            String
        ) async throws -> Void

        @_spi(MosaicPrivateAlpha)
        public init(
            relays: TransportBootstrapRelayCapabilities,
            loadAcceptedRelayEndpointIdentifiers: @escaping @Sendable (
                Data
            ) async throws -> [String],
            recordAcceptedRelayEndpointIdentifier: @escaping @Sendable (
                Data,
                String
            ) async throws -> Void
        ) {
            self.relays = relays
            self.loadAcceptedRelayEndpointIdentifiers =
                loadAcceptedRelayEndpointIdentifiers
            self.recordAcceptedRelayEndpointIdentifier =
                recordAcceptedRelayEndpointIdentifier
        }
    }
}
#endif

// OpalFusion+MosaicPrivateAlphaRuntime+TransportBootstrapPublicationReceipt.swift

#if os(macOS)
import Foundation

extension OpalFusion.MosaicPrivateAlphaRuntime {
    @_spi(MosaicPrivateAlpha)
    public struct TransportBootstrapPublicationReceipt:
        Sendable,
        Equatable
    {
        @_spi(MosaicPrivateAlpha) public let operationIdentifier: Data
        @_spi(MosaicPrivateAlpha) public let acceptedRelayEndpointIdentifiers:
            [String]

        init(
            operationIdentifier: Data,
            acceptedRelayEndpointIdentifiers: [String]
        ) {
            self.operationIdentifier = operationIdentifier
            self.acceptedRelayEndpointIdentifiers =
                acceptedRelayEndpointIdentifiers
        }
    }
}
#endif

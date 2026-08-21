// OpalFusion+MosaicPrivateAlphaRuntime+PrivateDeploymentContextDocuments.swift

#if os(macOS)
import Foundation

extension OpalFusion.MosaicPrivateAlphaRuntime {
    /// Canonical package-owned discovery context prepared from application policy.
    @_spi(MosaicPrivateAlpha)
    public struct PrivateDeploymentContextDocuments: Sendable, Equatable {
        @_spi(MosaicPrivateAlpha) public let opaquePoolDocument: Data
        @_spi(MosaicPrivateAlpha) public let relaySetDocument: Data
        @_spi(MosaicPrivateAlpha) public let relaySetDigest: Data
        @_spi(MosaicPrivateAlpha) public let relayEndpointIdentifiers: [String]

        init(
            opaquePoolDocument: Data,
            relaySetDocument: Data,
            relaySetDigest: Data,
            relayEndpointIdentifiers: [String]
        ) {
            self.opaquePoolDocument = opaquePoolDocument
            self.relaySetDocument = relaySetDocument
            self.relaySetDigest = relaySetDigest
            self.relayEndpointIdentifiers = relayEndpointIdentifiers
        }
    }
}
#endif

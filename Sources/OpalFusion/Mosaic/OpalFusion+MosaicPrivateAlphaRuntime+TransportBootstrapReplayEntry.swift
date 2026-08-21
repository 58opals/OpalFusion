// OpalFusion+MosaicPrivateAlphaRuntime+TransportBootstrapReplayEntry.swift

#if os(macOS)
import Foundation

extension OpalFusion.MosaicPrivateAlphaRuntime {
    /// App-persistable replay and wrapper-freshness fact for deterministic reconnect.
    @_spi(MosaicPrivateAlpha)
    public struct TransportBootstrapReplayEntry:
        Sendable,
        Hashable
    {
        @_spi(MosaicPrivateAlpha) public let wrapperEventIdentity: Data
        @_spi(MosaicPrivateAlpha) public let messageIdentifier: Data

        @_spi(MosaicPrivateAlpha)
        public init(
            wrapperEventIdentity: Data,
            messageIdentifier: Data
        ) {
            self.wrapperEventIdentity = wrapperEventIdentity
            self.messageIdentifier = messageIdentifier
        }
    }
}
#endif

// OpalFusion+MosaicPrivateAlphaRuntime+TransportBootstrapInboundEvent.swift

#if os(macOS)
import Foundation

extension OpalFusion.MosaicPrivateAlphaRuntime {
    /// One canonical relay event after recipient and replay preflight.
    @_spi(MosaicPrivateAlpha)
    public struct TransportBootstrapInboundEvent: Sendable, Equatable {
        @_spi(MosaicPrivateAlpha) public let canonicalEventBytes: Data
        @_spi(MosaicPrivateAlpha) public let replayEntry:
            TransportBootstrapReplayEntry

        init(
            canonicalEventBytes: Data,
            replayEntry: TransportBootstrapReplayEntry
        ) {
            self.canonicalEventBytes = canonicalEventBytes
            self.replayEntry = replayEntry
        }
    }
}
#endif

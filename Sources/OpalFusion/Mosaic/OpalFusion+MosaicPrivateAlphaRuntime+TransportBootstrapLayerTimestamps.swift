// OpalFusion+MosaicPrivateAlphaRuntime+TransportBootstrapLayerTimestamps.swift

#if os(macOS)
extension OpalFusion.MosaicPrivateAlphaRuntime {
    /// Caller-owned NIP-59 cover timestamps for one bootstrap wrapper.
    @_spi(MosaicPrivateAlpha)
    public struct TransportBootstrapLayerTimestamps: Sendable, Equatable {
        @_spi(MosaicPrivateAlpha) public let currentUnixSeconds: UInt64
        @_spi(MosaicPrivateAlpha) public let rumorCreatedAt: UInt64
        @_spi(MosaicPrivateAlpha) public let sealCreatedAt: UInt64
        @_spi(MosaicPrivateAlpha) public let giftWrapCreatedAt: UInt64

        @_spi(MosaicPrivateAlpha)
        public init(
            currentUnixSeconds: UInt64,
            rumorCreatedAt: UInt64,
            sealCreatedAt: UInt64,
            giftWrapCreatedAt: UInt64
        ) {
            self.currentUnixSeconds = currentUnixSeconds
            self.rumorCreatedAt = rumorCreatedAt
            self.sealCreatedAt = sealCreatedAt
            self.giftWrapCreatedAt = giftWrapCreatedAt
        }
    }
}
#endif

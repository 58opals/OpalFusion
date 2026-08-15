// OpalFusion+MosaicPrivateAlphaRuntime+PostManifestLayerTimestamps.swift

#if os(macOS)
extension OpalFusion.MosaicPrivateAlphaRuntime {
    @_spi(MosaicPrivateAlpha)
    public struct PostManifestLayerTimestamps: Sendable, Equatable {
        @_spi(MosaicPrivateAlpha) public let phaseStartUnixSeconds: UInt64
        @_spi(MosaicPrivateAlpha) public let currentUnixSeconds: UInt64
        @_spi(MosaicPrivateAlpha) public let sealCreatedAt: UInt64
        @_spi(MosaicPrivateAlpha) public let giftWrapCreatedAt: UInt64

        @_spi(MosaicPrivateAlpha)
        public init(
            phaseStartUnixSeconds: UInt64,
            currentUnixSeconds: UInt64,
            sealCreatedAt: UInt64,
            giftWrapCreatedAt: UInt64
        ) {
            self.phaseStartUnixSeconds = phaseStartUnixSeconds
            self.currentUnixSeconds = currentUnixSeconds
            self.sealCreatedAt = sealCreatedAt
            self.giftWrapCreatedAt = giftWrapCreatedAt
        }
    }
}
#endif

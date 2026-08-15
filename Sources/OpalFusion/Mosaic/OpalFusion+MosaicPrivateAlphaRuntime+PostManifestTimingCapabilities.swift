// OpalFusion+MosaicPrivateAlphaRuntime+PostManifestTimingCapabilities.swift

#if os(macOS)
extension OpalFusion.MosaicPrivateAlphaRuntime {
    /// App-owned clock policy consumed only for package-derived publication requests.
    @_spi(MosaicPrivateAlpha)
    public struct PostManifestTimingCapabilities: Sendable {
        let currentUnixSeconds: @Sendable () -> UInt64
        let makeLayerTimestamps: @Sendable (
            PostManifestTimestampRequest
        ) throws -> PostManifestLayerTimestamps

        @_spi(MosaicPrivateAlpha)
        public init(
            currentUnixSeconds: @escaping @Sendable () -> UInt64,
            makeLayerTimestamps: @escaping @Sendable (
                PostManifestTimestampRequest
            ) throws -> PostManifestLayerTimestamps
        ) {
            self.currentUnixSeconds = currentUnixSeconds
            self.makeLayerTimestamps = makeLayerTimestamps
        }
    }
}
#endif

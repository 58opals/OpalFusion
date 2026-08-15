// OpalFusion+MosaicPrivateAlphaRuntime+PostManifestExecutionOutcomeKind.swift

#if os(macOS)
extension OpalFusion.MosaicPrivateAlphaRuntime {
    @_spi(MosaicPrivateAlpha)
    public enum PostManifestExecutionOutcomeKind: Sendable, Equatable {
        case completed
        case aborted
        case failed
        case recoveryRequired
        case transportFailed
    }
}
#endif

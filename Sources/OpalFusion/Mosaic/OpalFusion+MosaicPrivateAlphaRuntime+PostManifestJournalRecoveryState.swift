// OpalFusion+MosaicPrivateAlphaRuntime+PostManifestJournalRecoveryState.swift

#if os(macOS)
extension OpalFusion.MosaicPrivateAlphaRuntime {
    enum PostManifestJournalRecoveryState: UInt8, Equatable, Sendable {
        case uninitialized = 0
        case initialized = 1
    }
}
#endif

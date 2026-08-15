// OpalFusion+MosaicPrivateAlphaRuntime+PostManifestPublicationKind.swift

#if os(macOS)
extension OpalFusion.MosaicPrivateAlphaRuntime {
    @_spi(MosaicPrivateAlpha)
    public enum PostManifestPublicationKind: Sendable, Equatable {
        case playerCommit
        case anonymousComponents
        case preSignAcknowledgement
        case localBCHSignatures
        case conductorAggregate
    }
}
#endif

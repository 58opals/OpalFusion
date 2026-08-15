// OpalFusion+MosaicPrivateAlphaRuntime+PostManifestRoutePurpose.swift

#if os(macOS)
extension OpalFusion.MosaicPrivateAlphaRuntime {
    @_spi(MosaicPrivateAlpha)
    public enum PostManifestRoutePurpose: Sendable, Hashable {
        case inboundControl
        case inboundAnonymous
        case outboundControl
        case outboundAnonymousComponents
        case outboundAnonymousBCHSignatures
    }
}
#endif

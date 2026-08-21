// OpalFusion+MosaicPrivateAlphaRuntime+TransportBootstrapRoutePurpose.swift

#if os(macOS)
extension OpalFusion.MosaicPrivateAlphaRuntime {
    @_spi(MosaicPrivateAlpha)
    public enum TransportBootstrapRoutePurpose: Sendable, Equatable {
        case inbound
        case outbound
    }
}
#endif

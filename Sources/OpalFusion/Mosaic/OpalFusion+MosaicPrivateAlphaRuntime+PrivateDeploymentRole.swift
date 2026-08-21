// OpalFusion+MosaicPrivateAlphaRuntime+PrivateDeploymentRole.swift

#if os(macOS)
extension OpalFusion.MosaicPrivateAlphaRuntime {
    /// Authenticated role selected for one control identity after role election.
    @_spi(MosaicPrivateAlpha)
    public enum PrivateDeploymentRole: Sendable, Equatable {
        case contributor
        case conductor
    }
}
#endif

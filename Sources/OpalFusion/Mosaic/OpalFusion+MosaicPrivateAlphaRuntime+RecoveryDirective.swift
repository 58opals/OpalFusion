// OpalFusion+MosaicPrivateAlphaRuntime+RecoveryDirective.swift

#if os(macOS)
extension OpalFusion.MosaicPrivateAlphaRuntime {
    /// The only permitted continuation after exact snapshot restoration.
    @_spi(MosaicPrivateAlpha)
    public enum RecoveryDirective: Equatable, Sendable {
        case resumePrivateDeployment(PrivateDeploymentContinuation)
        case validatePostManifestTerminal(PrivateDeploymentContinuation)
        case publishPrivateDeployment(PrivateDeploymentPublication)
        case terminal(TerminalDisposition)
    }
}
#endif

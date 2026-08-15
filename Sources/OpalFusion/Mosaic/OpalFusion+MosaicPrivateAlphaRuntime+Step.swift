// OpalFusion+MosaicPrivateAlphaRuntime+Step.swift

#if os(macOS)
extension OpalFusion.MosaicPrivateAlphaRuntime {
    @_spi(MosaicPrivateAlpha)
    public enum Step: Equatable, Sendable {
        case persist(RecoveryTransition)
        case publishPrivateDeployment(PrivateDeploymentPublication)
        case recover(RecoveryDirective)
        case ignoredDuplicate(Phase)
        case awaitingPreManifestAbortSignature(Phase)
        case awaitingInput(Phase)
        case terminal(TerminalDisposition)
    }
}
#endif

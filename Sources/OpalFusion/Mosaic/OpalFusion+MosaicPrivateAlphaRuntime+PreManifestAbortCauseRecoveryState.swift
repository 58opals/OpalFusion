// OpalFusion+MosaicPrivateAlphaRuntime+PreManifestAbortCauseRecoveryState.swift

#if os(macOS)
extension OpalFusion.MosaicPrivateAlphaRuntime {
    enum PreManifestAbortCauseRecoveryState: Equatable, Sendable {
        case none
        case equivocation(PrivateDeploymentEvent)
        case invalidAuthenticatedMessage(PrivateDeploymentEvent)
    }
}
#endif

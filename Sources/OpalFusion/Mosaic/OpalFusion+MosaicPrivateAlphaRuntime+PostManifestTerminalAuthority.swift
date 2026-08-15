// OpalFusion+MosaicPrivateAlphaRuntime+PostManifestTerminalAuthority.swift

#if os(macOS)
extension OpalFusion.MosaicPrivateAlphaRuntime {
    enum PostManifestTerminalAuthority: Sendable {
        case completion(
            OpalFusion.Mosaic.OpalMainnetAlpha
                .PrivateDeploymentCompletionValidation
        )
        case abort(
            OpalFusion.Mosaic.OpalMainnetAlpha
                .PrivateDeploymentAbortAuthority,
            reason: OpalFusion.Mosaic.Attempt.AbortReason
        )
        case unavailable
    }
}
#endif

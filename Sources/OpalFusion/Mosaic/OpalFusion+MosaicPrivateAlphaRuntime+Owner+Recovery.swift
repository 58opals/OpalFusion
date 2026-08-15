// OpalFusion+MosaicPrivateAlphaRuntime+Owner+Recovery.swift

#if os(macOS)
extension OpalFusion.MosaicPrivateAlphaRuntime.Owner {
    func recoveryDirective() throws
        -> OpalFusion.MosaicPrivateAlphaRuntime.RecoveryDirective {
        typealias Runtime = OpalFusion.MosaicPrivateAlphaRuntime
        if let disposition = state.terminalDisposition() {
            if case .validated = state.manifestState,
               !postManifestTerminalReadbackValidated {
                let proof = try Runtime.restorePrivateDeploymentProof(
                    discoveryEpochStartUnixSeconds:
                        state.discoveryEpochStartUnixSeconds,
                    canonicalDocuments: state.preManifestDocuments
                )
                return .validatePostManifestTerminal(.init(
                    binding: state.binding,
                    phase: state.phase,
                    proof: proof
                ))
            }
            return .terminal(disposition)
        }
        guard state.publicationState == .none else {
            throw Runtime.Failure.invalidStateTransition
        }
        switch state.manifestState {
        case .forming:
            return .resumePrivateDeployment(.init(
                binding: state.binding,
                phase: state.phase,
                proof: nil
            ))
        case .validated:
            let proof = try Runtime.restorePrivateDeploymentProof(
                discoveryEpochStartUnixSeconds:
                    state.discoveryEpochStartUnixSeconds,
                canonicalDocuments: state.preManifestDocuments
            )
            return .resumePrivateDeployment(.init(
                binding: state.binding,
                phase: state.phase,
                proof: proof
            ))
        }
    }
}
#endif

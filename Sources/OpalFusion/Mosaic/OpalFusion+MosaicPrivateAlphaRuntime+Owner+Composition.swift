// OpalFusion+MosaicPrivateAlphaRuntime+Owner+Composition.swift

#if os(macOS)
import Foundation

extension OpalFusion.MosaicPrivateAlphaRuntime.Owner {
    /// Initializes both exact empty Fusion journals before any Tor route can be requested.
    @_spi(MosaicPrivateAlpha)
    public func preparePostManifestRuntime(
        localControlIdentity: Data,
        capabilities: OpalFusion.MosaicPrivateAlphaRuntime
            .PostManifestRuntimeCapabilities
    ) throws -> OpalFusion.MosaicPrivateAlphaRuntime.Step {
        typealias Runtime = OpalFusion.MosaicPrivateAlphaRuntime
        guard !loadedRecoveryNeedsDirective,
              state.postManifestJournalState == .uninitialized else {
            throw Runtime.Failure.invalidStateTransition
        }
        let construction = try derivePostManifestConstruction(
            localControlIdentity: localControlIdentity
        )
        try construction.initializeJournalSnapshots(capabilities)
        return try stage { candidate in
            candidate.postManifestJournalState = .initialized
        }
    }

    /// Derives the existing driver bootstrap from the installed private proof and exact binding.
    @_spi(MosaicPrivateAlpha)
    public func makePostManifestConstruction(
        localControlIdentity: Data
    ) throws -> OpalFusion.MosaicPrivateAlphaRuntime.PostManifestConstruction {
        typealias Runtime = OpalFusion.MosaicPrivateAlphaRuntime
        guard !loadedRecoveryNeedsDirective,
              !postManifestConstructionIssued,
              state.postManifestJournalState == .initialized,
              !state.phase.isPreManifest,
              localControlIdentity.count == 32 else {
            throw Runtime.Failure.invalidStateTransition
        }
        let construction = try derivePostManifestConstruction(
            localControlIdentity: localControlIdentity
        )
        postManifestConstructionIssued = true
        return construction
    }

    private func derivePostManifestConstruction(
        localControlIdentity: Data
    ) throws -> OpalFusion.MosaicPrivateAlphaRuntime.PostManifestConstruction {
        typealias Runtime = OpalFusion.MosaicPrivateAlphaRuntime
        guard !state.phase.isPreManifest,
              localControlIdentity.count == 32 else {
            throw Runtime.Failure.invalidStateTransition
        }
        let proof = try Runtime.restorePrivateDeploymentProof(
            discoveryEpochStartUnixSeconds:
                state.discoveryEpochStartUnixSeconds,
            canonicalDocuments: state.preManifestDocuments
        )
        let identity = OpalFusion.Mosaic.Attempt.ControlIdentity(
            validatedBytes: Array(localControlIdentity)
        )
        guard let member = proof.completeManifest.core.roster.members
            .first(where: { $0.controlIdentity == identity }) else {
            throw Runtime.Failure.localControlIdentityNotInPrivateDeployment
        }
        let proposal = try OpalFusion.Mosaic.OpalMainnetAlpha
            .ManifestProposalValidation(
                validating: proof.proposalValidation.manifest.core,
                against: proof.proposalValidation.expectedContext
            )
        let terminalEvidence: Runtime.PostManifestTerminalEvidence?
        if case let .authorized(reason, evidenceBytes) = state.terminalState {
            terminalEvidence = try state
                .validatePostManifestTerminalEvidence(
                    evidenceBytes,
                    expectedReason: reason
                )
            guard terminalEvidence?.localControlIdentity
                    == localControlIdentity else {
                throw Runtime.Failure.localControlIdentityNotInPrivateDeployment
            }
        } else {
            terminalEvidence = nil
        }
        let bootstrap = OpalFusion.Mosaic.OpalMainnetAlpha
            .PostManifestRuntimeDriver.Bootstrap(
                validatedAttempt: proof.validatedAttempt,
                attemptIdentifier: .init(
                    validatedBytes: Array(state.binding.attemptIdentifier)
                ),
                generationIdentifier: .init(
                    opaqueBytes: Array(state.binding.generationIdentifier)
                ),
                materialIdentifier: .init(
                    opaqueBytes: Array(state.binding.materialIdentifier)
                ),
                localControlIdentity: identity,
                proposalValidation: proposal
            )
        return .init(
            binding: state.binding,
            localControlIdentity: localControlIdentity,
            bootstrap: bootstrap,
            completeManifest: proof.completeManifest,
            privateManifest: proof.proposalValidation.manifest,
            relaySet: try OpalFusion.Mosaic.OpalMainnetAlpha
                .RelaySetDocument.decode(
                    from: Array(proof.canonicalDocuments[1])
                ),
            recoveredTerminalEvidence: terminalEvidence,
            isConductor: member.role == .conductor
        )
    }
}
#endif

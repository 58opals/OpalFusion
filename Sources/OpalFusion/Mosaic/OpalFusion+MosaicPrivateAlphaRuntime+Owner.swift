// OpalFusion+MosaicPrivateAlphaRuntime+Owner.swift

#if os(macOS)
import Foundation

extension OpalFusion.MosaicPrivateAlphaRuntime {
    /// Sole transition and terminal-material owner for one exact attempt generation.
    @_spi(MosaicPrivateAlpha)
    public actor Owner {
        var state: RecoveryState
        var durableSnapshot: Data?
        var stagedState: RecoveryState?
        var stagedTransition: RecoveryTransition?
        var cachedFormationState: PrivateDeploymentFormationState?
        var stagedFormationState: PrivateDeploymentFormationState?
        var cachedAttempt: OpalFusion.Mosaic.Attempt?
        var stagedAttempt: OpalFusion.Mosaic.Attempt?
        var loadedRecoveryNeedsDirective: Bool
        var terminalEvidenceClaimed = false
        var issuedPublicationIdentifier: Data?
        var postManifestConstructionIssued = false
        var postManifestTerminalReadbackValidated: Bool

        @_spi(MosaicPrivateAlpha)
        public init(claiming freshAttempt: consuming FreshAttempt) throws {
            let initialState = freshAttempt.state
            let transition = try Self.makeTransition(
                expectedSnapshot: nil,
                replacementState: initialState
            )
            state = initialState
            durableSnapshot = nil
            stagedState = initialState
            stagedTransition = transition
            cachedFormationState = .uninitialized
            stagedFormationState = .uninitialized
            let initialAttempt = OpalFusion.Mosaic.Attempt(
                configuration: .init(profile: .opalMainnetAlpha)
            )
            cachedAttempt = initialAttempt
            stagedAttempt = initialAttempt
            loadedRecoveryNeedsDirective = false
            issuedPublicationIdentifier = nil
            postManifestConstructionIssued = false
            postManifestTerminalReadbackValidated = true
        }

        @_spi(MosaicPrivateAlpha)
        public init(claiming loadedRecovery: consuming LoadedRecovery) throws {
            typealias Runtime = OpalFusion.MosaicPrivateAlphaRuntime
            let recoveredState = loadedRecovery.state
            state = recoveredState
            durableSnapshot = try recoveredState.canonicalBytes()
            stagedState = nil
            stagedTransition = nil
            switch recoveredState.manifestState {
            case .forming:
                cachedFormationState = try Runtime
                    .restorePrivateDeploymentFormation(
                        discoveryEpochStartUnixSeconds:
                            recoveredState.discoveryEpochStartUnixSeconds,
                        phase: recoveredState.phase,
                        canonicalDocuments:
                            recoveredState.preManifestDocuments
                    )
            case .validated:
                cachedFormationState = nil
            }
            stagedFormationState = nil
            cachedAttempt = nil
            stagedAttempt = nil
            loadedRecoveryNeedsDirective = true
            issuedPublicationIdentifier = nil
            postManifestConstructionIssued = false
            if case .validated = recoveredState.manifestState {
                switch (
                    recoveredState.publicationState,
                    recoveredState.terminalState
                ) {
                case (.terminal, .active), (.none, .authorized):
                    postManifestTerminalReadbackValidated = false
                default:
                    postManifestTerminalReadbackValidated = true
                }
            } else {
                postManifestTerminalReadbackValidated = true
            }
        }
    }
}
#endif

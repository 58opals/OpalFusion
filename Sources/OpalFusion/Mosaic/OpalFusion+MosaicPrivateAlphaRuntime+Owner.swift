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
            loadedRecoveryNeedsDirective = false
            issuedPublicationIdentifier = nil
            postManifestConstructionIssued = false
            postManifestTerminalReadbackValidated = true
        }

        @_spi(MosaicPrivateAlpha)
        public init(claiming loadedRecovery: consuming LoadedRecovery) throws {
            let recoveredState = loadedRecovery.state
            state = recoveredState
            durableSnapshot = try recoveredState.canonicalBytes()
            stagedState = nil
            stagedTransition = nil
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

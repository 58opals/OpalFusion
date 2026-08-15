// OpalFusion+MosaicPrivateAlphaRuntime+Owner+Persistence.swift

#if os(macOS)
import Foundation

extension OpalFusion.MosaicPrivateAlphaRuntime.Owner {
    @_spi(MosaicPrivateAlpha)
    public func nextStep() throws -> OpalFusion.MosaicPrivateAlphaRuntime.Step {
        if let stagedTransition {
            return .persist(stagedTransition)
        }
        if let publication = try privateDeploymentPublication() {
            if loadedRecoveryNeedsDirective {
                return .recover(.publishPrivateDeployment(publication))
            }
            return .publishPrivateDeployment(publication)
        }
        if loadedRecoveryNeedsDirective {
            return .recover(try recoveryDirective())
        }
        if let disposition = state.terminalDisposition() {
            if case .validated = state.manifestState,
               !postManifestTerminalReadbackValidated {
                return .awaitingInput(state.phase)
            }
            return .terminal(disposition)
        }
        if state.preManifestAbortCause != .none {
            return .awaitingPreManifestAbortSignature(state.phase)
        }
        return .awaitingInput(state.phase)
    }

    /// Installs a transition only after exact bytes are read back from the app's outer record.
    @_spi(MosaicPrivateAlpha)
    public func acknowledgePersistence(
        _ transition: OpalFusion.MosaicPrivateAlphaRuntime
            .RecoveryTransition,
        exactReadback: Data
    ) throws -> OpalFusion.MosaicPrivateAlphaRuntime.Step {
        typealias Runtime = OpalFusion.MosaicPrivateAlphaRuntime
        guard transition == stagedTransition,
              let stagedState else {
            throw Runtime.Failure.staleRecoveryTransition
        }
        guard exactReadback == transition.replacementSnapshot else {
            throw Runtime.Failure.exactReadbackMismatch
        }
        let decoded = try Runtime.RecoveryState.decode(
            from: exactReadback,
            expectedBinding: state.binding
        )
        guard decoded == stagedState else {
            throw Runtime.Failure.exactReadbackMismatch
        }
        state = decoded
        durableSnapshot = exactReadback
        self.stagedState = nil
        stagedTransition = nil
        if case .validated = state.manifestState,
           case .authorized = state.terminalState,
           !postManifestTerminalReadbackValidated {
            // A loaded pending terminal publication has now crossed its
            // durable receipt transition. It must still reconstruct the
            // no-route runtime and validate both companion journals before
            // terminal cleanup authority can be surfaced.
            loadedRecoveryNeedsDirective = true
        } else {
            loadedRecoveryNeedsDirective = false
        }
        if state.publicationState == .none {
            issuedPublicationIdentifier = nil
        }

        return try nextStep()
    }

    func stage(
        _ update: (inout OpalFusion.MosaicPrivateAlphaRuntime.RecoveryState)
            throws -> Void
    ) throws -> OpalFusion.MosaicPrivateAlphaRuntime.Step {
        typealias Runtime = OpalFusion.MosaicPrivateAlphaRuntime
        guard stagedTransition == nil,
              state.publicationState == .none,
              state.terminalState == .active,
              let durableSnapshot else {
            throw Runtime.Failure.invalidStateTransition
        }
        var replacement = try state.replacingRevision()
        try update(&replacement)
        try replacement.validate()
        let transition = try Self.makeTransition(
            expectedSnapshot: durableSnapshot,
            replacementState: replacement
        )
        stagedState = replacement
        stagedTransition = transition
        return .persist(transition)
    }

    func stagePublicationResolution(
        _ update: (inout OpalFusion.MosaicPrivateAlphaRuntime.RecoveryState)
            throws -> Void
    ) throws -> OpalFusion.MosaicPrivateAlphaRuntime.Step {
        typealias Runtime = OpalFusion.MosaicPrivateAlphaRuntime
        guard stagedTransition == nil,
              state.publicationState != .none,
              state.terminalState == .active,
              let durableSnapshot else {
            throw Runtime.Failure.invalidStateTransition
        }
        var replacement = try state.replacingRevision()
        try update(&replacement)
        try replacement.validate()
        let transition = try Self.makeTransition(
            expectedSnapshot: durableSnapshot,
            replacementState: replacement
        )
        stagedState = replacement
        stagedTransition = transition
        return .persist(transition)
    }

    private func privateDeploymentPublication() throws
        -> OpalFusion.MosaicPrivateAlphaRuntime.PrivateDeploymentPublication? {
        typealias Runtime = OpalFusion.MosaicPrivateAlphaRuntime
        let publication: Runtime.PrivateDeploymentPublication
        switch state.publicationState {
        case .none:
            return nil
        case let .formation(event, endpoints),
             let .terminal(_, event, endpoints, _):
            publication = try .init(
                binding: state.binding,
                event: event,
                relayEndpointIdentifiers: endpoints
            )
        }
        guard issuedPublicationIdentifier == nil else {
            throw Runtime.Failure.invalidStateTransition
        }
        issuedPublicationIdentifier = publication.operationIdentifier
        return publication
    }

    static func makeTransition(
        expectedSnapshot: Data?,
        replacementState: OpalFusion.MosaicPrivateAlphaRuntime.RecoveryState
    ) throws -> OpalFusion.MosaicPrivateAlphaRuntime.RecoveryTransition {
        typealias Runtime = OpalFusion.MosaicPrivateAlphaRuntime
        let replacement = try replacementState.canonicalBytes()
        return .init(
            binding: replacementState.binding,
            expectedSnapshot: expectedSnapshot,
            replacementSnapshot: replacement,
            replacementDigest: Runtime.RecoveryState.sha256(replacement),
            replacementRevision: replacementState.revision,
            transitionIdentifier: try Runtime.RecoveryState
                .transitionIdentifier(
                    binding: replacementState.binding,
                    expectedSnapshot: expectedSnapshot,
                    replacementSnapshot: replacement
                )
        )
    }
}
#endif

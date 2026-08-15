// OpalFusion+MosaicPrivateAlphaRuntime+Owner+Terminal.swift

#if os(macOS)
import Foundation

extension OpalFusion.MosaicPrivateAlphaRuntime.Owner {
    /// Constructs, signs, and stages the exact local terminal notice before public relay access.
    @_spi(MosaicPrivateAlpha)
    public func prepareTerminalPublication(
        consuming termination: consuming OpalFusion
            .MosaicPrivateAlphaRuntime.PostManifestTermination,
        createdAtUnixSeconds: UInt64,
        signing: consuming OpalFusion.MosaicPrivateAlphaRuntime
            .PrivateDeploymentSigningCapability
    ) throws -> OpalFusion.MosaicPrivateAlphaRuntime.Step {
        typealias Alpha = OpalFusion.Mosaic.OpalMainnetAlpha
        typealias Runtime = OpalFusion.MosaicPrivateAlphaRuntime
        try validate(termination: termination)

        let payload: Alpha.PreManifestNostrPayloadDocument
        let reason: Runtime.TerminalReason
        switch (termination.kind, termination.authority) {
        case let (.completed, .completion(validation)):
            guard termination.receivedTerminalEvent == nil,
                  termination.localTerminalEvent == nil,
                  termination.isLocalConductor,
                  signing.verificationKey.rawRepresentation
                    == Data(validation.roundManifest.core.roster
                        .conductor.validatedBytes) else {
                throw Runtime.Failure.terminalEvidenceUnavailable
            }
            payload = try .makeCompletion(
                .init(validation: validation),
                validation: validation
            )
            reason = .completed
        case let (.aborted, .abort(authority, expectedReason)):
            guard termination.receivedTerminalEvent == nil,
                  termination.localTerminalEvent == nil,
                  signing.verificationKey == authority.signerIdentity else {
                throw Runtime.Failure.terminalEvidenceUnavailable
            }
            payload = try .makeAbort(
                .init(
                    discoveryEpochStartUnixSeconds:
                        authority.discoveryEpochStartUnixSeconds,
                    phase: authority.phase,
                    context: authority.context,
                    reason: expectedReason
                ),
                authority: authority
            )
            reason = .aborted
        case (.completed, .abort), (.completed, .unavailable),
             (.aborted, .completion), (.aborted, .unavailable),
             (.failed, _), (.recoveryRequired, _), (.transportFailed, _):
            throw Runtime.Failure.terminalEvidenceUnavailable
        }
        let signedEvent = try makeLocalPrivateDeploymentEvent(
            payload: payload,
            createdAtUnixSeconds: createdAtUnixSeconds,
            signing: signing
        )
        return try stageTerminalPublication(
            termination: termination,
            signedTerminalEvent: signedEvent,
            reason: reason
        )
    }

    /// Stages the exact timeout event already signed and persisted before coordinator abort.
    @_spi(MosaicPrivateAlpha)
    public func preparePersistedTimeoutPublication(
        consuming termination: consuming OpalFusion
            .MosaicPrivateAlphaRuntime.PostManifestTermination
    ) throws -> OpalFusion.MosaicPrivateAlphaRuntime.Step {
        typealias Alpha = OpalFusion.Mosaic.OpalMainnetAlpha
        typealias Runtime = OpalFusion.MosaicPrivateAlphaRuntime
        try validate(termination: termination)
        guard termination.kind == .aborted,
              termination.receivedTerminalEvent == nil,
              let localEvent = termination.localTerminalEvent,
              case let .abort(authority, expectedReason) =
                termination.authority,
              expectedReason == .timeout else {
            throw Runtime.Failure.terminalEvidenceUnavailable
        }
        let document = try Alpha.PreManifestNostrCodec.decodeAbort(
            localEvent.decodeCanonicalNostrEvent(),
            authority: authority,
            currentUnixSeconds: localEvent.acceptedAtUnixSeconds
        )
        guard document.reason == expectedReason,
              authority.signerIdentity.rawRepresentation
                == termination.localControlIdentity else {
            throw Runtime.Failure.terminalEvidenceUnavailable
        }
        return try stageTerminalPublication(
            termination: termination,
            signedTerminalEvent: localEvent,
            reason: .aborted
        )
    }

    /// Accepts an exact conductor-signed completion received by a contributor.
    @_spi(MosaicPrivateAlpha)
    public func acceptReceivedConductorCompletion(
        consuming termination: consuming OpalFusion
            .MosaicPrivateAlphaRuntime.PostManifestTermination
    ) throws -> OpalFusion.MosaicPrivateAlphaRuntime.Step {
        typealias Alpha = OpalFusion.Mosaic.OpalMainnetAlpha
        typealias Runtime = OpalFusion.MosaicPrivateAlphaRuntime
        try validate(termination: termination)
        guard !termination.isLocalConductor,
              termination.localTerminalEvent == nil,
              let receivedCompletionEvent =
                termination.receivedTerminalEvent,
              termination.kind == .completed,
              case let .completion(validation) = termination.authority else {
            throw Runtime.Failure.terminalEvidenceUnavailable
        }
        let event = try receivedCompletionEvent.decodeCanonicalNostrEvent()
        _ = try Alpha.PreManifestNostrCodec.decodeCompletion(
            event,
            validation: validation,
            currentUnixSeconds:
                receivedCompletionEvent.acceptedAtUnixSeconds
        )
        let evidence = try Self.makeTerminalEvidence(
            termination: termination,
            signedTerminalEvent: receivedCompletionEvent,
            reason: .completed,
            wasReceived: true,
            predecessorRevision: state.revision,
            predecessorSnapshotDigest: try state.digest()
        )
        return try stage { candidate in
            candidate.terminalState = .authorized(
                .completed,
                exactEvidenceBytes: evidence
            )
        }
    }

    /// Installs a received abort only after the exact coordinator termination and drain.
    @_spi(MosaicPrivateAlpha)
    public func acceptReceivedAbortTermination(
        consuming termination: consuming OpalFusion
            .MosaicPrivateAlphaRuntime.PostManifestTermination
    ) throws -> OpalFusion.MosaicPrivateAlphaRuntime.Step {
        typealias Alpha = OpalFusion.Mosaic.OpalMainnetAlpha
        typealias Runtime = OpalFusion.MosaicPrivateAlphaRuntime
        try validate(termination: termination)
        guard termination.kind == .aborted,
              termination.localTerminalEvent == nil,
              case let .abort(authority, expectedReason) =
                termination.authority,
              let receivedEvent = termination.receivedTerminalEvent else {
            throw Runtime.Failure.terminalEvidenceUnavailable
        }
        let event = try receivedEvent.decodeCanonicalNostrEvent()
        let document = try Alpha.PreManifestNostrCodec.decodeAbort(
            event,
            authority: authority,
            currentUnixSeconds: receivedEvent.acceptedAtUnixSeconds
        )
        guard document.reason == expectedReason else {
            throw Runtime.Failure.terminalEvidenceUnavailable
        }
        let evidence = try Self.makeTerminalEvidence(
            termination: termination,
            signedTerminalEvent: receivedEvent,
            reason: .aborted,
            wasReceived: true,
            predecessorRevision: state.revision,
            predecessorSnapshotDigest: try state.digest()
        )
        return try stage { candidate in
            candidate.terminalState = .authorized(
                .aborted,
                exactEvidenceBytes: evidence
            )
        }
    }

    @_spi(MosaicPrivateAlpha)
    public func claimTerminalEvidence()
        throws -> OpalFusion.MosaicPrivateAlphaRuntime.TerminalEvidence {
        typealias Runtime = OpalFusion.MosaicPrivateAlphaRuntime
        guard stagedTransition == nil,
              state.publicationState == .none,
              postManifestTerminalReadbackValidated,
              case let .authorized(_, evidence) = state.terminalState else {
            throw Runtime.Failure.terminalEvidenceUnavailable
        }
        guard !terminalEvidenceClaimed else {
            throw Runtime.Failure.terminalEvidenceAlreadyClaimed
        }
        terminalEvidenceClaimed = true
        return .init(
            binding: state.binding,
            evidenceIdentifier: Runtime.RecoveryState.sha256(evidence),
            recoveryRevision: state.revision,
            recoverySnapshotDigest: try state.digest()
        )
    }

    /// Reattaches a loaded terminal snapshot to exact canonical journals and runtime proof.
    @_spi(MosaicPrivateAlpha)
    public func validateRecoveredPostManifestTerminal(
        consuming termination: consuming OpalFusion.MosaicPrivateAlphaRuntime
            .PostManifestTermination
    ) throws -> OpalFusion.MosaicPrivateAlphaRuntime.Step {
        typealias Runtime = OpalFusion.MosaicPrivateAlphaRuntime
        guard !loadedRecoveryNeedsDirective,
              postManifestConstructionIssued,
              !postManifestTerminalReadbackValidated,
              state.publicationState == .none,
              case .validated = state.manifestState,
              case let .authorized(reason, storedBytes) = state.terminalState
        else {
            throw Runtime.Failure.terminalEvidenceUnavailable
        }
        let evidence = try state.validatePostManifestTerminalEvidence(
            storedBytes,
            expectedReason: reason
        )
        try validate(termination: termination)
        let expectedKind: Runtime.PostManifestExecutionOutcomeKind
        switch (reason, termination.authority) {
        case (.aborted, .abort):
            expectedKind = .aborted
        case (.completed, .completion):
            expectedKind = .completed
        case (.aborted, .completion), (.aborted, .unavailable),
             (.completed, .abort), (.completed, .unavailable):
            throw Runtime.Failure.terminalEvidenceUnavailable
        }
        guard termination.kind == expectedKind,
              termination.localControlIdentity
                == evidence.localControlIdentity,
              termination.terminalIdentity == evidence.terminalIdentity,
              termination.admissionSnapshotDigest
                == evidence.admissionSnapshotDigest,
              termination.publicationSnapshotDigest
                == evidence.publicationSnapshotDigest,
              termination.receivedTerminalEvent
                == (evidence.wasReceived ? evidence.event : nil),
              termination.localTerminalEvent
                == (evidence.wasReceived ? nil : evidence.event),
              try Self.makeTerminalEvidence(
                termination: termination,
                signedTerminalEvent: evidence.event,
                reason: reason,
                wasReceived: evidence.wasReceived,
                predecessorRevision: evidence.predecessorRevision,
                predecessorSnapshotDigest:
                    evidence.predecessorSnapshotDigest
              ) == storedBytes,
              let disposition = state.terminalDisposition() else {
            throw Runtime.Failure.terminalEvidenceUnavailable
        }
        postManifestTerminalReadbackValidated = true
        return .terminal(disposition)
    }

    private func validate(
        termination: borrowing OpalFusion.MosaicPrivateAlphaRuntime
            .PostManifestTermination
    ) throws {
        typealias Runtime = OpalFusion.MosaicPrivateAlphaRuntime
        guard termination.binding == state.binding,
              termination.outboundIsDrained,
              termination.terminalIdentity.count == 32,
              termination.admissionSnapshotDigest.count == 32,
              termination.publicationSnapshotDigest.count == 32 else {
            throw Runtime.Failure.terminalEvidenceUnavailable
        }
    }

    private func stageTerminalPublication(
        termination: borrowing OpalFusion.MosaicPrivateAlphaRuntime
            .PostManifestTermination,
        signedTerminalEvent: OpalFusion.MosaicPrivateAlphaRuntime
            .PrivateDeploymentEvent,
        reason: OpalFusion.MosaicPrivateAlphaRuntime.TerminalReason
    ) throws -> OpalFusion.MosaicPrivateAlphaRuntime.Step {
        typealias Runtime = OpalFusion.MosaicPrivateAlphaRuntime
        let evidence = try Self.makeTerminalEvidence(
            termination: termination,
            signedTerminalEvent: signedTerminalEvent,
            reason: reason,
            wasReceived: false,
            predecessorRevision: state.revision,
            predecessorSnapshotDigest: try state.digest()
        )
        let proof = try Runtime.restorePrivateDeploymentProof(
            discoveryEpochStartUnixSeconds:
                state.discoveryEpochStartUnixSeconds,
            canonicalDocuments: state.preManifestDocuments
        )
        let relaySet = try OpalFusion.Mosaic.OpalMainnetAlpha
            .RelaySetDocument.decode(
                from: Array(proof.canonicalDocuments[1])
            )
        return try stage { candidate in
            candidate.publicationState = .terminal(
                reason: reason,
                event: signedTerminalEvent,
                relayEndpointIdentifiers: relaySet.registrations.map {
                    $0.endpoint.normalizedURL
                },
                exactEvidenceBytes: evidence
            )
        }
    }

    private static func makeTerminalEvidence(
        termination: borrowing OpalFusion.MosaicPrivateAlphaRuntime
            .PostManifestTermination,
        signedTerminalEvent: OpalFusion.MosaicPrivateAlphaRuntime
            .PrivateDeploymentEvent,
        reason: OpalFusion.MosaicPrivateAlphaRuntime.TerminalReason,
        wasReceived: Bool,
        predecessorRevision: UInt64,
        predecessorSnapshotDigest: Data
    ) throws -> Data {
        try OpalFusion.MosaicPrivateAlphaRuntime.PostManifestTerminalEvidence(
            binding: termination.binding,
            reason: reason,
            wasReceived: wasReceived,
            predecessorRevision: predecessorRevision,
            predecessorSnapshotDigest: predecessorSnapshotDigest,
            localControlIdentity: termination.localControlIdentity,
            terminalIdentity: termination.terminalIdentity,
            event: signedTerminalEvent,
            admissionSnapshotDigest: termination.admissionSnapshotDigest,
            publicationSnapshotDigest:
                termination.publicationSnapshotDigest
        ).canonicalBytes()
    }
}
#endif

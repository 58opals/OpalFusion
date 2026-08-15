// OpalFusion+MosaicPrivateAlphaRuntime+Owner+PreManifestAbort.swift

#if os(macOS)
import Foundation

extension OpalFusion.MosaicPrivateAlphaRuntime.Owner {
    @_spi(MosaicPrivateAlpha)
    public func preparePreManifestAbort(
        currentUnixSeconds: UInt64,
        signing: consuming OpalFusion.MosaicPrivateAlphaRuntime
            .PrivateDeploymentSigningCapability
    ) throws -> OpalFusion.MosaicPrivateAlphaRuntime.Step {
        typealias Alpha = OpalFusion.Mosaic.OpalMainnetAlpha
        typealias Runtime = OpalFusion.MosaicPrivateAlphaRuntime
        guard !loadedRecoveryNeedsDirective,
              state.manifestState == .forming,
              let durableSnapshot else {
            throw Runtime.Failure.invalidStateTransition
        }
        let formation = try Runtime.restorePrivateDeploymentFormation(
            discoveryEpochStartUnixSeconds:
                state.discoveryEpochStartUnixSeconds,
            phase: state.phase,
            canonicalDocuments: state.preManifestDocuments
        )
        let authority = try Runtime.privateDeploymentAbortAuthority(
            formation: formation,
            signerIdentity: signing.verificationKey
        )
        let reason = try state.expectedPreManifestDeadlineAbortReason()
        guard currentUnixSeconds >= state.discoveryEpochStartUnixSeconds,
              currentUnixSeconds <= authority.expiryUnixSeconds else {
            throw Runtime.Failure.invalidStateTransition
        }
        switch state.preManifestAbortCause {
        case let .equivocation(event),
             let .invalidAuthenticatedMessage(event):
            guard currentUnixSeconds >= event.acceptedAtUnixSeconds else {
                throw Runtime.Failure.invalidStateTransition
            }
        case .none:
            break
        }
        if reason == .missingRequiredParticipant || reason == .timeout {
            let phaseBoundary = try Runtime.preManifestTimeoutBoundary(
                phase: state.phase,
                discoveryEpochStartUnixSeconds:
                    state.discoveryEpochStartUnixSeconds
            )
            guard currentUnixSeconds >= phaseBoundary else {
                throw Runtime.Failure.invalidStateTransition
            }
        }
        let payload = try Alpha.PreManifestNostrPayloadDocument.makeAbort(
            .init(
                discoveryEpochStartUnixSeconds:
                    authority.discoveryEpochStartUnixSeconds,
                phase: authority.phase,
                context: authority.context,
                reason: reason
            ),
            authority: authority
        )
        let event = try makeLocalPrivateDeploymentEvent(
            payload: payload,
            createdAtUnixSeconds: currentUnixSeconds,
            signing: signing
        )
        let evidence = try Runtime.RecoveryState
            .makePreManifestTerminalEvidence(
                binding: state.binding,
                phase: state.phase,
                event: event,
                wasLocallyPublished: true,
                predecessorRevision: state.revision,
                priorSnapshotDigest: Runtime.RecoveryState.sha256(
                    durableSnapshot
                )
            )
        let relaySet = try privateDeploymentRelaySet()
        return try stage { candidate in
            candidate.publicationState = .terminal(
                reason: .aborted,
                event: event,
                relayEndpointIdentifiers: relaySet.registrations.map {
                    $0.endpoint.normalizedURL
                },
                exactEvidenceBytes: evidence
            )
        }
    }

    @_spi(MosaicPrivateAlpha)
    public func acceptReceivedPreManifestAbort(
        _ receivedEvent: OpalFusion.MosaicPrivateAlphaRuntime
            .PrivateDeploymentEvent
    ) throws -> OpalFusion.MosaicPrivateAlphaRuntime.Step {
        typealias Alpha = OpalFusion.Mosaic.OpalMainnetAlpha
        typealias Runtime = OpalFusion.MosaicPrivateAlphaRuntime
        guard !loadedRecoveryNeedsDirective,
              state.manifestState == .forming,
              let durableSnapshot else {
            throw Runtime.Failure.invalidStateTransition
        }
        let formation = try Runtime.restorePrivateDeploymentFormation(
            discoveryEpochStartUnixSeconds:
                state.discoveryEpochStartUnixSeconds,
            phase: state.phase,
            canonicalDocuments: state.preManifestDocuments
        )
        let event = try receivedEvent.decodeCanonicalNostrEvent()
        let authority = try Runtime.privateDeploymentAbortAuthority(
            formation: formation,
            signerIdentity: event.publicKey
        )
        _ = try Alpha.PreManifestNostrCodec.decodeAbort(
            event,
            authority: authority,
            currentUnixSeconds: receivedEvent.acceptedAtUnixSeconds
        )
        let evidence = try Runtime.RecoveryState
            .makePreManifestTerminalEvidence(
                binding: state.binding,
                phase: state.phase,
                event: receivedEvent,
                wasLocallyPublished: false,
                predecessorRevision: state.revision,
                priorSnapshotDigest: Runtime.RecoveryState.sha256(
                    durableSnapshot
                )
            )
        return try stage { candidate in
            candidate.terminalState = .authorized(
                .aborted,
                exactEvidenceBytes: evidence
            )
        }
    }
}
#endif

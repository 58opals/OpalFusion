// OpalFusion+MosaicPrivateAlphaRuntime+RecoveryState+PreManifestAbortCause.swift

#if os(macOS)
import Foundation

extension OpalFusion.MosaicPrivateAlphaRuntime.RecoveryState {
    func validatePreManifestAbortCause() throws {
        typealias Runtime = OpalFusion.MosaicPrivateAlphaRuntime
        let conflictingEvent: Runtime.PrivateDeploymentEvent
        switch preManifestAbortCause {
        case .none:
            return
        case let .equivocation(event):
            conflictingEvent = event
        case let .invalidAuthenticatedMessage(event):
            try validatePreManifestInvalidTransition(event)
            return
        }
        guard case .forming = manifestState else {
            throw Runtime.Failure.contradictoryRecoverySnapshot
        }
        guard let conflict = try preManifestConflict(
            for: conflictingEvent
        ), conflict.isSemanticConflict else {
            throw Runtime.Failure.contradictoryRecoverySnapshot
        }
        var replacement = self
        replacement.preManifestAbortCause = .none
        replacement.publicationState = .none
        replacement.terminalState = .active
        replacement.preManifestDocuments[conflict.storedIndex] =
            try conflictingEvent.canonicalRecoveryBytes()
        try replacement.validate()
    }

    private func validatePreManifestInvalidTransition(
        _ invalidEvent: OpalFusion.MosaicPrivateAlphaRuntime
            .PrivateDeploymentEvent
    ) throws {
        typealias Alpha = OpalFusion.Mosaic.OpalMainnetAlpha
        typealias Runtime = OpalFusion.MosaicPrivateAlphaRuntime
        guard case .forming = manifestState,
              try preManifestConflict(for: invalidEvent) == nil else {
            throw Runtime.Failure.contradictoryRecoverySnapshot
        }
        let formation = try Runtime.restorePrivateDeploymentFormation(
            discoveryEpochStartUnixSeconds:
                discoveryEpochStartUnixSeconds,
            phase: phase,
            canonicalDocuments: preManifestDocuments
        )
        let payload = try decodeTimelyPreManifestEnvelope(invalidEvent).payload
        let expectedKind: Alpha.PrivateDeploymentNostrSelector.PayloadKind?
        let signerIsRecognized: Bool
        let signerBytes = [UInt8](payload.signerIdentity.rawRepresentation)
        switch formation {
        case .uninitialized:
            expectedKind = .availabilityBeacon
            signerIsRecognized = false
        case let .discovery(_, _, _, beacons):
            expectedKind = .availabilityBeacon
            signerIsRecognized = beacons.contains {
                $0.core.discoveryIdentity == payload.signerIdentity
            }
        case let .candidateSetAgreement(selection, _, _):
            expectedKind = .candidateSetAcknowledgement
            signerIsRecognized = selection.selectedDiscoveryIdentities
                .contains(signerBytes)
        case let .admission(selection, _, _, _):
            expectedKind = .candidateAdmission
            signerIsRecognized = selection.selectedDiscoveryIdentities
                .contains(signerBytes)
        case let .controlRosterAgreement(roster, _, _):
            expectedKind = .roleCommitment
            signerIsRecognized = roster.controlRosterBinding
                .controlIdentities.contains { $0.validatedBytes == signerBytes }
        case let .roleElection(roster, _, _, _):
            expectedKind = .roleReveal
            signerIsRecognized = roster.controlRosterBinding
                .controlIdentities.contains { $0.validatedBytes == signerBytes }
        case let .nonceAllocationPending(roster, _):
            expectedKind = .contributorNonceAllocation
            signerIsRecognized = roster.controlRosterBinding
                .controlIdentities.contains { $0.validatedBytes == signerBytes }
        case let .nonceAllocationAccepted(roster, _):
            expectedKind = nil
            signerIsRecognized = roster.controlRosterBinding
                .controlIdentities.contains { $0.validatedBytes == signerBytes }
        case let .manifestProposalPending(_, _, _, roster, _, _):
            expectedKind = .manifestProposal
            signerIsRecognized = roster.controlRosterBinding
                .controlIdentities.contains { $0.validatedBytes == signerBytes }
        case let .manifestSignatures(proposal, _, _):
            expectedKind = .manifestSignature
            signerIsRecognized = proposal.manifest.core.roster
                .controlIdentities.contains { $0.validatedBytes == signerBytes }
        }
        guard signerIsRecognized,
              payload.payloadKind != expectedKind,
              payload.payloadKind != .abort,
              payload.payloadKind != .completion else {
            throw Runtime.Failure.contradictoryRecoverySnapshot
        }
    }

    func provesPreManifestInvalidTransition(
        _ event: OpalFusion.MosaicPrivateAlphaRuntime.PrivateDeploymentEvent
    ) -> Bool {
        var candidate = self
        candidate.preManifestAbortCause = .invalidAuthenticatedMessage(event)
        do {
            try candidate.validatePreManifestAbortCause()
            return true
        } catch {
            return false
        }
    }

    func preManifestConflict(
        for conflictingEvent: OpalFusion.MosaicPrivateAlphaRuntime
        .PrivateDeploymentEvent
    ) throws -> (storedIndex: Int, isSemanticConflict: Bool)? {
        typealias Runtime = OpalFusion.MosaicPrivateAlphaRuntime
        let incomingEnvelope = try decodeTimelyPreManifestEnvelope(
            conflictingEvent
        )
        let incoming = incomingEnvelope.event
        let incomingPayload = incomingEnvelope.payload
        let stored = try preManifestDocuments.enumerated().dropFirst(2)
            .compactMap { index, bytes -> (
                Int,
                Runtime.PrivateDeploymentEvent,
                OpalFusion.Mosaic.NostrNamespace.Event,
                OpalFusion.Mosaic.OpalMainnetAlpha
                    .PreManifestNostrPayloadDocument
            )? in
                guard let event = try? Runtime.PrivateDeploymentEvent
                    .decodeRecoveryBytes(bytes) else {
                    return nil
                }
                let decoded = try event.decodeCanonicalNostrEvent()
                let payload = try OpalFusion.Mosaic.OpalMainnetAlpha
                    .PreManifestNostrCodec.decodeCanonicalEnvelope(decoded)
                guard payload.payloadKind == incomingPayload.payloadKind,
                      payload.signerIdentity == incomingPayload.signerIdentity
                else {
                    return nil
                }
                return (index, event, decoded, payload)
            }
        guard stored.count <= 1 else {
            throw Runtime.Failure.contradictoryRecoverySnapshot
        }
        guard let stored = stored.first else { return nil }
        guard stored.1.canonicalEventBytes
                != conflictingEvent.canonicalEventBytes else {
            return (stored.0, false)
        }
        if incomingPayload.payloadKind == .availabilityBeacon {
            let existingBeacon = try OpalFusion.Mosaic.OpalMainnetAlpha
                .PreManifestNostrCodec.decodeAvailabilityBeacon(
                    stored.2,
                    discoveryEpochStartUnixSeconds:
                        discoveryEpochStartUnixSeconds,
                    currentUnixSeconds: stored.1.acceptedAtUnixSeconds
                )
            let conflictingBeacon = try OpalFusion.Mosaic.OpalMainnetAlpha
                .PreManifestNostrCodec.decodeAvailabilityBeacon(
                    incoming,
                    discoveryEpochStartUnixSeconds:
                        discoveryEpochStartUnixSeconds,
                    currentUnixSeconds:
                        conflictingEvent.acceptedAtUnixSeconds
                )
            return (
                stored.0,
                existingBeacon.core.canonicalBytes
                    != conflictingBeacon.core.canonicalBytes
            )
        }
        // Rewrapping the same canonical signed statement in a distinct valid
        // Nostr envelope is a semantic duplicate, not protocol equivocation.
        return (
            stored.0,
            stored.3.canonicalBytes != incomingPayload.canonicalBytes
        )
    }

    private func decodeTimelyPreManifestEnvelope(
        _ event: OpalFusion.MosaicPrivateAlphaRuntime.PrivateDeploymentEvent
    ) throws -> (
        event: OpalFusion.Mosaic.NostrNamespace.Event,
        payload: OpalFusion.Mosaic.OpalMainnetAlpha
            .PreManifestNostrPayloadDocument
    ) {
        typealias Runtime = OpalFusion.MosaicPrivateAlphaRuntime
        let nostrEvent = try event.decodeCanonicalNostrEvent()
        let payload = try OpalFusion.Mosaic.OpalMainnetAlpha
            .PreManifestNostrCodec.decodeCanonicalEnvelope(nostrEvent)
        guard payload.discoveryEpochStartUnixSeconds
                == discoveryEpochStartUnixSeconds,
              nostrEvent.template.createdAt
                <= event.acceptedAtUnixSeconds,
              event.acceptedAtUnixSeconds <= payload.expiryUnixSeconds else {
            throw Runtime.Failure.invalidPrivateDeploymentProof
        }
        return (nostrEvent, payload)
    }

    func expectedPreManifestDeadlineAbortReason()
        throws -> OpalFusion.Mosaic.Attempt.AbortReason {
        typealias Runtime = OpalFusion.MosaicPrivateAlphaRuntime
        switch preManifestAbortCause {
        case .equivocation:
            return .equivocation
        case .invalidAuthenticatedMessage:
            return .invalidAuthenticatedMessage
        case .none:
            break
        }
        let formation = try Runtime.restorePrivateDeploymentFormation(
            discoveryEpochStartUnixSeconds:
                discoveryEpochStartUnixSeconds,
            phase: phase,
            canonicalDocuments: preManifestDocuments
        )
        let isMissing: Bool
        switch formation {
        case .uninitialized:
            isMissing = true
        case let .discovery(_, _, _, beacons):
            isMissing = beacons.count < 7
        case let .candidateSetAgreement(selection, _, acknowledgements):
            isMissing = acknowledgements.count
                < selection.selectedBeacons.count
        case let .admission(selection, _, _, admissions):
            isMissing = admissions.count < selection.selectedBeacons.count
        case let .controlRosterAgreement(roster, _, commitments):
            isMissing = commitments.count
                < roster.controlRosterBinding.controlIdentities.count
        case let .roleElection(roster, _, _, reveals):
            isMissing = reveals.count
                < roster.controlRosterBinding.controlIdentities.count
        case .nonceAllocationPending, .manifestProposalPending:
            isMissing = true
        case .nonceAllocationAccepted:
            isMissing = false
        case let .manifestSignatures(proposal, _, signatures):
            isMissing = signatures.count
                < proposal.manifest.core.roster.controlIdentities.count
        }
        return isMissing ? .missingRequiredParticipant : .timeout
    }
}
#endif

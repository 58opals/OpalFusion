// OpalFusion+MosaicPrivateAlphaRuntime+RecoveryState+PostManifestTerminal.swift

#if os(macOS)
import Foundation
import OpalCrypto

extension OpalFusion.MosaicPrivateAlphaRuntime.RecoveryState {
    func validatePostManifestTerminalEvidence(
        _ bytes: Data,
        expectedReason: OpalFusion.MosaicPrivateAlphaRuntime.TerminalReason,
        expectedEvent: OpalFusion.MosaicPrivateAlphaRuntime
            .PrivateDeploymentEvent? = nil
    ) throws -> OpalFusion.MosaicPrivateAlphaRuntime
        .PostManifestTerminalEvidence {
        typealias Alpha = OpalFusion.Mosaic.OpalMainnetAlpha
        typealias Runtime = OpalFusion.MosaicPrivateAlphaRuntime
        let evidence = try Runtime.PostManifestTerminalEvidence.decode(
            bytes,
            expectedBinding: binding
        )
        guard evidence.reason == expectedReason,
              expectedEvent == nil || evidence.event == expectedEvent,
              postManifestJournalState == .initialized else {
            throw Runtime.Failure.contradictoryRecoverySnapshot
        }
        let revisionDelta: UInt64
        if evidence.wasReceived {
            guard case let .authorized(reason, storedBytes) = terminalState,
                  reason == evidence.reason,
                  storedBytes == bytes,
                  publicationState == .none else {
                throw Runtime.Failure.contradictoryRecoverySnapshot
            }
            revisionDelta = 1
        } else {
            switch (publicationState, terminalState) {
            case let (.terminal(reason, event, _, storedBytes), .active):
                guard reason == evidence.reason,
                      event == evidence.event,
                      storedBytes == bytes else {
                    throw Runtime.Failure.contradictoryRecoverySnapshot
                }
                revisionDelta = 1
            case let (.none, .authorized(reason, storedBytes)):
                guard reason == evidence.reason,
                      storedBytes == bytes else {
                    throw Runtime.Failure.contradictoryRecoverySnapshot
                }
                revisionDelta = 2
            default:
                throw Runtime.Failure.contradictoryRecoverySnapshot
            }
        }
        let expectedRevision = evidence.predecessorRevision
            .addingReportingOverflow(revisionDelta)
        guard !expectedRevision.overflow,
              revision == expectedRevision.partialValue else {
            throw Runtime.Failure.contradictoryRecoverySnapshot
        }
        var predecessor = self
        predecessor.revision = evidence.predecessorRevision
        predecessor.publicationState = .none
        predecessor.terminalState = .active
        try predecessor.validate()
        guard try predecessor.digest()
                == evidence.predecessorSnapshotDigest else {
            throw Runtime.Failure.contradictoryRecoverySnapshot
        }
        let proof = try Runtime.restorePrivateDeploymentProof(
            discoveryEpochStartUnixSeconds:
                discoveryEpochStartUnixSeconds,
            canonicalDocuments: preManifestDocuments
        )
        let localIdentity = OpalFusion.Mosaic.Attempt.ControlIdentity(
            validatedBytes: Array(evidence.localControlIdentity)
        )
        guard proof.completeManifest.core.roster.controlIdentities
                .contains(localIdentity) else {
            throw Runtime.Failure.contradictoryRecoverySnapshot
        }
        let event = try evidence.event.decodeCanonicalNostrEvent()
        let payload = try Alpha.PreManifestNostrCodec
            .decodeCanonicalEnvelope(event)
        guard event.template.createdAt
                <= evidence.event.acceptedAtUnixSeconds,
              evidence.event.acceptedAtUnixSeconds
                <= payload.expiryUnixSeconds else {
            throw Runtime.Failure.contradictoryRecoverySnapshot
        }
        if !evidence.wasReceived {
            guard event.publicKey.rawRepresentation
                    == evidence.localControlIdentity,
                  event.template.createdAt
                    == evidence.event.acceptedAtUnixSeconds else {
                throw Runtime.Failure.contradictoryRecoverySnapshot
            }
        }

        let authorityBytes: Data
        let kind: Runtime.PostManifestExecutionOutcomeKind
        switch evidence.reason {
        case .aborted:
            authorityBytes = try postManifestAbortAuthorityBytes(
                event: event,
                storedEvent: evidence.event,
                proof: proof,
                wasReceived: evidence.wasReceived
            )
            kind = .aborted
        case .completed:
            let localIsConductor = localIdentity
                == proof.completeManifest.core.roster.conductor
            guard localIsConductor != evidence.wasReceived else {
                throw Runtime.Failure.contradictoryRecoverySnapshot
            }
            authorityBytes = try postManifestCompletionAuthorityBytes(
                event: event,
                payload: payload,
                proof: proof
            )
            kind = .completed
        }
        let expectedIdentity = try Runtime.PostManifestExecution
            .makeTerminalIdentity(
                binding: binding,
                kind: kind,
                authorityIdentityBytes: authorityBytes,
                admissionSnapshotDigest:
                    evidence.admissionSnapshotDigest,
                publicationSnapshotDigest:
                    evidence.publicationSnapshotDigest,
                receivedTerminalEvent:
                    evidence.wasReceived ? evidence.event : nil
            )
        guard expectedIdentity == evidence.terminalIdentity else {
            throw Runtime.Failure.contradictoryRecoverySnapshot
        }
        return evidence
    }

    private func postManifestAbortAuthorityBytes(
        event: OpalFusion.Mosaic.NostrNamespace.Event,
        storedEvent: OpalFusion.MosaicPrivateAlphaRuntime
            .PrivateDeploymentEvent,
        proof: OpalFusion.MosaicPrivateAlphaRuntime.PrivateDeploymentProof,
        wasReceived: Bool
    ) throws -> Data {
        typealias Alpha = OpalFusion.Mosaic.OpalMainnetAlpha
        typealias Runtime = OpalFusion.MosaicPrivateAlphaRuntime
        let participant = OpalFusion.Mosaic.Attempt.ControlIdentity(
            validatedBytes: Array(event.publicKey.rawRepresentation)
        )
        let phases: [OpalFusion.Mosaic.Attempt.Phase] = [
            .walletReservation,
            .groupedCommitment,
            .anonymousComponentSubmission,
            .transcriptAgreement,
            .bchSigning,
        ]
        var matches: [(
            Alpha.PrivateDeploymentAbortAuthority,
            OpalFusion.Mosaic.Attempt.AbortReason
        )] = []
        for phase in phases {
            guard let authority = try? Alpha.PrivateDeploymentAbortAuthority
                .makePostManifestAuthority(
                    phase: phase,
                    participant: participant,
                    manifest: proof.proposalValidation.manifest,
                    roundManifest: proof.completeManifest
                ), let document = try? Alpha.PreManifestNostrCodec
                .decodeAbort(
                    event,
                    authority: authority,
                    currentUnixSeconds: storedEvent.acceptedAtUnixSeconds
                ) else {
                continue
            }
            matches.append((authority, document.reason))
        }
        guard matches.count == 1, let match = matches.first else {
            throw Runtime.Failure.contradictoryRecoverySnapshot
        }
        if !wasReceived, match.1 == .timeout {
            let boundary = try Runtime.PostManifestExecution.timeoutBoundary(
                for: match.0.phase,
                deadlines: proof.completeManifest.core.deadlines
            )
            guard event.template.createdAt
                    == storedEvent.acceptedAtUnixSeconds,
                  event.template.createdAt >= boundary,
                  event.template.createdAt
                    <= proof.completeManifest.core.deadlines.bchSigning else {
                throw Runtime.Failure.contradictoryRecoverySnapshot
            }
        }
        return try Runtime.PostManifestExecution.terminalAuthorityIdentityBytes(
            .abort(match.0, reason: match.1)
        )
    }

    private func postManifestCompletionAuthorityBytes(
        event: OpalFusion.Mosaic.NostrNamespace.Event,
        payload: OpalFusion.Mosaic.OpalMainnetAlpha
            .PreManifestNostrPayloadDocument,
        proof: OpalFusion.MosaicPrivateAlphaRuntime.PrivateDeploymentProof
    ) throws -> Data {
        typealias Alpha = OpalFusion.Mosaic.OpalMainnetAlpha
        typealias Runtime = OpalFusion.MosaicPrivateAlphaRuntime
        let conductor = proof.completeManifest.core.roster.conductor
        guard payload.payloadKind == .completion,
              payload.signerRole == .conductor,
              event.publicKey.rawRepresentation == Data(
                conductor.validatedBytes
              ),
              payload.signerIdentity == event.publicKey,
              payload.discoveryEpochStartUnixSeconds
                == discoveryEpochStartUnixSeconds,
              payload.expiryUnixSeconds
                == proof.completeManifest.core.deadlines.bchSigning else {
            throw Runtime.Failure.contradictoryRecoverySnapshot
        }
        try OpalFusion.Mosaic.CanonicalDecoder.decode(
            from: payload.body
        ) { decoder in
            guard try decoder.readText(maximumByteCount: 80)
                    == Alpha.PrivateDeploymentNostrSelector.identifier,
                  try decoder.readText(maximumByteCount: 80)
                    == OpalFusion.Mosaic.Profile.opalMainnetAlpha.rawValue,
                  try decoder.readFixedBytes(byteCount: 32)
                    == Alpha.mainnetGenesisHash,
                  try decoder.readUInt64()
                    == discoveryEpochStartUnixSeconds,
                  try decoder.readFixedBytes(byteCount: 32)
                    == proof.completeManifest.core.roundIdentifier else {
                throw Runtime.Failure.contradictoryRecoverySnapshot
            }
            _ = try decoder.readFixedBytes(byteCount: 32)
        }
        var encoder = OpalFusion.Mosaic.CanonicalEncoder()
        encoder.writeUInt8(0)
        try encoder.writeBytes(payload.body)
        return Data(encoder.encodedBytes)
    }
}
#endif

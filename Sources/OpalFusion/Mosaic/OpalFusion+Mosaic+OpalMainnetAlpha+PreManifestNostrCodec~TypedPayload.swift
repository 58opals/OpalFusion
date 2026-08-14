// OpalFusion+Mosaic+OpalMainnetAlpha+PreManifestNostrCodec~TypedPayload.swift

extension OpalFusion.Mosaic.OpalMainnetAlpha.PreManifestNostrCodec {
    static func decodeAvailabilityBeacon(
        _ event: OpalFusion.Mosaic.NostrNamespace.Event,
        discoveryEpochStartUnixSeconds: UInt64,
        currentUnixSeconds: UInt64
    ) throws -> OpalFusion.Mosaic.OpalMainnetAlpha.AvailabilityBeaconDocument {
        let context = try OpalFusion.Mosaic.OpalMainnetAlpha
            .PreManifestNostrValidationContext.makeDiscoveryContext(
                discoveryEpochStartUnixSeconds:
                    discoveryEpochStartUnixSeconds,
                discoveryIdentity: event.publicKey,
                payloadKind: .availabilityBeacon,
                currentUnixSeconds: currentUnixSeconds
            )
        let payload = try decode(event, validating: context)
        try require(payload, kind: .availabilityBeacon)
        let document = try OpalFusion.Mosaic.OpalMainnetAlpha
            .AvailabilityBeaconDocument.decode(from: payload.body)
        guard document.core.discoveryIdentity == payload.signerIdentity else {
            throw ValidationError.bodySignerIdentityMismatch
        }
        try requireMatchingEpoch(
            document.core.discoveryEpochStartUnixSeconds,
            payload: payload
        )
        return document
    }

    static func decodeCandidateSetAcknowledgement(
        _ event: OpalFusion.Mosaic.NostrNamespace.Event,
        candidateSelection: OpalFusion.Mosaic.OpalMainnetAlpha
            .CandidateSelectionValidation,
        currentUnixSeconds: UInt64
    ) throws -> OpalFusion.Mosaic.OpalMainnetAlpha
        .CandidateSetAcknowledgementDocument {
        let signerBytes = [UInt8](event.publicKey.rawRepresentation)
        guard candidateSelection.selectedDiscoveryIdentities
                .contains(signerBytes) else {
            throw ValidationError.unrecognizedSigner
        }
        let context = try OpalFusion.Mosaic.OpalMainnetAlpha
            .PreManifestNostrValidationContext.makeDiscoveryContext(
                discoveryEpochStartUnixSeconds:
                    candidateSelection.discoveryEpochStartUnixSeconds,
                discoveryIdentity: event.publicKey,
                payloadKind: .candidateSetAcknowledgement,
                currentUnixSeconds: currentUnixSeconds
            )
        let payload = try decode(event, validating: context)
        try require(payload, kind: .candidateSetAcknowledgement)
        let document = try OpalFusion.Mosaic.OpalMainnetAlpha
            .CandidateSetAcknowledgementDocument.decode(from: payload.body)
        guard document.signerDiscoveryIdentity == payload.signerIdentity else {
            throw ValidationError.bodySignerIdentityMismatch
        }
        try requireMatchingEpoch(
            document.discoveryEpochStartUnixSeconds,
            payload: payload
        )
        guard document.candidateSetDigest
                == candidateSelection.candidateSetDigest else {
            throw ValidationError.bodyCandidateSetDigestMismatch
        }
        return document
    }

    static func decodeCandidateAdmission(
        _ event: OpalFusion.Mosaic.NostrNamespace.Event,
        candidateSelection: OpalFusion.Mosaic.OpalMainnetAlpha
            .CandidateSelectionValidation,
        acknowledgementSet: OpalFusion.Mosaic.OpalMainnetAlpha
            .CandidateSetAcknowledgementSetDocument,
        currentUnixSeconds: UInt64
    ) throws -> OpalFusion.Mosaic.OpalMainnetAlpha.CandidateAdmissionDocument {
        do {
            _ = try OpalFusion.Mosaic.OpalMainnetAlpha
                .CandidateSetAcknowledgementSetDocument.decode(
                    from: acknowledgementSet.canonicalBytes,
                    candidateSelection: candidateSelection
                )
        } catch {
            throw ValidationError.invalidFormationProof
        }
        let signerBytes = [UInt8](event.publicKey.rawRepresentation)
        guard candidateSelection.selectedDiscoveryIdentities
                .contains(signerBytes) else {
            throw ValidationError.unrecognizedSigner
        }
        let context = try OpalFusion.Mosaic.OpalMainnetAlpha
            .PreManifestNostrValidationContext.makeDiscoveryContext(
                discoveryEpochStartUnixSeconds:
                    candidateSelection.discoveryEpochStartUnixSeconds,
                discoveryIdentity: event.publicKey,
                payloadKind: .candidateAdmission,
                currentUnixSeconds: currentUnixSeconds
            )
        let payload = try decode(event, validating: context)
        try require(payload, kind: .candidateAdmission)
        let document = try OpalFusion.Mosaic.OpalMainnetAlpha
            .CandidateAdmissionDocument.decode(from: payload.body)
        guard document.discoveryIdentity == payload.signerIdentity else {
            throw ValidationError.bodySignerIdentityMismatch
        }
        try requireMatchingEpoch(
            document.discoveryEpochStartUnixSeconds,
            payload: payload
        )
        guard document.candidateSetDigest
                == candidateSelection.candidateSetDigest else {
            throw ValidationError.bodyCandidateSetDigestMismatch
        }
        return document
    }

    static func decodeRoleCommitment(
        _ event: OpalFusion.Mosaic.NostrNamespace.Event,
        controlRoster: OpalFusion.Mosaic.OpalMainnetAlpha
            .ControlRosterValidation,
        currentUnixSeconds: UInt64
    ) throws -> OpalFusion.Mosaic.Attempt.RoleCommitment {
        let signer = OpalFusion.Mosaic.Attempt.ControlIdentity(
            validatedBytes: [UInt8](event.publicKey.rawRepresentation)
        )
        let context = try OpalFusion.Mosaic.OpalMainnetAlpha
            .PreManifestNostrValidationContext.makeRoleContext(
                signer: signer,
                payloadKind: .roleCommitment,
                controlRoster: controlRoster,
                currentUnixSeconds: currentUnixSeconds
            )
        let payload = try decode(event, validating: context)
        try require(payload, kind: .roleCommitment)
        let document = try OpalFusion.Mosaic.OpalMainnetAlpha
            .PreManifestDocumentCodec.decodeRoleCommitment(
                from: payload.body,
                controlRoster: controlRoster.controlRosterBinding
            )
        guard document.candidate.validatedBytes
                == [UInt8](payload.signerIdentity.rawRepresentation) else {
            throw ValidationError.bodySignerIdentityMismatch
        }
        return document
    }

    static func decodeRoleReveal(
        _ event: OpalFusion.Mosaic.NostrNamespace.Event,
        controlRoster: OpalFusion.Mosaic.OpalMainnetAlpha
            .ControlRosterValidation,
        currentUnixSeconds: UInt64
    ) throws -> OpalFusion.Mosaic.Attempt.RoleReveal {
        let signer = OpalFusion.Mosaic.Attempt.ControlIdentity(
            validatedBytes: [UInt8](event.publicKey.rawRepresentation)
        )
        let context = try OpalFusion.Mosaic.OpalMainnetAlpha
            .PreManifestNostrValidationContext.makeRoleContext(
                signer: signer,
                payloadKind: .roleReveal,
                controlRoster: controlRoster,
                currentUnixSeconds: currentUnixSeconds
            )
        let payload = try decode(event, validating: context)
        try require(payload, kind: .roleReveal)
        let document = try OpalFusion.Mosaic.OpalMainnetAlpha
            .PreManifestDocumentCodec.decodeRoleReveal(
                from: payload.body,
                controlRoster: controlRoster.controlRosterBinding
            )
        guard document.candidate.validatedBytes
                == [UInt8](payload.signerIdentity.rawRepresentation) else {
            throw ValidationError.bodySignerIdentityMismatch
        }
        return document
    }

    static func decodeManifestProposal(
        _ event: OpalFusion.Mosaic.NostrNamespace.Event,
        proposal: OpalFusion.Mosaic.OpalMainnetAlpha
            .PrivateDeploymentManifestProposalValidation,
        currentUnixSeconds: UInt64
    ) throws -> OpalFusion.Mosaic.OpalMainnetAlpha.RoundManifestCore {
        let context = try OpalFusion.Mosaic.OpalMainnetAlpha
            .PreManifestNostrValidationContext.makeManifestProposalContext(
                proposal: proposal,
                currentUnixSeconds: currentUnixSeconds
            )
        let payload = try decode(event, validating: context)
        try require(payload, kind: .manifestProposal)
        let core = try OpalFusion.Mosaic.OpalMainnetAlpha
            .PreManifestDocumentCodec.decodeManifestProposal(
                from: payload.body,
                expectedContext: proposal.expectedContext
            )
        guard core.roster.conductor.validatedBytes
                == [UInt8](payload.signerIdentity.rawRepresentation) else {
            throw ValidationError.bodySignerIdentityMismatch
        }
        guard core == proposal.manifest.core else {
            throw ValidationError.bodyManifestMismatch
        }
        return core
    }

    static func decodeManifestSignature(
        _ event: OpalFusion.Mosaic.NostrNamespace.Event,
        proposal: OpalFusion.Mosaic.OpalMainnetAlpha
            .PrivateDeploymentManifestProposalValidation,
        currentUnixSeconds: UInt64
    ) throws -> OpalFusion.Mosaic.OpalMainnetAlpha
        .PrivateDeploymentManifestSignatureValidation {
        let signer = OpalFusion.Mosaic.Attempt.ControlIdentity(
            validatedBytes: [UInt8](event.publicKey.rawRepresentation)
        )
        let context = try OpalFusion.Mosaic.OpalMainnetAlpha
            .PreManifestNostrValidationContext.makeManifestSignatureContext(
                signer: signer,
                proposal: proposal,
                currentUnixSeconds: currentUnixSeconds
            )
        let payload = try decode(event, validating: context)
        try require(payload, kind: .manifestSignature)
        let validation = try OpalFusion.Mosaic.OpalMainnetAlpha
            .PreManifestDocumentCodec.decodeManifestSignature(
                from: payload.body,
                for: proposal.signatureBinding,
                expectedRoster: proposal.manifest.core.roster
            )
        guard validation.signature.signer.validatedBytes
                == [UInt8](payload.signerIdentity.rawRepresentation) else {
            throw ValidationError.bodySignerIdentityMismatch
        }
        return validation
    }

    static func decodeContributorNonceAllocation(
        _ event: OpalFusion.Mosaic.NostrNamespace.Event,
        controlRoster: OpalFusion.Mosaic.OpalMainnetAlpha
            .ControlRosterValidation,
        roleElection: OpalFusion.Mosaic.Attempt.RoleElectionResult,
        currentUnixSeconds: UInt64
    ) throws -> OpalFusion.Mosaic.OpalMainnetAlpha
        .ContributorNonceAllocationDocument {
        let context = try OpalFusion.Mosaic.OpalMainnetAlpha
            .PreManifestNostrValidationContext
            .makeContributorNonceAllocationContext(
                controlRoster: controlRoster,
                roleElection: roleElection,
                currentUnixSeconds: currentUnixSeconds
            )
        let payload = try decode(event, validating: context)
        try require(payload, kind: .contributorNonceAllocation)
        return try OpalFusion.Mosaic.OpalMainnetAlpha
            .ContributorNonceAllocationDocument.decode(
                from: payload.body,
                roleElection: roleElection
            )
    }

    static func decodeAbort(
        _ event: OpalFusion.Mosaic.NostrNamespace.Event,
        authority: OpalFusion.Mosaic.OpalMainnetAlpha
            .PrivateDeploymentAbortAuthority,
        currentUnixSeconds: UInt64
    ) throws -> OpalFusion.Mosaic.OpalMainnetAlpha.PrivateDeploymentAbortDocument {
        let context = try OpalFusion.Mosaic.OpalMainnetAlpha
            .PreManifestNostrValidationContext.makeAbortContext(
                authority: authority,
                currentUnixSeconds: currentUnixSeconds
            )
        let payload = try decode(event, validating: context)
        try require(payload, kind: .abort)
        let document = try OpalFusion.Mosaic.OpalMainnetAlpha
            .PrivateDeploymentAbortDocument.decode(
                from: payload.body,
                expectedPhase: authority.phase,
                expectedContext: authority.context
            )
        try requireMatchingEpoch(
            document.discoveryEpochStartUnixSeconds,
            payload: payload
        )
        return document
    }

    static func decodeCompletion(
        _ event: OpalFusion.Mosaic.NostrNamespace.Event,
        validation: OpalFusion.Mosaic.OpalMainnetAlpha
            .PrivateDeploymentCompletionValidation,
        currentUnixSeconds: UInt64
    ) throws -> OpalFusion.Mosaic.OpalMainnetAlpha
        .PrivateDeploymentCompletionDocument {
        let context = try OpalFusion.Mosaic.OpalMainnetAlpha
            .PreManifestNostrValidationContext.makeCompletionContext(
                validation: validation,
                currentUnixSeconds: currentUnixSeconds
            )
        let payload = try decode(event, validating: context)
        try require(payload, kind: .completion)
        let document = try OpalFusion.Mosaic.OpalMainnetAlpha
            .PrivateDeploymentCompletionDocument.decode(
                from: payload.body,
                validation: validation
            )
        try requireMatchingEpoch(
            document.discoveryEpochStartUnixSeconds,
            payload: payload
        )
        return document
    }

    private static func require(
        _ payload: OpalFusion.Mosaic.OpalMainnetAlpha
            .PreManifestNostrPayloadDocument,
        kind: OpalFusion.Mosaic.OpalMainnetAlpha.PrivateDeploymentNostrSelector
            .PayloadKind
    ) throws {
        guard payload.payloadKind == kind else {
            throw ValidationError.payloadKindMismatch
        }
    }

    private static func requireMatchingEpoch(
        _ discoveryEpochStartUnixSeconds: UInt64,
        payload: OpalFusion.Mosaic.OpalMainnetAlpha
            .PreManifestNostrPayloadDocument
    ) throws {
        guard discoveryEpochStartUnixSeconds
                == payload.discoveryEpochStartUnixSeconds else {
            throw ValidationError.bodyDiscoveryEpochMismatch
        }
    }
}

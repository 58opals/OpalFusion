// OpalFusion+MosaicPrivateAlphaRuntime+Owner+LocalPrivateDeployment.swift

#if os(macOS)
import Foundation
import OpalCrypto

extension OpalFusion.MosaicPrivateAlphaRuntime.Owner {
    @_spi(MosaicPrivateAlpha)
    public func prepareAvailabilityBeacon(
        proofOfWorkNonce: UInt64,
        createdAtUnixSeconds: UInt64,
        signing: consuming OpalFusion.MosaicPrivateAlphaRuntime
            .PrivateDeploymentSigningCapability
    ) throws -> OpalFusion.MosaicPrivateAlphaRuntime.Step {
        typealias Alpha = OpalFusion.Mosaic.OpalMainnetAlpha
        typealias Runtime = OpalFusion.MosaicPrivateAlphaRuntime
        guard !loadedRecoveryNeedsDirective,
              case let .discovery(pool, relaySet, events, _) =
                try formationState() else {
            throw Runtime.Failure.invalidStateTransition
        }
        let expiry = try Alpha.PrivateDeploymentPolicy.frozen
            .preManifestDeadlines(
                forEpochStartingAt: state.discoveryEpochStartUnixSeconds
            ).beaconCutoff
        let core = try Alpha.AvailabilityBeaconCoreDocument(
            discoveryEpochStartUnixSeconds:
                state.discoveryEpochStartUnixSeconds,
            opaquePoolIdentifier: pool.opaqueIdentifier,
            discoveryIdentity: signing.verificationKey,
            relaySetDigest: relaySet.digest,
            proofOfWorkNonce: proofOfWorkNonce,
            expiryUnixSeconds: expiry
        )
        let workCount = try Alpha.AvailabilityBeaconDocument
            .validateWork(for: core)
        let digest = Alpha.AvailabilityBeaconDocument
            .deriveSignatureDigest(core: core, claimedWorkBitCount: workCount)
        let document = try Alpha.AvailabilityBeaconDocument(
            core: core,
            claimedWorkBitCount: workCount,
            signature: signing.signDocumentDigest(digest)
        )
        let event = try makeLocalPrivateDeploymentEvent(
            payload: Alpha.PreManifestNostrPayloadDocument
                .makeAvailabilityBeacon(document),
            createdAtUnixSeconds: createdAtUnixSeconds,
            signing: signing
        )
        return try stageLocalSortedEvent(
            event,
            replacing: events.count,
            relaySet: relaySet
        )
    }

    @_spi(MosaicPrivateAlpha)
    public func prepareCandidateSetAcknowledgement(
        createdAtUnixSeconds: UInt64,
        signing: consuming OpalFusion.MosaicPrivateAlphaRuntime
            .PrivateDeploymentSigningCapability
    ) throws -> OpalFusion.MosaicPrivateAlphaRuntime.Step {
        typealias Alpha = OpalFusion.Mosaic.OpalMainnetAlpha
        typealias Runtime = OpalFusion.MosaicPrivateAlphaRuntime
        guard !loadedRecoveryNeedsDirective,
              case let .candidateSetAgreement(selection, events, _) =
                try formationState(),
              selection.selectedBeacons.contains(where: {
                  $0.core.discoveryIdentity == signing.verificationKey
              }) else {
            throw Runtime.Failure.invalidStateTransition
        }
        let expiry = try Alpha.PrivateDeploymentPolicy.frozen
            .preManifestDeadlines(
                forEpochStartingAt: state.discoveryEpochStartUnixSeconds
            ).candidateSetAgreement
        let digest = try Alpha.CandidateSetAcknowledgementDocument
            .deriveSignatureDigest(
                discoveryEpochStartUnixSeconds:
                    state.discoveryEpochStartUnixSeconds,
                candidateSetDigest: selection.candidateSetDigest,
                signerDiscoveryIdentity: signing.verificationKey,
                expiryUnixSeconds: expiry
            )
        let document = try Alpha.CandidateSetAcknowledgementDocument(
            discoveryEpochStartUnixSeconds:
                state.discoveryEpochStartUnixSeconds,
            candidateSetDigest: selection.candidateSetDigest,
            signerDiscoveryIdentity: signing.verificationKey,
            expiryUnixSeconds: expiry,
            signature: signing.signDocumentDigest(digest)
        )
        let event = try makeLocalPrivateDeploymentEvent(
            payload: Alpha.PreManifestNostrPayloadDocument
                .makeCandidateSetAcknowledgement(document),
            createdAtUnixSeconds: createdAtUnixSeconds,
            signing: signing
        )
        return try stageLocalSortedEvent(
            event,
            replacing: events.count,
            relaySet: try privateDeploymentRelaySet()
        )
    }

    @_spi(MosaicPrivateAlpha)
    public func prepareCandidateAdmission(
        createdAtUnixSeconds: UInt64,
        discoverySigning: consuming OpalFusion.MosaicPrivateAlphaRuntime
            .PrivateDeploymentSigningCapability,
        controlSigning: consuming OpalFusion.MosaicPrivateAlphaRuntime
            .PrivateDeploymentSigningCapability
    ) throws -> OpalFusion.MosaicPrivateAlphaRuntime.Step {
        typealias Alpha = OpalFusion.Mosaic.OpalMainnetAlpha
        typealias Attempt = OpalFusion.Mosaic.Attempt
        typealias Runtime = OpalFusion.MosaicPrivateAlphaRuntime
        guard !loadedRecoveryNeedsDirective,
              case let .admission(selection, _, events, _) =
                try formationState(),
              selection.selectedBeacons.contains(where: {
                  $0.core.discoveryIdentity
                    == discoverySigning.verificationKey
              }) else {
            throw Runtime.Failure.invalidStateTransition
        }
        let controlIdentity = Attempt.ControlIdentity(
            validatedBytes: [UInt8](
                controlSigning.verificationKey.rawRepresentation
            )
        )
        let expiry = try Alpha.PrivateDeploymentPolicy.frozen
            .preManifestDeadlines(
                forEpochStartingAt: state.discoveryEpochStartUnixSeconds
            ).controlRosterAgreement
        let digest = try Alpha.CandidateAdmissionDocument
            .deriveSignatureDigest(
                discoveryEpochStartUnixSeconds:
                    state.discoveryEpochStartUnixSeconds,
                candidateSetDigest: selection.candidateSetDigest,
                discoveryIdentity: discoverySigning.verificationKey,
                controlIdentity: controlIdentity,
                expiryUnixSeconds: expiry
            )
        let document = try Alpha.CandidateAdmissionDocument(
            discoveryEpochStartUnixSeconds:
                state.discoveryEpochStartUnixSeconds,
            candidateSetDigest: selection.candidateSetDigest,
            discoveryIdentity: discoverySigning.verificationKey,
            controlIdentity: controlIdentity,
            expiryUnixSeconds: expiry,
            discoverySignature:
                discoverySigning.signDocumentDigest(digest),
            controlSignature: controlSigning.signDocumentDigest(digest)
        )
        let event = try makeLocalPrivateDeploymentEvent(
            payload: Alpha.PreManifestNostrPayloadDocument
                .makeCandidateAdmission(document),
            createdAtUnixSeconds: createdAtUnixSeconds,
            signing: discoverySigning
        )
        return try stageLocalSortedEvent(
            event,
            replacing: events.count,
            relaySet: try privateDeploymentRelaySet()
        )
    }

    @_spi(MosaicPrivateAlpha)
    public func prepareRoleCommitment(
        randomness: Data,
        createdAtUnixSeconds: UInt64,
        signing: consuming OpalFusion.MosaicPrivateAlphaRuntime
            .PrivateDeploymentSigningCapability
    ) throws -> OpalFusion.MosaicPrivateAlphaRuntime.Step {
        typealias Alpha = OpalFusion.Mosaic.OpalMainnetAlpha
        typealias Attempt = OpalFusion.Mosaic.Attempt
        typealias Runtime = OpalFusion.MosaicPrivateAlphaRuntime
        guard !loadedRecoveryNeedsDirective,
              case let .controlRosterAgreement(
                  controlRoster,
                  events,
                  _
              ) = try formationState() else {
            throw Runtime.Failure.invalidStateTransition
        }
        let identity = Attempt.ControlIdentity(
            validatedBytes: [UInt8](signing.verificationKey.rawRepresentation)
        )
        guard controlRoster.controlRosterBinding.controlIdentities
                .contains(identity) else {
            throw Runtime.Failure.invalidStateTransition
        }
        let commitment = try Alpha.RoleSeedValidator.roleCommitment(
            controlRosterDigest: controlRoster.controlRosterDigest,
            controlIdentity: identity,
            randomness: Array(randomness)
        )
        let document = Attempt.RoleCommitment(
            candidate: identity,
            controlRosterDigest: controlRoster.controlRosterDigest,
            commitment: commitment
        )
        let event = try makeLocalPrivateDeploymentEvent(
            payload: Alpha.PreManifestNostrPayloadDocument.makeRoleCommitment(
                document,
                controlRoster: controlRoster
            ),
            createdAtUnixSeconds: createdAtUnixSeconds,
            signing: signing
        )
        return try stageLocalSortedEvent(
            event,
            replacing: events.count,
            relaySet: try privateDeploymentRelaySet()
        )
    }

    @_spi(MosaicPrivateAlpha)
    public func prepareRoleReveal(
        randomness: Data,
        createdAtUnixSeconds: UInt64,
        signing: consuming OpalFusion.MosaicPrivateAlphaRuntime
            .PrivateDeploymentSigningCapability
    ) throws -> OpalFusion.MosaicPrivateAlphaRuntime.Step {
        typealias Alpha = OpalFusion.Mosaic.OpalMainnetAlpha
        typealias Attempt = OpalFusion.Mosaic.Attempt
        typealias Runtime = OpalFusion.MosaicPrivateAlphaRuntime
        guard !loadedRecoveryNeedsDirective,
              case let .roleElection(
                  controlRoster,
                  commitmentSet,
                  events,
                  _
              ) = try formationState() else {
            throw Runtime.Failure.invalidStateTransition
        }
        let identity = Attempt.ControlIdentity(
            validatedBytes: [UInt8](signing.verificationKey.rawRepresentation)
        )
        let expectedCommitment = try Alpha.RoleSeedValidator.roleCommitment(
            controlRosterDigest: controlRoster.controlRosterDigest,
            controlIdentity: identity,
            randomness: Array(randomness)
        )
        guard let storedCommitment = commitmentSet.commitments.first(where: {
            $0.candidate == identity
        }),
        storedCommitment.commitment == expectedCommitment else {
            throw Runtime.Failure.invalidStateTransition
        }
        let document = Attempt.RoleReveal(
            candidate: identity,
            controlRosterDigest: controlRoster.controlRosterDigest,
            randomness: Array(randomness)
        )
        let event = try makeLocalPrivateDeploymentEvent(
            payload: Alpha.PreManifestNostrPayloadDocument.makeRoleReveal(
                document,
                controlRoster: controlRoster
            ),
            createdAtUnixSeconds: createdAtUnixSeconds,
            signing: signing
        )
        return try stageLocalSortedEvent(
            event,
            replacing: events.count,
            relaySet: try privateDeploymentRelaySet()
        )
    }

    @_spi(MosaicPrivateAlpha)
    public func prepareContributorNonceAllocation(
        publicSources: [Data],
        createdAtUnixSeconds: UInt64,
        signing: consuming OpalFusion.MosaicPrivateAlphaRuntime
            .PrivateDeploymentSigningCapability
    ) throws -> OpalFusion.MosaicPrivateAlphaRuntime.Step {
        typealias Alpha = OpalFusion.Mosaic.OpalMainnetAlpha
        typealias Runtime = OpalFusion.MosaicPrivateAlphaRuntime
        guard !loadedRecoveryNeedsDirective,
              case let .nonceAllocationPending(controlRoster, roleElection) =
                try formationState(),
              roleElection.roster.conductor.validatedBytes
                == [UInt8](signing.verificationKey.rawRepresentation),
              publicSources.count == roleElection.roster.contributors.count
        else {
            throw Runtime.Failure.invalidStateTransition
        }
        let allocations = zip(
            roleElection.roster.contributors,
            publicSources
        ).map { contributor, source in
            Alpha.ContributorNonceAllocationDocument
                .ContributorAllocationEntry(
                    contributor: contributor,
                    appGeneratedPublicSource: Array(source)
                )
        }
        let document = try Alpha.ContributorNonceAllocationDocument(
            roleElection: roleElection,
            allocations: allocations
        )
        let event = try makeLocalPrivateDeploymentEvent(
            payload: Alpha.PreManifestNostrPayloadDocument
                .makeContributorNonceAllocation(
                    document,
                    controlRoster: controlRoster,
                    roleElection: roleElection
                ),
            createdAtUnixSeconds: createdAtUnixSeconds,
            signing: signing
        )
        return try stageLocalSingletonEvent(event)
    }

    @_spi(MosaicPrivateAlpha)
    public func prepareManifestProposal(
        authorizationKeys: OpalFusion.MosaicPrivateAlphaRuntime
            .PrivateDeploymentManifestAuthorizationKeys,
        createdAtUnixSeconds: UInt64,
        signing: consuming OpalFusion.MosaicPrivateAlphaRuntime
            .PrivateDeploymentSigningCapability
    ) throws -> OpalFusion.MosaicPrivateAlphaRuntime.Step {
        typealias Alpha = OpalFusion.Mosaic.OpalMainnetAlpha
        typealias Runtime = OpalFusion.MosaicPrivateAlphaRuntime
        guard !loadedRecoveryNeedsDirective,
              case let .manifestProposalPending(
                  pool,
                  relaySet,
                  candidateSelection,
                  controlRoster,
                  roleElection,
                  nonceAllocation
              ) = try formationState(),
              roleElection.roster.conductor.validatedBytes
                == [UInt8](signing.verificationKey.rawRepresentation) else {
            throw Runtime.Failure.invalidStateTransition
        }
        let policy = Alpha.PrivateDeploymentPolicy.frozen
        let phaseStart = try policy.preManifestDeadlines(
            forEpochStartingAt: state.discoveryEpochStartUnixSeconds
        ).manifestAgreement
        let core = try Alpha.RoundManifestCore(
            candidateSetDigest: candidateSelection.candidateSetDigest,
            roleElection: roleElection,
            opaquePoolIdentifier: pool.opaqueIdentifier,
            componentAuthorizationVerificationKey:
                authorizationKeys.component,
            bchSignatureAuthorizationVerificationKey:
                authorizationKeys.bchSignature,
            contributorNonceAllocationDigest: nonceAllocation.digest,
            relaySetDigest: relaySet.digest,
            deadlines: try policy.postManifestDeadlines(
                forPhaseStartingAt: phaseStart
            )
        )
        let validation = try Alpha.PrivateDeploymentManifestValidation(
            discoveryEpochStartUnixSeconds:
                state.discoveryEpochStartUnixSeconds,
            core: core,
            candidateSelection: candidateSelection,
            controlRoster: controlRoster,
            roleElection: roleElection,
            opaquePool: pool,
            relaySet: relaySet,
            nonceAllocation: nonceAllocation
        )
        let proposal = try Alpha.PrivateDeploymentManifestProposalValidation(
            manifest: validation
        )
        let event = try makeLocalPrivateDeploymentEvent(
            payload: Alpha.PreManifestNostrPayloadDocument
                .makeManifestProposal(proposal),
            createdAtUnixSeconds: createdAtUnixSeconds,
            signing: signing
        )
        return try stageLocalSingletonEvent(event)
    }

    @_spi(MosaicPrivateAlpha)
    public func prepareManifestSignature(
        createdAtUnixSeconds: UInt64,
        signing: consuming OpalFusion.MosaicPrivateAlphaRuntime
            .PrivateDeploymentSigningCapability
    ) throws -> OpalFusion.MosaicPrivateAlphaRuntime.Step {
        typealias Alpha = OpalFusion.Mosaic.OpalMainnetAlpha
        typealias Attempt = OpalFusion.Mosaic.Attempt
        typealias Runtime = OpalFusion.MosaicPrivateAlphaRuntime
        guard !loadedRecoveryNeedsDirective,
              case let .manifestSignatures(proposal, events, _) =
                try formationState() else {
            throw Runtime.Failure.invalidStateTransition
        }
        let identity = Attempt.ControlIdentity(
            validatedBytes: [UInt8](signing.verificationKey.rawRepresentation)
        )
        guard proposal.manifest.core.roster.controlIdentities
                .contains(identity) else {
            throw Runtime.Failure.invalidStateTransition
        }
        let signature = Attempt.ManifestSignature(
            signer: identity,
            rawRepresentation: try signing.signDocumentDigest(
                proposal.signatureBinding.roundIdentifier
            )
        )
        let event = try makeLocalPrivateDeploymentEvent(
            payload: Alpha.PreManifestNostrPayloadDocument
                .makeManifestSignature(signature, proposal: proposal),
            createdAtUnixSeconds: createdAtUnixSeconds,
            signing: signing
        )
        return try stageLocalSortedEvent(
            event,
            replacing: events.count,
            relaySet: try privateDeploymentRelaySet()
        )
    }

    func makeLocalPrivateDeploymentEvent(
        payload: OpalFusion.Mosaic.OpalMainnetAlpha
            .PreManifestNostrPayloadDocument,
        createdAtUnixSeconds: UInt64,
        signing: borrowing OpalFusion.MosaicPrivateAlphaRuntime
            .PrivateDeploymentSigningCapability
    ) throws -> OpalFusion.MosaicPrivateAlphaRuntime.PrivateDeploymentEvent {
        try OpalFusion.MosaicPrivateAlphaRuntime.PrivateDeploymentEvent
            .makeLocal(
                payload: payload,
                createdAtUnixSeconds: createdAtUnixSeconds,
                signing: signing
            )
    }

    private func stageLocalSortedEvent(
        _ event: OpalFusion.MosaicPrivateAlphaRuntime.PrivateDeploymentEvent,
        replacing existingEventCount: Int,
        relaySet: OpalFusion.Mosaic.OpalMainnetAlpha.RelaySetDocument
    ) throws -> OpalFusion.MosaicPrivateAlphaRuntime.Step {
        typealias Runtime = OpalFusion.MosaicPrivateAlphaRuntime
        let records = try Array(
            state.preManifestDocuments.suffix(existingEventCount)
        ).map(Runtime.PrivateDeploymentEvent.decodeRecoveryBytes) + [event]
        let keyed = try records.map {
            ($0, try $0.decodeCanonicalNostrEvent().publicKey.rawRepresentation)
        }
        let sorted = keyed.sorted {
            $0.1.lexicographicallyPrecedes($1.1)
        }
        for index in sorted.indices.dropFirst() {
            guard sorted[index - 1].1 != sorted[index].1 else {
                throw Runtime.Failure.invalidPrivateDeploymentProof
            }
        }
        return try stage { candidate in
            candidate.preManifestDocuments.removeLast(existingEventCount)
            candidate.preManifestDocuments += try sorted.map {
                try $0.0.canonicalRecoveryBytes()
            }
            candidate.publicationState = .formation(
                event: event,
                relayEndpointIdentifiers: relaySet.registrations.map {
                    $0.endpoint.normalizedURL
                }
            )
        }
    }

    private func stageLocalSingletonEvent(
        _ event: OpalFusion.MosaicPrivateAlphaRuntime.PrivateDeploymentEvent
    ) throws -> OpalFusion.MosaicPrivateAlphaRuntime.Step {
        let relaySet = try privateDeploymentRelaySet()
        return try stage { candidate in
            candidate.preManifestDocuments.append(
                try event.canonicalRecoveryBytes()
            )
            candidate.publicationState = .formation(
                event: event,
                relayEndpointIdentifiers: relaySet.registrations.map {
                    $0.endpoint.normalizedURL
                }
            )
        }
    }

    func privateDeploymentRelaySet() throws
        -> OpalFusion.Mosaic.OpalMainnetAlpha.RelaySetDocument {
        typealias Runtime = OpalFusion.MosaicPrivateAlphaRuntime
        guard state.preManifestDocuments.count >= 2 else {
            throw Runtime.Failure.invalidStateTransition
        }
        return try OpalFusion.Mosaic.OpalMainnetAlpha.RelaySetDocument.decode(
            from: Array(state.preManifestDocuments[1])
        )
    }
}
#endif

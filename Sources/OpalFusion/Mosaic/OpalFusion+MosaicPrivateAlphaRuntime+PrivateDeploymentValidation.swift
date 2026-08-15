// OpalFusion+MosaicPrivateAlphaRuntime+PrivateDeploymentValidation.swift

#if os(macOS)
import Foundation

extension OpalFusion.MosaicPrivateAlphaRuntime {
    /// Validates a complete private-deployment transcript from its exact signed events.
    static func validatePrivateDeployment(
        discoveryEpochStartUnixSeconds: UInt64,
        opaquePoolDocument: Data,
        relaySetDocument: Data,
        availabilityBeaconEvents: [PrivateDeploymentEvent],
        candidateSetAcknowledgementEvents: [PrivateDeploymentEvent],
        candidateAdmissionEvents: [PrivateDeploymentEvent],
        roleCommitmentEvents: [PrivateDeploymentEvent],
        roleRevealEvents: [PrivateDeploymentEvent],
        contributorNonceAllocationEvent: PrivateDeploymentEvent,
        manifestProposalEvent: PrivateDeploymentEvent,
        manifestSignatureEvents: [PrivateDeploymentEvent],
        completeManifestDocument: Data
    ) throws -> PrivateDeploymentProof {
        typealias Alpha = OpalFusion.Mosaic.OpalMainnetAlpha
        typealias Attempt = OpalFusion.Mosaic.Attempt
        typealias Nostr = OpalFusion.Mosaic.NostrNamespace

        do {
            func decodeEvent(
                _ stored: PrivateDeploymentEvent
            ) throws -> Nostr.Event {
                try stored.decodeCanonicalNostrEvent()
            }
            func requireUniqueEvents(
                _ events: [PrivateDeploymentEvent]
            ) throws {
                guard Set(events.map(\.canonicalEventBytes)).count
                        == events.count else {
                    throw Failure.invalidPrivateDeploymentProof
                }
            }

            let pool = try Alpha.OpaquePoolDocument.decode(
                from: Array(opaquePoolDocument)
            )
            let relaySet = try Alpha.RelaySetDocument.decode(
                from: Array(relaySetDocument)
            )
            guard Data(pool.canonicalBytes) == opaquePoolDocument,
                  Data(relaySet.canonicalBytes) == relaySetDocument else {
                throw Failure.invalidPrivateDeploymentProof
            }

            try requireUniqueEvents(availabilityBeaconEvents)
            let decodedBeacons = try availabilityBeaconEvents.map { stored in
                let document = try Alpha.PreManifestNostrCodec
                    .decodeAvailabilityBeacon(
                        decodeEvent(stored),
                        discoveryEpochStartUnixSeconds:
                            discoveryEpochStartUnixSeconds,
                        currentUnixSeconds: stored.acceptedAtUnixSeconds
                    )
                return (stored, document)
            }
            let candidateSelection = try Alpha.CandidateSelectionValidation(
                beacons: decodedBeacons.map(\.1),
                discoveryEpochStartUnixSeconds:
                    discoveryEpochStartUnixSeconds,
                opaquePool: pool,
                relaySet: relaySet
            )
            guard decodedBeacons.count
                    == candidateSelection.selectedBeacons.count else {
                throw Failure.invalidPrivateDeploymentProof
            }
            let selectedBeaconEvents = try candidateSelection.selectedBeacons
                .map { selected in
                    guard let event = decodedBeacons.first(where: {
                        $0.1 == selected
                    })?.0 else {
                        throw Failure.invalidPrivateDeploymentProof
                    }
                    return event
                }

            try requireUniqueEvents(candidateSetAcknowledgementEvents)
            let decodedAcknowledgements = try
                candidateSetAcknowledgementEvents.map { stored in
                    let document = try Alpha.PreManifestNostrCodec
                        .decodeCandidateSetAcknowledgement(
                            decodeEvent(stored),
                            candidateSelection: candidateSelection,
                            currentUnixSeconds: stored.acceptedAtUnixSeconds
                        )
                    return (stored, document)
                }
            let acknowledgementSet = try Alpha
                .CandidateSetAcknowledgementSetDocument(
                    acknowledgements: decodedAcknowledgements.map(\.1),
                    candidateSelection: candidateSelection
                )
            let acknowledgementEvents = try acknowledgementSet
                .acknowledgements.map { acknowledgement in
                    guard let event = decodedAcknowledgements.first(where: {
                        $0.1 == acknowledgement
                    })?.0 else {
                        throw Failure.invalidPrivateDeploymentProof
                    }
                    return event
                }

            try requireUniqueEvents(candidateAdmissionEvents)
            let decodedAdmissions = try candidateAdmissionEvents.map { stored in
                let document = try Alpha.PreManifestNostrCodec
                    .decodeCandidateAdmission(
                        decodeEvent(stored),
                        candidateSelection: candidateSelection,
                        acknowledgementSet: acknowledgementSet,
                        currentUnixSeconds: stored.acceptedAtUnixSeconds
                    )
                return (stored, document)
            }
            let controlRoster = try Alpha.ControlRosterValidation(
                admissions: decodedAdmissions.map(\.1),
                candidateSelection: candidateSelection,
                acknowledgementSet: acknowledgementSet
            )
            let admissionEvents = try controlRoster.admissions.map { admission in
                guard let event = decodedAdmissions.first(where: {
                    $0.1 == admission
                })?.0 else {
                    throw Failure.invalidPrivateDeploymentProof
                }
                return event
            }

            try requireUniqueEvents(roleCommitmentEvents)
            let decodedCommitments = try roleCommitmentEvents.map { stored in
                let document = try Alpha.PreManifestNostrCodec
                    .decodeRoleCommitment(
                        decodeEvent(stored),
                        controlRoster: controlRoster,
                        currentUnixSeconds: stored.acceptedAtUnixSeconds
                    )
                return (stored, document)
            }
            let commitmentSet = try Attempt.RoleCommitmentSet(
                controlRoster: controlRoster.controlRosterBinding,
                commitments: decodedCommitments.map(\.1)
            )
            let commitmentEvents = try commitmentSet.commitments.map {
                commitment in
                guard let event = decodedCommitments.first(where: {
                    $0.1 == commitment
                })?.0 else {
                    throw Failure.invalidPrivateDeploymentProof
                }
                return event
            }

            try requireUniqueEvents(roleRevealEvents)
            let decodedReveals = try roleRevealEvents.map { stored in
                let document = try Alpha.PreManifestNostrCodec.decodeRoleReveal(
                    decodeEvent(stored),
                    controlRoster: controlRoster,
                    currentUnixSeconds: stored.acceptedAtUnixSeconds
                )
                return (stored, document)
            }
            let roleSeed = try Attempt.RoleSeedValidation(
                profile: .opalMainnetAlpha,
                commitmentSet: commitmentSet,
                reveals: decodedReveals.map(\.1),
                using: Alpha.RoleSeedValidator()
            )
            let roleElection = try Attempt.RoleElectionResult(
                profile: .opalMainnetAlpha,
                commitmentSet: commitmentSet,
                validation: roleSeed
            )
            let revealEvents = try roleSeed.revealSet.reveals.map { reveal in
                guard let event = decodedReveals.first(where: {
                    $0.1 == reveal
                })?.0 else {
                    throw Failure.invalidPrivateDeploymentProof
                }
                return event
            }

            let nonceAllocation = try Alpha.PreManifestNostrCodec
                .decodeContributorNonceAllocation(
                    decodeEvent(contributorNonceAllocationEvent),
                    controlRoster: controlRoster,
                    roleElection: roleElection,
                    currentUnixSeconds:
                        contributorNonceAllocationEvent.acceptedAtUnixSeconds
                )
            let proposalContext = try Alpha.ManifestProposalContext(
                roleElection: roleElection,
                candidateSetDigest: candidateSelection.candidateSetDigest,
                opaquePoolIdentifier: pool.opaqueIdentifier
            )
            let proposalNostrEvent = try decodeEvent(manifestProposalEvent)
            let manifestCore = try Alpha.PreManifestNostrCodec
                .decodeManifestProposalCandidate(
                    proposalNostrEvent,
                    discoveryEpochStartUnixSeconds:
                        discoveryEpochStartUnixSeconds,
                    proposalContext: proposalContext,
                    currentUnixSeconds:
                        manifestProposalEvent.acceptedAtUnixSeconds
                )
            let manifestValidation = try Alpha
                .PrivateDeploymentManifestValidation(
                    discoveryEpochStartUnixSeconds:
                        discoveryEpochStartUnixSeconds,
                    core: manifestCore,
                    candidateSelection: candidateSelection,
                    controlRoster: controlRoster,
                    roleElection: roleElection,
                    opaquePool: pool,
                    relaySet: relaySet,
                    nonceAllocation: nonceAllocation
                )
            let proposalValidation = try Alpha
                .PrivateDeploymentManifestProposalValidation(
                    manifest: manifestValidation
                )
            guard try Alpha.PreManifestNostrCodec.decodeManifestProposal(
                proposalNostrEvent,
                proposal: proposalValidation,
                currentUnixSeconds:
                    manifestProposalEvent.acceptedAtUnixSeconds
            ) == manifestCore else {
                throw Failure.invalidPrivateDeploymentProof
            }

            try requireUniqueEvents(manifestSignatureEvents)
            let decodedSignatures = try manifestSignatureEvents.map { stored in
                let validation = try Alpha.PreManifestNostrCodec
                    .decodeManifestSignature(
                        decodeEvent(stored),
                        proposal: proposalValidation,
                        currentUnixSeconds: stored.acceptedAtUnixSeconds
                    )
                return (stored, validation)
            }
            _ = try Attempt.ManifestAgreement(
                roster: manifestCore.roster,
                validatedSignatures: decodedSignatures.map(\.1.validation)
            )
            let normalizedSignatures = decodedSignatures.map(\.1.signature)
                .sorted {
                    $0.signer.validatedBytes.lexicographicallyPrecedes(
                        $1.signer.validatedBytes
                    )
                }
            let signatureEvents = try normalizedSignatures.map { signature in
                guard let event = decodedSignatures.first(where: {
                    $0.1.signature == signature
                })?.0 else {
                    throw Failure.invalidPrivateDeploymentProof
                }
                return event
            }
            let completeManifest = try Alpha.CanonicalWireCodec.decodeManifest(
                from: Array(completeManifestDocument),
                expectedContext: proposalContext
            )
            guard completeManifest.core == manifestCore,
                  completeManifest.signatures == normalizedSignatures,
                  Data(completeManifest.canonicalBytes)
                    == completeManifestDocument else {
                throw Failure.invalidPrivateDeploymentProof
            }

            var attempt = Attempt(
                configuration: .init(profile: .opalMainnetAlpha)
            )
            guard attempt.apply(input: .discoveryCompleted(
                candidateCount: candidateSelection.selectedBeacons.count
            )).isEmpty,
                attempt.apply(input: .candidateSetAgreementValidated).isEmpty,
                attempt.apply(input: .controlRosterValidated(
                    controlRoster.controlRosterBinding
                )).isEmpty,
                attempt.apply(input: .roleCommitmentsReceived(
                    commitmentSet.commitments
                )).isEmpty,
                attempt.apply(input: .roleElectionValidated(roleSeed)).isEmpty,
                case .manifestAgreement = attempt.state else {
                throw Failure.invalidPrivateDeploymentProof
            }

            var canonicalDocuments: [Data] = [
                Data(pool.canonicalBytes),
                Data(relaySet.canonicalBytes),
            ]
            canonicalDocuments += try selectedBeaconEvents.map {
                try $0.canonicalRecoveryBytes()
            }
            canonicalDocuments += try acknowledgementEvents.map {
                try $0.canonicalRecoveryBytes()
            }
            canonicalDocuments += try admissionEvents.map {
                try $0.canonicalRecoveryBytes()
            }
            canonicalDocuments += try commitmentEvents.map {
                try $0.canonicalRecoveryBytes()
            }
            canonicalDocuments += try revealEvents.map {
                try $0.canonicalRecoveryBytes()
            }
            canonicalDocuments += [
                try contributorNonceAllocationEvent.canonicalRecoveryBytes(),
                try manifestProposalEvent.canonicalRecoveryBytes(),
            ]
            canonicalDocuments += try signatureEvents.map {
                try $0.canonicalRecoveryBytes()
            }
            canonicalDocuments.append(Data(completeManifest.canonicalBytes))

            return .init(
                validatedAttempt: attempt,
                proposalValidation: proposalValidation,
                completeManifest: completeManifest,
                canonicalDocuments: canonicalDocuments
            )
        } catch let failure as Failure {
            throw failure
        } catch {
            throw Failure.invalidPrivateDeploymentProof
        }
    }
}
#endif

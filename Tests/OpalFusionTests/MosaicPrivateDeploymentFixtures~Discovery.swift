// MosaicPrivateDeploymentFixtures~Discovery.swift

import Foundation
@_spi(MosaicPrivateAlpha) @testable import OpalFusion

extension MosaicPrivateDeploymentFixtures {
    private static let beaconProofOfWorkNonces: [UInt64] = [
        988_699,
        20_377_683,
        41_136_949,
        60_349_466,
        81_284_867,
        100_918_419,
        120_512_972,
        140_022_629,
        161_485_851,
        182_020_711,
    ]

    static func makeDiscovery(candidateCount: Int) throws -> Discovery {
        let epochStart: UInt64 = 1_800_000_000
        let pool = try Alpha.OpaquePoolDocument(
            appGeneratedOpaqueIdentifier: [UInt8](repeating: 0x31, count: 32)
        )
        let relaySet = try makeRelaySet()
        let candidates = try (1 ... candidateCount).map {
            try CandidateKeyMaterial(scalar: UInt8($0))
        }
        let beacons = try zip(candidates, beaconProofOfWorkNonces).map {
            candidate, nonce in
            try makeBeacon(
                candidate: candidate,
                epochStart: epochStart,
                pool: pool,
                relaySet: relaySet,
                proofOfWorkNonce: nonce
            )
        }
        return .init(
            epochStart: epochStart,
            pool: pool,
            relaySet: relaySet,
            candidates: candidates,
            beacons: beacons
        )
    }

    static func makeBeacon(
        candidate: CandidateKeyMaterial,
        epochStart: UInt64,
        pool: Alpha.OpaquePoolDocument,
        relaySet: Alpha.RelaySetDocument,
        proofOfWorkNonce: UInt64,
        auxiliaryByte: UInt8 = 0xA5
    ) throws -> Alpha.AvailabilityBeaconDocument {
        let expiry = try Alpha.PrivateDeploymentPolicy.frozen
            .preManifestDeadlines(forEpochStartingAt: epochStart).beaconCutoff
        let core = try Alpha.AvailabilityBeaconCoreDocument(
            discoveryEpochStartUnixSeconds: epochStart,
            opaquePoolIdentifier: pool.opaqueIdentifier,
            discoveryIdentity: candidate.identity,
            relaySetDigest: relaySet.digest,
            proofOfWorkNonce: proofOfWorkNonce,
            expiryUnixSeconds: expiry
        )
        let workBitCount = try Alpha.AvailabilityBeaconDocument
            .validateWork(for: core)
        let digest = Alpha.AvailabilityBeaconDocument.deriveSignatureDigest(
            core: core,
            claimedWorkBitCount: workBitCount
        )
        return try .init(
            core: core,
            claimedWorkBitCount: workBitCount,
            signature: sign(
                digestBytes: digest,
                using: candidate.signingKey,
                auxiliaryByte: auxiliaryByte
            )
        )
    }

    static func makeAcknowledgement(
        selection: Alpha.CandidateSelectionValidation,
        candidate: CandidateKeyMaterial
    ) throws -> Alpha.CandidateSetAcknowledgementDocument {
        let expiry = try Alpha.PrivateDeploymentPolicy.frozen
            .preManifestDeadlines(
                forEpochStartingAt: selection.discoveryEpochStartUnixSeconds
            ).candidateSetAgreement
        let digest = try Alpha.CandidateSetAcknowledgementDocument
            .deriveSignatureDigest(
                discoveryEpochStartUnixSeconds:
                    selection.discoveryEpochStartUnixSeconds,
                candidateSetDigest: selection.candidateSetDigest,
                signerDiscoveryIdentity: candidate.identity,
                expiryUnixSeconds: expiry
            )
        return try .init(
            discoveryEpochStartUnixSeconds:
                selection.discoveryEpochStartUnixSeconds,
            candidateSetDigest: selection.candidateSetDigest,
            signerDiscoveryIdentity: candidate.identity,
            expiryUnixSeconds: expiry,
            signature: sign(
                digestBytes: digest,
                using: candidate.signingKey,
                auxiliaryByte: 0xB1
            )
        )
    }

    static func makeAdmission(
        selection: Alpha.CandidateSelectionValidation,
        discoveryCandidate: CandidateKeyMaterial,
        controlCandidate: CandidateKeyMaterial
    ) throws -> Alpha.CandidateAdmissionDocument {
        let expiry = try Alpha.PrivateDeploymentPolicy.frozen
            .preManifestDeadlines(
                forEpochStartingAt: selection.discoveryEpochStartUnixSeconds
            ).controlRosterAgreement
        let digest = try Alpha.CandidateAdmissionDocument.deriveSignatureDigest(
            discoveryEpochStartUnixSeconds:
                selection.discoveryEpochStartUnixSeconds,
            candidateSetDigest: selection.candidateSetDigest,
            discoveryIdentity: discoveryCandidate.identity,
            controlIdentity: controlCandidate.controlIdentity,
            expiryUnixSeconds: expiry
        )
        return try .init(
            discoveryEpochStartUnixSeconds:
                selection.discoveryEpochStartUnixSeconds,
            candidateSetDigest: selection.candidateSetDigest,
            discoveryIdentity: discoveryCandidate.identity,
            controlIdentity: controlCandidate.controlIdentity,
            expiryUnixSeconds: expiry,
            discoverySignature: sign(
                digestBytes: digest,
                using: discoveryCandidate.signingKey,
                auxiliaryByte: 0xB2
            ),
            controlSignature: sign(
                digestBytes: digest,
                using: controlCandidate.signingKey,
                auxiliaryByte: 0xB3
            )
        )
    }

    static func makeFormation() throws -> Formation {
        let discovery = try makeDiscovery(candidateCount: 10)
        let selection = try Alpha.CandidateSelectionValidation(
            beacons: discovery.beacons,
            discoveryEpochStartUnixSeconds: discovery.epochStart,
            opaquePool: discovery.pool,
            relaySet: discovery.relaySet
        )
        let acknowledgements = try selection.selectedBeacons.map { beacon in
            try makeAcknowledgement(
                selection: selection,
                candidate: discovery.candidate(
                    for: beacon.core.discoveryIdentity
                )
            )
        }
        let acknowledgementSet = try Alpha
            .CandidateSetAcknowledgementSetDocument(
                acknowledgements: acknowledgements,
                candidateSelection: selection
            )
        let controlCandidates = try (21 ..< 21 + selection.selectedBeacons.count)
            .map { try CandidateKeyMaterial(scalar: UInt8($0)) }
        let admissions = try zip(
            selection.selectedBeacons,
            controlCandidates
        ).map { beacon, controlCandidate in
            try makeAdmission(
                selection: selection,
                discoveryCandidate: discovery.candidate(
                    for: beacon.core.discoveryIdentity
                ),
                controlCandidate: controlCandidate
            )
        }
        let controlRoster = try Alpha.ControlRosterValidation(
            admissions: admissions,
            candidateSelection: selection,
            acknowledgementSet: acknowledgementSet
        )
        let reveals = controlRoster.controlRosterBinding.controlIdentities
            .enumerated().map { index, identity in
                Attempt.RoleReveal(
                    candidate: identity,
                    controlRosterDigest: controlRoster.controlRosterDigest,
                    randomness: [UInt8](
                        repeating: UInt8(index + 1),
                        count: 32
                    )
                )
            }
        let commitments = try reveals.map { reveal in
            Attempt.RoleCommitment(
                candidate: reveal.candidate,
                controlRosterDigest: reveal.controlRosterDigest,
                commitment: try Alpha.RoleSeedValidator.roleCommitment(
                    controlRosterDigest: reveal.controlRosterDigest,
                    controlIdentity: reveal.candidate,
                    randomness: reveal.randomness
                )
            )
        }
        let commitmentSet = try Attempt.RoleCommitmentSet(
            controlRoster: controlRoster.controlRosterBinding,
            commitments: commitments
        )
        let roleSeed = try Attempt.RoleSeedValidation(
            profile: .opalMainnetAlpha,
            commitmentSet: commitmentSet,
            reveals: reveals,
            using: Alpha.RoleSeedValidator()
        )
        let roleElection = try Attempt.RoleElectionResult(
            profile: .opalMainnetAlpha,
            commitmentSet: commitmentSet,
            validation: roleSeed
        )
        let nonceAllocation = try Alpha.ContributorNonceAllocationDocument(
            roleElection: roleElection,
            allocations: roleElection.roster.contributors.enumerated().map {
                index, contributor in
                .init(
                    contributor: contributor,
                    appGeneratedPublicSource: [UInt8](
                        repeating: UInt8(0x80 + index),
                        count: 32
                    )
                )
            }
        )
        return .init(
            discovery: discovery,
            selection: selection,
            acknowledgementSet: acknowledgementSet,
            controlCandidates: controlCandidates,
            controlRoster: controlRoster,
            commitments: commitments,
            reveals: reveals,
            roleElection: roleElection,
            nonceAllocation: nonceAllocation
        )
    }

    static func makeManifestValidation(
        formation: Formation
    ) throws -> Alpha.PrivateDeploymentManifestValidation {
        let policy = Alpha.PrivateDeploymentPolicy.frozen
        let phaseStart = try policy.preManifestDeadlines(
            forEpochStartingAt: formation.discovery.epochStart
        ).manifestAgreement
        let core = try Alpha.RoundManifestCore(
            candidateSetDigest: formation.selection.candidateSetDigest,
            roleElection: formation.roleElection,
            opaquePoolIdentifier: formation.discovery.pool.opaqueIdentifier,
            componentAuthorizationVerificationKey:
                try MosaicMainnetAlphaFixtures.rsaVerificationKey(),
            bchSignatureAuthorizationVerificationKey:
                try MosaicMainnetAlphaFixtures
                    .bchSignatureRSAVerificationKey(),
            contributorNonceAllocationDigest:
                formation.nonceAllocation.digest,
            relaySetDigest: formation.discovery.relaySet.digest,
            deadlines: try policy.postManifestDeadlines(
                forPhaseStartingAt: phaseStart
            )
        )
        return try .init(
            discoveryEpochStartUnixSeconds:
                formation.discovery.epochStart,
            core: core,
            candidateSelection: formation.selection,
            controlRoster: formation.controlRoster,
            roleElection: formation.roleElection,
            opaquePool: formation.discovery.pool,
            relaySet: formation.discovery.relaySet,
            nonceAllocation: formation.nonceAllocation
        )
    }

    static func makeManifestProposalValidation(
        formation: Formation
    ) throws -> Alpha.PrivateDeploymentManifestProposalValidation {
        try .init(manifest: makeManifestValidation(formation: formation))
    }

    static func makeRoundManifest(
        formation: Formation,
        validation: Alpha.PrivateDeploymentManifestValidation
    ) throws -> Alpha.RoundManifest {
        let signatures = try validation.core.roster.controlIdentities
            .enumerated().map { index, signer in
                let candidate = formation.controlCandidate(for: signer)
                return Attempt.ManifestSignature(
                    signer: signer,
                    rawRepresentation: try sign(
                        digestBytes: validation.core.roundIdentifier,
                        using: candidate.signingKey,
                        auxiliaryByte: UInt8(0xC0 + index)
                    )
                )
            }
        return try .init(core: validation.core, signatures: signatures)
    }

    private static let cachedPrivateAlphaRuntimeProof = Result {
        try buildPrivateAlphaRuntimeProof()
    }

    static func makePrivateAlphaRuntimeProof()
        throws -> (
            proof: OpalFusion.MosaicPrivateAlphaRuntime
                .PrivateDeploymentProof,
            formation: Formation,
            epoch: UInt64,
            localControlIdentity: Data,
            opaquePoolDocument: Data,
            relaySetDocument: Data,
            beaconEvents: [OpalFusion.MosaicPrivateAlphaRuntime
                .PrivateDeploymentEvent],
            acknowledgementEvents: [OpalFusion.MosaicPrivateAlphaRuntime
                .PrivateDeploymentEvent],
            admissionEvents: [OpalFusion.MosaicPrivateAlphaRuntime
                .PrivateDeploymentEvent],
            commitmentEvents: [OpalFusion.MosaicPrivateAlphaRuntime
                .PrivateDeploymentEvent],
            revealEvents: [OpalFusion.MosaicPrivateAlphaRuntime
                .PrivateDeploymentEvent],
            nonceEvent: OpalFusion.MosaicPrivateAlphaRuntime
                .PrivateDeploymentEvent,
            proposalEvent: OpalFusion.MosaicPrivateAlphaRuntime
                .PrivateDeploymentEvent,
            signatureEvents: [OpalFusion.MosaicPrivateAlphaRuntime
                .PrivateDeploymentEvent],
            completeManifestDocument: Data
        ) {
        try cachedPrivateAlphaRuntimeProof.get()
    }

    private static func buildPrivateAlphaRuntimeProof()
        throws -> (
            proof: OpalFusion.MosaicPrivateAlphaRuntime
                .PrivateDeploymentProof,
            formation: Formation,
            epoch: UInt64,
            localControlIdentity: Data,
            opaquePoolDocument: Data,
            relaySetDocument: Data,
            beaconEvents: [OpalFusion.MosaicPrivateAlphaRuntime
                .PrivateDeploymentEvent],
            acknowledgementEvents: [OpalFusion.MosaicPrivateAlphaRuntime
                .PrivateDeploymentEvent],
            admissionEvents: [OpalFusion.MosaicPrivateAlphaRuntime
                .PrivateDeploymentEvent],
            commitmentEvents: [OpalFusion.MosaicPrivateAlphaRuntime
                .PrivateDeploymentEvent],
            revealEvents: [OpalFusion.MosaicPrivateAlphaRuntime
                .PrivateDeploymentEvent],
            nonceEvent: OpalFusion.MosaicPrivateAlphaRuntime
                .PrivateDeploymentEvent,
            proposalEvent: OpalFusion.MosaicPrivateAlphaRuntime
                .PrivateDeploymentEvent,
            signatureEvents: [OpalFusion.MosaicPrivateAlphaRuntime
                .PrivateDeploymentEvent],
            completeManifestDocument: Data
        ) {
        let formation = try makeFormation()
        let proposal = try makeManifestProposalValidation(
            formation: formation
        )
        let manifest = try makeRoundManifest(
            formation: formation,
            validation: proposal.manifest
        )
        let limits = try OpalFusion.Mosaic.NostrNamespace.EventCodingLimits(
            maximumEventJSONByteCount: 200_000,
            maximumTagCount: 1,
            maximumTagElementCount: 2,
            maximumStringByteCount: 150_000
        )
        func storedEvent(
            payload: Alpha.PreManifestNostrPayloadDocument,
            candidate: CandidateKeyMaterial,
            createdAt: UInt64,
            auxiliaryByte: UInt8
        ) throws -> OpalFusion.MosaicPrivateAlphaRuntime
            .PrivateDeploymentEvent {
            let event = try Alpha.PreManifestNostrCodec.makeEvent(
                for: payload,
                createdAtUnixSeconds: createdAt,
                using: candidate.signingKey,
                auxiliaryRandomness: .init(
                    rawRepresentation: Data(
                        repeating: auxiliaryByte,
                        count: 32
                    )
                ),
                limits: limits
            )
            return try .init(
                canonicalEventBytes: try OpalFusion.Mosaic.NostrNamespace
                    .EventCodec.encode(event, limits: limits),
                acceptedAtUnixSeconds: createdAt
            )
        }
        let epoch = formation.discovery.epochStart
        let beaconEvents = try formation.selection.selectedBeacons
            .enumerated().map { index, beacon in
                try storedEvent(
                    payload: Alpha.PreManifestNostrPayloadDocument
                        .makeAvailabilityBeacon(beacon),
                    candidate: formation.discovery.candidate(
                        for: beacon.core.discoveryIdentity
                    ),
                    createdAt: epoch + 1,
                    auxiliaryByte: UInt8(0x20 + index)
                )
            }
        let acknowledgementEvents = try formation.acknowledgementSet
            .acknowledgements.enumerated().map { index, acknowledgement in
                try storedEvent(
                    payload: Alpha.PreManifestNostrPayloadDocument
                        .makeCandidateSetAcknowledgement(acknowledgement),
                    candidate: formation.discovery.candidate(
                        for: acknowledgement.signerDiscoveryIdentity
                    ),
                    createdAt: epoch + 61,
                    auxiliaryByte: UInt8(0x30 + index)
                )
            }
        let admissionEvents = try formation.controlRoster.admissions
            .enumerated().map { index, admission in
                try storedEvent(
                    payload: Alpha.PreManifestNostrPayloadDocument
                        .makeCandidateAdmission(admission),
                    candidate: formation.discovery.candidate(
                        for: admission.discoveryIdentity
                    ),
                    createdAt: epoch + 91,
                    auxiliaryByte: UInt8(0x40 + index)
                )
            }
        let commitmentEvents = try formation.commitments.enumerated().map {
            index, commitment in
            try storedEvent(
                payload: Alpha.PreManifestNostrPayloadDocument
                    .makeRoleCommitment(
                        commitment,
                        controlRoster: formation.controlRoster
                    ),
                candidate: formation.controlCandidate(
                    for: commitment.candidate
                ),
                createdAt: epoch + 121,
                auxiliaryByte: UInt8(0x50 + index)
            )
        }
        let revealEvents = try formation.reveals.enumerated().map {
            index, reveal in
            try storedEvent(
                payload: Alpha.PreManifestNostrPayloadDocument.makeRoleReveal(
                    reveal,
                    controlRoster: formation.controlRoster
                ),
                candidate: formation.controlCandidate(for: reveal.candidate),
                createdAt: epoch + 151,
                auxiliaryByte: UInt8(0x60 + index)
            )
        }
        let nonceEvent = try storedEvent(
            payload: Alpha.PreManifestNostrPayloadDocument
                .makeContributorNonceAllocation(
                    formation.nonceAllocation,
                    controlRoster: formation.controlRoster,
                    roleElection: formation.roleElection
                ),
            candidate: formation.controlCandidate(
                for: formation.roleElection.roster.conductor
            ),
            createdAt: epoch + 181,
            auxiliaryByte: 0x70
        )
        let proposalEvent = try storedEvent(
            payload: Alpha.PreManifestNostrPayloadDocument
                .makeManifestProposal(proposal),
            candidate: formation.controlCandidate(
                for: proposal.manifest.core.roster.conductor
            ),
            createdAt: epoch + 182,
            auxiliaryByte: 0x71
        )
        let signatureEvents = try manifest.signatures.enumerated().map {
            index, signature in
            try storedEvent(
                payload: Alpha.PreManifestNostrPayloadDocument
                    .makeManifestSignature(signature, proposal: proposal),
                candidate: formation.controlCandidate(for: signature.signer),
                createdAt: epoch + 183,
                auxiliaryByte: UInt8(0x80 + index)
            )
        }
        let proof = try OpalFusion.MosaicPrivateAlphaRuntime
            .validatePrivateDeployment(
                discoveryEpochStartUnixSeconds:
                    formation.discovery.epochStart,
                opaquePoolDocument: Data(
                    formation.discovery.pool.canonicalBytes
                ),
                relaySetDocument: Data(
                    formation.discovery.relaySet.canonicalBytes
                ),
                availabilityBeaconEvents: beaconEvents,
                candidateSetAcknowledgementEvents: acknowledgementEvents,
                candidateAdmissionEvents: admissionEvents,
                roleCommitmentEvents: commitmentEvents,
                roleRevealEvents: revealEvents,
                contributorNonceAllocationEvent: nonceEvent,
                manifestProposalEvent: proposalEvent,
                manifestSignatureEvents: signatureEvents,
                completeManifestDocument: Data(manifest.canonicalBytes)
            )
        return (
            proof,
            formation,
            formation.discovery.epochStart,
            Data(formation.roleElection.roster.conductor.validatedBytes),
            Data(formation.discovery.pool.canonicalBytes),
            Data(formation.discovery.relaySet.canonicalBytes),
            beaconEvents,
            acknowledgementEvents,
            admissionEvents,
            commitmentEvents,
            revealEvents,
            nonceEvent,
            proposalEvent,
            signatureEvents,
            Data(manifest.canonicalBytes)
        )
    }

    private static func makeRelaySet() throws -> Alpha.RelaySetDocument {
        let registrations = try (1 ... 3).map { index in
            try Alpha.RelayRegistrationDocument(
                endpoint: Alpha.PrivateRelayEndpoint(
                    normalizing: "wss://relay-\(index).example/"
                ),
                operatorIdentity: Alpha.RelayOperatorIdentity(
                    appReviewedRegistryLabel: "fixture operator \(index)"
                ),
                requiresNIP42Authentication: false,
                requiresProofOfWork: false
            )
        }
        return try .init(registrations: registrations)
    }
}

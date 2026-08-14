// MosaicPrivateDeploymentFixtures~Discovery.swift

@testable import OpalFusion

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

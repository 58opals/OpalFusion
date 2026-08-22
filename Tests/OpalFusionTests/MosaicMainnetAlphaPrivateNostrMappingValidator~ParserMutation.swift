// MosaicMainnetAlphaPrivateNostrMappingValidator~ParserMutation.swift

import Foundation
import Testing
@testable import OpalFusion

extension MosaicMainnetAlphaPrivateNostrMappingValidator {
    @Test(
        "Mutate typed pre-manifest Nostr parsers",
        .timeLimit(.minutes(1))
    )
    func mutateTypedPreManifestNostrParsers() throws {
        let formation = try MosaicPrivateDeploymentFixtures.makeFormation()
        let epochStart = formation.discovery.epochStart
        let beacon = formation.discovery.beacons[0]
        let beaconCandidate = formation.discovery.candidate(
            for: beacon.core.discoveryIdentity
        )
        let acknowledgement = formation.acknowledgementSet
            .acknowledgements[0]
        let acknowledgementCandidate = formation.discovery.candidate(
            for: acknowledgement.signerDiscoveryIdentity
        )
        let admission = formation.controlRoster.admissions[0]
        let admissionCandidate = formation.discovery.candidate(
            for: admission.discoveryIdentity
        )
        let commitment = formation.commitments[0]
        let reveal = formation.reveals[0]
        let controlCandidate = formation.controlCandidate(
            for: commitment.candidate
        )
        let proposal = try MosaicPrivateDeploymentFixtures
            .makeManifestProposalValidation(formation: formation)
        let conductor = formation.controlCandidate(
            for: proposal.manifest.core.roster.conductor
        )
        let signatureSigner = proposal.manifest.core.roster
            .controlIdentities[0]
        let signatureCandidate = formation.controlCandidate(
            for: signatureSigner
        )
        let signature = Attempt.ManifestSignature(
            signer: signatureSigner,
            rawRepresentation: try MosaicPrivateDeploymentFixtures.sign(
                digestBytes: proposal.manifest.core.roundIdentifier,
                using: signatureCandidate.signingKey,
                auxiliaryByte: 0xB7
            )
        )
        let abortAuthority = try Alpha.PrivateDeploymentAbortAuthority
            .makeRoleSelectionAuthority(
                participant: signatureSigner,
                controlRoster: formation.controlRoster
            )
        let abort = try Alpha.PrivateDeploymentAbortDocument(
            discoveryEpochStartUnixSeconds: epochStart,
            phase: .roleSelection,
            context: abortAuthority.context,
            reason: .missingRequiredParticipant
        )

        let availabilityEvent = try makeEvent(
            payload: .makeAvailabilityBeacon(beacon),
            candidate: beaconCandidate,
            createdAt: epochStart + 1,
            auxiliaryByte: 0xB8
        )
        let acknowledgementEvent = try makeEvent(
            payload: .makeCandidateSetAcknowledgement(acknowledgement),
            candidate: acknowledgementCandidate,
            createdAt: epochStart + 61,
            auxiliaryByte: 0xB9
        )
        let admissionEvent = try makeEvent(
            payload: .makeCandidateAdmission(admission),
            candidate: admissionCandidate,
            createdAt: epochStart + 91,
            auxiliaryByte: 0xBA
        )
        let commitmentEvent = try makeEvent(
            payload: .makeRoleCommitment(
                commitment,
                controlRoster: formation.controlRoster
            ),
            candidate: controlCandidate,
            createdAt: epochStart + 121,
            auxiliaryByte: 0xBB
        )
        let revealEvent = try makeEvent(
            payload: .makeRoleReveal(
                reveal,
                controlRoster: formation.controlRoster
            ),
            candidate: controlCandidate,
            createdAt: epochStart + 151,
            auxiliaryByte: 0xBC
        )
        let proposalEvent = try makeEvent(
            payload: .makeManifestProposal(proposal),
            candidate: conductor,
            createdAt: epochStart + 181,
            auxiliaryByte: 0xBD
        )
        let signatureEvent = try makeEvent(
            payload: .makeManifestSignature(signature, proposal: proposal),
            candidate: signatureCandidate,
            createdAt: epochStart + 182,
            auxiliaryByte: 0xBE
        )
        let nonceEvent = try makeEvent(
            payload: .makeContributorNonceAllocation(
                formation.nonceAllocation,
                controlRoster: formation.controlRoster,
                roleElection: formation.roleElection
            ),
            candidate: conductor,
            createdAt: epochStart + 181,
            auxiliaryByte: 0xBF
        )
        let abortEvent = try makeEvent(
            payload: .makeAbort(abort, authority: abortAuthority),
            candidate: signatureCandidate,
            createdAt: epochStart + 181,
            auxiliaryByte: 0xC0
        )

        let vectors = try [
            semanticEventVector(
                name: "pre-manifest availability beacon",
                event: availabilityEvent
            ) {
                _ = try Alpha.PreManifestNostrCodec
                    .decodeAvailabilityBeacon(
                        $0,
                        discoveryEpochStartUnixSeconds: epochStart,
                        currentUnixSeconds: epochStart + 1
                    )
            },
            semanticEventVector(
                name: "pre-manifest candidate-set acknowledgement",
                event: acknowledgementEvent
            ) {
                _ = try Alpha.PreManifestNostrCodec
                    .decodeCandidateSetAcknowledgement(
                        $0,
                        candidateSelection: formation.selection,
                        currentUnixSeconds: epochStart + 61
                    )
            },
            semanticEventVector(
                name: "pre-manifest candidate admission",
                event: admissionEvent
            ) {
                _ = try Alpha.PreManifestNostrCodec
                    .decodeCandidateAdmission(
                        $0,
                        candidateSelection: formation.selection,
                        acknowledgementSet: formation.acknowledgementSet,
                        currentUnixSeconds: epochStart + 91
                    )
            },
            semanticEventVector(
                name: "pre-manifest role commitment",
                event: commitmentEvent
            ) {
                _ = try Alpha.PreManifestNostrCodec.decodeRoleCommitment(
                    $0,
                    controlRoster: formation.controlRoster,
                    currentUnixSeconds: epochStart + 121
                )
            },
            semanticEventVector(
                name: "pre-manifest role reveal",
                event: revealEvent
            ) {
                _ = try Alpha.PreManifestNostrCodec.decodeRoleReveal(
                    $0,
                    controlRoster: formation.controlRoster,
                    currentUnixSeconds: epochStart + 151
                )
            },
            semanticEventVector(
                name: "pre-manifest manifest proposal",
                event: proposalEvent
            ) {
                _ = try Alpha.PreManifestNostrCodec.decodeManifestProposal(
                    $0,
                    proposal: proposal,
                    currentUnixSeconds: epochStart + 181
                )
            },
            semanticEventVector(
                name: "pre-manifest manifest signature",
                event: signatureEvent
            ) {
                _ = try Alpha.PreManifestNostrCodec.decodeManifestSignature(
                    $0,
                    proposal: proposal,
                    currentUnixSeconds: epochStart + 182
                )
            },
            semanticEventVector(
                name: "pre-manifest contributor nonce allocation",
                event: nonceEvent
            ) {
                _ = try Alpha.PreManifestNostrCodec
                    .decodeContributorNonceAllocation(
                        $0,
                        controlRoster: formation.controlRoster,
                        roleElection: formation.roleElection,
                        currentUnixSeconds: epochStart + 181
                    )
            },
            semanticEventVector(
                name: "pre-manifest abort",
                event: abortEvent
            ) {
                _ = try Alpha.PreManifestNostrCodec.decodeAbort(
                    $0,
                    authority: abortAuthority,
                    currentUnixSeconds: epochStart + 181
                )
            },
        ]

        try MosaicDeterministicParserMutationCampaign.validate(
            vectors,
            seed: 0x9B05_688C_2B3E_6C1F,
            seededMutationCount: 64
        )
    }

    @Test(
        "Mutate the typed completion Nostr parser",
        .timeLimit(.minutes(1))
    )
    func mutateTypedCompletionNostrParser() async throws {
        let formation = try MosaicPrivateDeploymentFixtures.makeFormation()
        let manifest = try MosaicPrivateDeploymentFixtures
            .makeManifestValidation(formation: formation)
        let roundManifest = try MosaicPrivateDeploymentFixtures
            .makeRoundManifest(
                formation: formation,
                validation: manifest
            )
        let completed = try await MosaicMainnetAlphaBCHCompletionFixtures
            .prepare(manifest: roundManifest)
        let validation = try Alpha.PrivateDeploymentCompletionValidation(
            manifest: manifest,
            roundManifest: roundManifest,
            completeTransactionValidation: completed.validation
        )
        let completion = Alpha.PrivateDeploymentCompletionDocument(
            validation: validation
        )
        let completionTime = manifest.core.deadlines.bchSigning
        let event = try makeEvent(
            payload: .makeCompletion(
                completion,
                validation: validation
            ),
            candidate: formation.controlCandidate(
                for: roundManifest.core.roster.conductor
            ),
            createdAt: completionTime,
            auxiliaryByte: 0xC1
        )
        let vector = try semanticEventVector(
            name: "pre-manifest completion",
            event: event
        ) {
            _ = try Alpha.PreManifestNostrCodec.decodeCompletion(
                $0,
                validation: validation,
                currentUnixSeconds: completionTime
            )
        }

        try MosaicDeterministicParserMutationCampaign.validate(
            [vector],
            seed: 0x1F83_D9AB_FB41_BD6C,
            seededMutationCount: 64
        )
    }

    private func semanticEventVector(
        name: String,
        event: Nostr.Event,
        validate: @escaping (Nostr.Event) throws -> Void
    ) throws -> MosaicDeterministicParserMutationVector {
        let codingLimits = try limits
        let canonical = try Nostr.EventCodec.encode(
            event,
            limits: codingLimits
        )
        return .init(name: name, seedBytes: Array(canonical)) { bytes in
            let decoded = try Nostr.EventCodec.decode(
                Data(bytes),
                limits: codingLimits
            )
            try validate(decoded)
            return try Nostr.EventCodec.encode(
                decoded,
                limits: codingLimits
            ) == Data(bytes)
        }
    }
}

// MosaicMainnetAlphaPrivateNostrMappingValidator~TerminalAuthority.swift

import Testing
@testable import OpalFusion

extension MosaicMainnetAlphaPrivateNostrMappingValidator {
    @Test("Require signed-manifest and previous-output proofs for completion")
    func requireSignedManifestAndPreviousOutputProofsForCompletion() async throws {
        let formation = try MosaicPrivateDeploymentFixtures.makeFormation()
        let manifest = try MosaicPrivateDeploymentFixtures
            .makeManifestValidation(formation: formation)
        #expect(
            throws: Alpha.ContractError.invalidManifestSignatureCount(
                expected: manifest.core.roster.candidateCount,
                actual: 0
            )
        ) {
            _ = try Alpha.RoundManifest(core: manifest.core, signatures: [])
        }

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
        let document = Alpha.PrivateDeploymentCompletionDocument(
            validation: validation
        )

        let structurallyValidUnvalidatedPayload = try Alpha
            .CompleteTransactionPayload(
                roundIdentifier: completed.payload.roundIdentifier,
                transcriptRoot: [UInt8](repeating: 0xFF, count: 32),
                completeTransaction: completed.payload.completeTransaction
            )
        var unvalidatedCompletionBytes = document.canonicalBytes
        unvalidatedCompletionBytes.replaceSubrange(
            (unvalidatedCompletionBytes.count - 32)...,
            with: structurallyValidUnvalidatedPayload.digest
        )
        #expect(
            throws: Alpha.PrivateDeploymentCompletionDocument.ValidationError
                .completeTransactionDigestMismatch
        ) {
            _ = try Alpha.PrivateDeploymentCompletionDocument.decode(
                from: unvalidatedCompletionBytes,
                validation: validation
            )
        }
    }

    @Test("Derive phase-specific abort authority and reject context drift")
    func derivePhaseSpecificAbortAuthorityAndRejectContextDrift() throws {
        let formation = try MosaicPrivateDeploymentFixtures.makeFormation()
        let participant = formation.roleElection.roster.controlIdentities[0]
        let authority = try Alpha.PrivateDeploymentAbortAuthority
            .makeRoleSelectionAuthority(
                participant: participant,
                controlRoster: formation.controlRoster
            )
        let document = try Alpha.PrivateDeploymentAbortDocument(
            discoveryEpochStartUnixSeconds:
                formation.discovery.epochStart,
            phase: .roleSelection,
            context: authority.context,
            reason: .timeout
        )
        #expect(authority.signerRole == .control)
        #expect(
            authority.expiryUnixSeconds
                == formation.discovery.epochStart + 300
        )

        let selectedParticipant = formation.selection.selectedBeacons[0]
            .core.discoveryIdentity
        let wrongAuthority = try Alpha.PrivateDeploymentAbortAuthority
            .makeSelectedDiscoveryAuthority(
                phase: .controlRosterAgreement,
                participant: selectedParticipant,
                candidateSelection: formation.selection
            )
        #expect(
            throws: Alpha.PreManifestNostrPayloadDocument.ValidationError
                .authorityMismatch
        ) {
            _ = try Alpha.PreManifestNostrPayloadDocument.makeAbort(
                document,
                authority: wrongAuthority
            )
        }
        #expect(
            throws: Alpha.PrivateDeploymentAbortDocument.ValidationError
                .phaseMismatch
        ) {
            _ = try Alpha.PrivateDeploymentAbortDocument.decode(
                from: document.canonicalBytes,
                expectedPhase: .controlRosterAgreement,
                expectedContext: wrongAuthority.context
            )
        }

        let manifest = try MosaicPrivateDeploymentFixtures
            .makeManifestValidation(formation: formation)
        let roundManifest = try MosaicPrivateDeploymentFixtures
            .makeRoundManifest(
                formation: formation,
                validation: manifest
            )
        let conductorAuthority = try Alpha.PrivateDeploymentAbortAuthority
            .makePostManifestAuthority(
                phase: .bchSigning,
                participant: manifest.core.roster.conductor,
                manifest: manifest,
                roundManifest: roundManifest
            )
        let proposal = try Alpha.PrivateDeploymentManifestProposalValidation(
            manifest: manifest
        )
        let contributorAuthority = try Alpha.PrivateDeploymentAbortAuthority
            .makeManifestAgreementAuthority(
                participant: manifest.core.roster.contributors[0],
                proposal: proposal
            )
        #expect(conductorAuthority.signerRole == .conductor)
        #expect(
            conductorAuthority.expiryUnixSeconds
                == manifest.core.deadlines.bchSigning
        )
        #expect(contributorAuthority.signerRole == .control)
        #expect(
            contributorAuthority.expiryUnixSeconds
                == formation.discovery.epochStart + 300
        )

        let outsider = try MosaicPrivateDeploymentFixtures
            .CandidateKeyMaterial(scalar: 40).controlIdentity
        #expect(
            throws: Alpha.PrivateDeploymentAbortAuthority.ValidationError
                .unrecognizedParticipant
        ) {
            _ = try Alpha.PrivateDeploymentAbortAuthority
                .makeManifestAgreementAuthority(
                    participant: outsider,
                    proposal: proposal
                )
        }
    }
}

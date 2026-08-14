// MosaicMainnetAlphaPrivateNostrMappingValidator~Manifest.swift

import Testing
@testable import OpalFusion

extension MosaicMainnetAlphaPrivateNostrMappingValidator {
    @Test("Round trip manifest proposal and separated signature events")
    func roundTripManifestProposalAndSeparatedSignatureEvents() throws {
        let formation = try MosaicPrivateDeploymentFixtures.makeFormation()
        let proposal = try MosaicPrivateDeploymentFixtures
            .makeManifestProposalValidation(formation: formation)
        let epochStart = formation.discovery.epochStart
        let core = proposal.manifest.core
        let conductor = formation.controlCandidate(
            for: core.roster.conductor
        )
        let proposalPayload = try Alpha.PreManifestNostrPayloadDocument
            .makeManifestProposal(proposal)
        let proposalEvent = try makeEvent(
            payload: proposalPayload,
            candidate: conductor,
            createdAt: epochStart + 181,
            auxiliaryByte: 0xF3
        )
        #expect(
            try Alpha.PreManifestNostrCodec.decodeManifestProposal(
                proposalEvent,
                proposal: proposal,
                currentUnixSeconds: epochStart + 181
            ) == core
        )

        let binding = proposal.signatureBinding
        let signer = core.roster.controlIdentities[0]
        let signerCandidate = formation.controlCandidate(for: signer)
        let signature = Attempt.ManifestSignature(
            signer: signer,
            rawRepresentation: try MosaicPrivateDeploymentFixtures.sign(
                digestBytes: core.roundIdentifier,
                using: signerCandidate.signingKey,
                auxiliaryByte: 0xF4
            )
        )
        let signaturePayload = try Alpha.PreManifestNostrPayloadDocument
            .makeManifestSignature(
                signature,
                proposal: proposal
            )
        #expect(
            signaturePayload.signerRole
                == (signer == core.roster.conductor
                    ? .conductor
                    : .control)
        )
        let signatureEvent = try makeEvent(
            payload: signaturePayload,
            candidate: signerCandidate,
            createdAt: epochStart + 182,
            auxiliaryByte: 0xF4
        )
        let validation = try Alpha.PreManifestNostrCodec
            .decodeManifestSignature(
                signatureEvent,
                proposal: proposal,
                currentUnixSeconds: epochStart + 182
            )
        #expect(validation.signature == signature)
        #expect(validation.validation.signer == signer)
        #expect(validation.validation.binding == binding)

        let outsiderCandidate = try MosaicPrivateDeploymentFixtures
            .CandidateKeyMaterial(scalar: 40)
        let outsider = outsiderCandidate.controlIdentity
        let outsiderSignature = Attempt.ManifestSignature(
            signer: outsider,
            rawRepresentation: try MosaicPrivateDeploymentFixtures.sign(
                digestBytes: core.roundIdentifier,
                using: outsiderCandidate.signingKey,
                auxiliaryByte: 0xF5
            )
        )
        #expect(
            throws: Alpha.PreManifestNostrPayloadDocument.ValidationError
                .signerNotInRoster
        ) {
            _ = try Alpha.PreManifestNostrPayloadDocument
                .makeManifestSignature(
                    outsiderSignature,
                    proposal: proposal
                )
        }
    }

    @Test("Assemble a complete manifest solely from decoded signature events")
    func assembleCompleteManifestSolelyFromDecodedSignatureEvents() throws {
        let formation = try MosaicPrivateDeploymentFixtures.makeFormation()
        let proposal = try MosaicPrivateDeploymentFixtures
            .makeManifestProposalValidation(formation: formation)
        let epochStart = formation.discovery.epochStart
        let decodedSignatures = try proposal.manifest.core.roster
            .controlIdentities.enumerated().map { index, signer in
                let signerCandidate = formation.controlCandidate(for: signer)
                let signature = Attempt.ManifestSignature(
                    signer: signer,
                    rawRepresentation: try MosaicPrivateDeploymentFixtures.sign(
                        digestBytes: proposal.manifest.core.roundIdentifier,
                        using: signerCandidate.signingKey,
                        auxiliaryByte: UInt8(0x60 + index)
                    )
                )
                let payload = try Alpha.PreManifestNostrPayloadDocument
                    .makeManifestSignature(signature, proposal: proposal)
                let event = try makeEvent(
                    payload: payload,
                    candidate: signerCandidate,
                    createdAt: epochStart + 183,
                    auxiliaryByte: UInt8(0x70 + index)
                )
                return try Alpha.PreManifestNostrCodec.decodeManifestSignature(
                    event,
                    proposal: proposal,
                    currentUnixSeconds: epochStart + 183
                )
            }

        let completeManifest = try Alpha.RoundManifest(
            core: proposal.manifest.core,
            signatures: decodedSignatures.map(\.signature)
        )
        #expect(completeManifest.signatures.count == decodedSignatures.count)
        #expect(
            decodedSignatures.allSatisfy {
                completeManifest.signatures.contains($0.signature)
            }
        )
        #expect(
            decodedSignatures.allSatisfy {
                $0.validation.binding == proposal.signatureBinding
            }
        )

        let admittedAuthority = try Alpha.PrivateDeploymentAbortAuthority
            .makePostManifestAuthority(
                phase: .walletReservation,
                participant: completeManifest.core.roster.conductor,
                manifest: proposal.manifest,
                roundManifest: completeManifest
            )
        #expect(admittedAuthority.signerRole == .conductor)
        #expect(
            admittedAuthority.context
                == Alpha.PrivateDeploymentAbortContext.makeManifestContext(
                    completeManifest.binding
                )
        )
    }

    @Test("Reject re-signed manifest signatures with false outer authority")
    func rejectResignedManifestSignaturesWithFalseOuterAuthority() throws {
        let formation = try MosaicPrivateDeploymentFixtures.makeFormation()
        let proposal = try MosaicPrivateDeploymentFixtures
            .makeManifestProposalValidation(formation: formation)
        let epochStart = formation.discovery.epochStart
        let conductor = formation.controlCandidate(
            for: proposal.manifest.core.roster.conductor
        )
        let contributor = formation.controlCandidate(
            for: proposal.manifest.core.roster.contributors[0]
        )
        let conductorSignature = Attempt.ManifestSignature(
            signer: conductor.controlIdentity,
            rawRepresentation: try MosaicPrivateDeploymentFixtures.sign(
                digestBytes: proposal.manifest.core.roundIdentifier,
                using: conductor.signingKey,
                auxiliaryByte: 0x81
            )
        )
        let conductorBody = try Alpha.PreManifestDocumentCodec
            .encodeManifestSignature(conductorSignature)
        let falseRolePayload = try Alpha.PreManifestNostrPayloadDocument(
            discoveryEpochStartUnixSeconds: epochStart,
            payloadKind: .manifestSignature,
            signerRole: .control,
            signerIdentity: conductor.identity,
            expiryUnixSeconds: epochStart + 240,
            body: conductorBody
        )
        let falseRoleEvent = try makeEvent(
            payload: falseRolePayload,
            candidate: conductor,
            createdAt: epochStart + 183,
            auxiliaryByte: 0x82
        )
        #expect(
            throws: Alpha.PreManifestNostrCodec.ValidationError
                .signerRoleMismatch
        ) {
            _ = try Alpha.PreManifestNostrCodec.decodeManifestSignature(
                falseRoleEvent,
                proposal: proposal,
                currentUnixSeconds: epochStart + 183
            )
        }

        let contributorSignature = Attempt.ManifestSignature(
            signer: contributor.controlIdentity,
            rawRepresentation: try MosaicPrivateDeploymentFixtures.sign(
                digestBytes: proposal.manifest.core.roundIdentifier,
                using: contributor.signingKey,
                auxiliaryByte: 0x83
            )
        )
        let foreignBody = try Alpha.PreManifestDocumentCodec
            .encodeManifestSignature(contributorSignature)
        let foreignBodyPayload = try Alpha.PreManifestNostrPayloadDocument(
            discoveryEpochStartUnixSeconds: epochStart,
            payloadKind: .manifestSignature,
            signerRole: .conductor,
            signerIdentity: conductor.identity,
            expiryUnixSeconds: epochStart + 240,
            body: foreignBody
        )
        let foreignBodyEvent = try makeEvent(
            payload: foreignBodyPayload,
            candidate: conductor,
            createdAt: epochStart + 183,
            auxiliaryByte: 0x84
        )
        #expect(
            throws: Alpha.PreManifestNostrCodec.ValidationError
                .bodySignerIdentityMismatch
        ) {
            _ = try Alpha.PreManifestNostrCodec.decodeManifestSignature(
                foreignBodyEvent,
                proposal: proposal,
                currentUnixSeconds: epochStart + 183
            )
        }
    }
}

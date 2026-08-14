// MosaicMainnetAlphaPrivateNostrEnvelopeValidator~Formation.swift

import Testing
@testable import OpalFusion

extension MosaicMainnetAlphaPrivateNostrEnvelopeValidator {
    @Test("Derive acknowledgement and admission receive authority from formation proofs")
    func deriveAcknowledgementAndAdmissionReceiveAuthorityFromFormationProofs() throws {
        let formation = try MosaicPrivateDeploymentFixtures.makeFormation()
        let epochStart = formation.discovery.epochStart
        let acknowledgement = formation.acknowledgementSet
            .acknowledgements[0]
        let acknowledgementSigner = formation.discovery.candidate(
            for: acknowledgement.signerDiscoveryIdentity
        )
        let acknowledgementPayload = try Alpha
            .PreManifestNostrPayloadDocument.makeCandidateSetAcknowledgement(
                acknowledgement
            )
        let acknowledgementEvent = try Alpha.PreManifestNostrCodec.makeEvent(
            for: acknowledgementPayload,
            createdAtUnixSeconds: epochStart + 61,
            using: acknowledgementSigner.signingKey,
            auxiliaryRandomness: auxiliaryRandomness(0xE7),
            limits: limits
        )
        #expect(
            try Alpha.PreManifestNostrCodec
                .decodeCandidateSetAcknowledgement(
                    acknowledgementEvent,
                    candidateSelection: formation.selection,
                    currentUnixSeconds: epochStart + 61
                ) == acknowledgement
        )

        let admission = formation.controlRoster.admissions[0]
        let admissionSigner = formation.discovery.candidate(
            for: admission.discoveryIdentity
        )
        let admissionPayload = try Alpha.PreManifestNostrPayloadDocument
            .makeCandidateAdmission(admission)
        let admissionEvent = try Alpha.PreManifestNostrCodec.makeEvent(
            for: admissionPayload,
            createdAtUnixSeconds: epochStart + 91,
            using: admissionSigner.signingKey,
            auxiliaryRandomness: auxiliaryRandomness(0xE8),
            limits: limits
        )
        #expect(
            try Alpha.PreManifestNostrCodec.decodeCandidateAdmission(
                admissionEvent,
                candidateSelection: formation.selection,
                acknowledgementSet: formation.acknowledgementSet,
                currentUnixSeconds: epochStart + 91
            ) == admission
        )

        let selectedIdentities = Set(
            formation.selection.selectedDiscoveryIdentities
        )
        let unselected = try #require(
            formation.discovery.candidates.first {
                !selectedIdentities.contains(
                    [UInt8]($0.identity.rawRepresentation)
                )
            }
        )
        let unselectedAcknowledgement = try MosaicPrivateDeploymentFixtures
            .makeAcknowledgement(
                selection: formation.selection,
                candidate: unselected
            )
        let unselectedPayload = try Alpha.PreManifestNostrPayloadDocument
            .makeCandidateSetAcknowledgement(unselectedAcknowledgement)
        let unselectedEvent = try Alpha.PreManifestNostrCodec.makeEvent(
            for: unselectedPayload,
            createdAtUnixSeconds: epochStart + 61,
            using: unselected.signingKey,
            auxiliaryRandomness: auxiliaryRandomness(0xE9),
            limits: limits
        )
        #expect(
            throws: Alpha.PreManifestNostrCodec.ValidationError
                .unrecognizedSigner
        ) {
            _ = try Alpha.PreManifestNostrCodec
                .decodeCandidateSetAcknowledgement(
                    unselectedEvent,
                    candidateSelection: formation.selection,
                    currentUnixSeconds: epochStart + 61
                )
        }

        let alternateSelection = try Alpha.CandidateSelectionValidation(
            beacons: Array(formation.selection.selectedBeacons.prefix(8)),
            discoveryEpochStartUnixSeconds: epochStart,
            opaquePool: formation.discovery.pool,
            relaySet: formation.discovery.relaySet
        )
        let alternateAcknowledgements = try alternateSelection.selectedBeacons
            .map { beacon in
                try MosaicPrivateDeploymentFixtures.makeAcknowledgement(
                    selection: alternateSelection,
                    candidate: formation.discovery.candidate(
                        for: beacon.core.discoveryIdentity
                    )
                )
            }
        let alternateAcknowledgementSet = try Alpha
            .CandidateSetAcknowledgementSetDocument(
                acknowledgements: alternateAcknowledgements,
                candidateSelection: alternateSelection
            )
        #expect(
            throws: Alpha.PreManifestNostrCodec.ValidationError
                .invalidFormationProof
        ) {
            _ = try Alpha.PreManifestNostrCodec.decodeCandidateAdmission(
                admissionEvent,
                candidateSelection: formation.selection,
                acknowledgementSet: alternateAcknowledgementSet,
                currentUnixSeconds: epochStart + 91
            )
        }
    }
}

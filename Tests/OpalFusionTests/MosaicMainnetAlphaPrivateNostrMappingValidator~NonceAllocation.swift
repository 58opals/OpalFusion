// MosaicMainnetAlphaPrivateNostrMappingValidator~NonceAllocation.swift

import Testing
@testable import OpalFusion

extension MosaicMainnetAlphaPrivateNostrMappingValidator {
    @Test("Publish the full nonce allocation by the elected conductor")
    func publishFullNonceAllocationByElectedConductor() throws {
        let formation = try MosaicPrivateDeploymentFixtures.makeFormation()
        let epochStart = formation.discovery.epochStart
        let conductor = formation.controlCandidate(
            for: formation.roleElection.roster.conductor
        )
        let payload = try Alpha.PreManifestNostrPayloadDocument
            .makeContributorNonceAllocation(
                formation.nonceAllocation,
                controlRoster: formation.controlRoster,
                roleElection: formation.roleElection
            )
        let event = try makeEvent(
            payload: payload,
            candidate: conductor,
            createdAt: epochStart + 181,
            auxiliaryByte: 0xF7
        )
        #expect(event.template.kind == 26_546)
        #expect(
            try Alpha.PreManifestNostrCodec
                .decodeContributorNonceAllocation(
                    event,
                    controlRoster: formation.controlRoster,
                    roleElection: formation.roleElection,
                    currentUnixSeconds: epochStart + 181
                ) == formation.nonceAllocation
        )

        let nonConductor = formation.controlCandidate(
            for: formation.roleElection.roster.contributors[0]
        )
        let falseAuthorityPayload = try Alpha
            .PreManifestNostrPayloadDocument(
                discoveryEpochStartUnixSeconds: epochStart,
                payloadKind: .contributorNonceAllocation,
                signerRole: .conductor,
                signerIdentity: nonConductor.identity,
                expiryUnixSeconds: payload.expiryUnixSeconds,
                body: payload.body
            )
        let falseAuthorityEvent = try makeEvent(
            payload: falseAuthorityPayload,
            candidate: nonConductor,
            createdAt: epochStart + 181,
            auxiliaryByte: 0xF8
        )
        #expect(
            throws: Alpha.PreManifestNostrCodec.ValidationError
                .signerIdentityMismatch
        ) {
            _ = try Alpha.PreManifestNostrCodec
                .decodeContributorNonceAllocation(
                    falseAuthorityEvent,
                    controlRoster: formation.controlRoster,
                    roleElection: formation.roleElection,
                    currentUnixSeconds: epochStart + 181
                )
        }
        #expect(
            throws: Alpha.PreManifestNostrCodec.ValidationError
                .eventCreatedBeforePayloadWindow
        ) {
            _ = try makeEvent(
                payload: payload,
                candidate: conductor,
                createdAt: epochStart + 179,
                auxiliaryByte: 0xF9
            )
        }
    }
}

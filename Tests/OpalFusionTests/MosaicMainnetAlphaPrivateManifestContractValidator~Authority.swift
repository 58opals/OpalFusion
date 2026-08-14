// MosaicMainnetAlphaPrivateManifestContractValidator~Authority.swift

import Testing
@testable import OpalFusion

extension MosaicMainnetAlphaPrivateManifestContractValidator {
    @Test("Reject mismatched discovery authority and manifest phase start")
    func rejectMismatchedDiscoveryAuthorityAndManifestPhaseStart() throws {
        let formation = try MosaicPrivateDeploymentFixtures.makeFormation()
        let validation = try MosaicPrivateDeploymentFixtures
            .makeManifestValidation(formation: formation)

        #expect(
            throws: Alpha.PrivateDeploymentManifestValidation.ValidationError
                .discoveryEpochMismatch
        ) {
            _ = try Alpha.PrivateDeploymentManifestValidation(
                discoveryEpochStartUnixSeconds:
                    formation.discovery.epochStart + 300,
                core: validation.core,
                candidateSelection: formation.selection,
                controlRoster: formation.controlRoster,
                roleElection: formation.roleElection,
                opaquePool: formation.discovery.pool,
                relaySet: formation.discovery.relaySet,
                nonceAllocation: formation.nonceAllocation
            )
        }

        let wrongPhaseStart = validation.core.deadlines.phaseStart + 1
        let wrongPhaseCore = try Alpha.RoundManifestCore(
            candidateSetDigest: formation.selection.candidateSetDigest,
            roleElection: formation.roleElection,
            opaquePoolIdentifier: formation.discovery.pool.opaqueIdentifier,
            componentAuthorizationVerificationKey:
                validation.core.componentAuthorizationVerificationKey,
            bchSignatureAuthorizationVerificationKey:
                validation.core.bchSignatureAuthorizationVerificationKey,
            contributorNonceAllocationDigest:
                formation.nonceAllocation.digest,
            relaySetDigest: formation.discovery.relaySet.digest,
            deadlines: try Alpha.PrivateDeploymentPolicy.frozen
                .postManifestDeadlines(
                    forPhaseStartingAt: wrongPhaseStart
                )
        )
        #expect(
            throws: Alpha.PrivateDeploymentManifestValidation.ValidationError
                .phaseStartPolicyMismatch
        ) {
            _ = try Alpha.PrivateDeploymentManifestValidation(
                discoveryEpochStartUnixSeconds:
                    formation.discovery.epochStart,
                core: wrongPhaseCore,
                candidateSelection: formation.selection,
                controlRoster: formation.controlRoster,
                roleElection: formation.roleElection,
                opaquePool: formation.discovery.pool,
                relaySet: formation.discovery.relaySet,
                nonceAllocation: formation.nonceAllocation
            )
        }
    }
}

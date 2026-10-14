// MosaicMainnetAlphaPrivateManifestContractValidator~Authority.swift

import Testing
@testable import MosaicEngine
@testable import OpalFusionCore
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
    @Test("Manifest timing must match the selected pool version on creation and replay")
    func rejectCrossProfileSchedules() throws {
        let formation = try MosaicPrivateDeploymentFixtures.makeFormation()
        let frozen = try MosaicPrivateDeploymentFixtures.makeManifestValidation(formation: formation)
        let candidatePool = try Alpha.OpaquePoolDocument(
            appGeneratedOpaqueIdentifier: formation.discovery.pool.opaqueIdentifier,
            policy: .bootstrap180Candidate)
        let candidateCore = try Alpha.RoundManifestCore(
            candidateSetDigest: frozen.core.candidateSetDigest,
            roleElection: formation.roleElection,
            opaquePoolIdentifier: frozen.core.opaquePoolIdentifier,
            componentAuthorizationVerificationKey: frozen.core.componentAuthorizationVerificationKey,
            bchSignatureAuthorizationVerificationKey: frozen.core.bchSignatureAuthorizationVerificationKey,
            contributorNonceAllocationDigest: frozen.core.contributorNonceAllocationDigest,
            relaySetDigest: frozen.core.relaySetDigest,
            deadlines: Alpha.PrivateDeploymentPolicy.bootstrap180Candidate.postManifestDeadlines(
                forPhaseStartingAt: frozen.core.deadlines.phaseStart))
        func validate(_ core: Alpha.RoundManifestCore, _ pool: Alpha.OpaquePoolDocument) throws
            -> Alpha.PrivateDeploymentManifestValidation {
            try .init(discoveryEpochStartUnixSeconds: formation.discovery.epochStart,
                      core: core, candidateSelection: formation.selection,
                      controlRoster: formation.controlRoster, roleElection: formation.roleElection,
                      opaquePool: pool, relaySet: formation.discovery.relaySet,
                      nonceAllocation: formation.nonceAllocation)
        }
        _ = try validate(candidateCore, candidatePool)
        #expect(throws: Alpha.PrivateDeploymentManifestValidation.ValidationError.deadlinePolicyMismatch) {
            _ = try validate(frozen.core, candidatePool)
        }
        #expect(throws: Alpha.PrivateDeploymentManifestValidation.ValidationError.deadlinePolicyMismatch) {
            _ = try validate(candidateCore, formation.discovery.pool)
        }
    }

}

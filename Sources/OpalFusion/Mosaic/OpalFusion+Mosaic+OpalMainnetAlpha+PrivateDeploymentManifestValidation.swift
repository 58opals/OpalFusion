// OpalFusion+Mosaic+OpalMainnetAlpha+PrivateDeploymentManifestValidation.swift

import Foundation

extension OpalFusion.Mosaic.OpalMainnetAlpha {
    /// Proof that deployment-owned pool, relay, nonce, and deadline documents match one manifest.
    struct PrivateDeploymentManifestValidation: Sendable, Equatable {
        enum ValidationError: Error, Sendable, Equatable {
            case discoveryEpochMismatch
            case candidateSetDigestMismatch
            case controlRosterCandidateSetMismatch
            case controlRosterDigestMismatch
            case roleElectionControlRosterMismatch
            case roleSeedMismatch
            case rosterMismatch
            case opaquePoolMismatch
            case relaySetDigestMismatch
            case nonceAllocationDigestMismatch
            case nonceAllocationControlRosterMismatch
            case nonceAllocationContributorMismatch
            case invalidDeadlineOverflow
            case phaseStartPolicyMismatch
            case deadlinePolicyMismatch
        }

        let discoveryEpochStartUnixSeconds: UInt64
        let core: RoundManifestCore
        let candidateSelection: CandidateSelectionValidation
        let controlRoster: ControlRosterValidation
        let roleElection: OpalFusion.Mosaic.Attempt.RoleElectionResult
        let opaquePool: OpaquePoolDocument
        let relaySet: RelaySetDocument
        let nonceAllocation: ContributorNonceAllocationDocument
        let reservationLeaseExpirationUnixSeconds: UInt64

        init(
            discoveryEpochStartUnixSeconds: UInt64,
            core: RoundManifestCore,
            candidateSelection: CandidateSelectionValidation,
            controlRoster: ControlRosterValidation,
            roleElection: OpalFusion.Mosaic.Attempt.RoleElectionResult,
            opaquePool: OpaquePoolDocument,
            relaySet: RelaySetDocument,
            nonceAllocation: ContributorNonceAllocationDocument,
            policy: PrivateDeploymentPolicy = .frozen
        ) throws(ValidationError) {
            guard candidateSelection.discoveryEpochStartUnixSeconds
                    == discoveryEpochStartUnixSeconds,
                  controlRoster.discoveryEpochStartUnixSeconds
                    == discoveryEpochStartUnixSeconds else {
                throw .discoveryEpochMismatch
            }
            guard core.candidateSetDigest
                    == candidateSelection.candidateSetDigest else {
                throw .candidateSetDigestMismatch
            }
            guard controlRoster.candidateSetDigest
                    == candidateSelection.candidateSetDigest else {
                throw .controlRosterCandidateSetMismatch
            }
            guard core.controlRosterDigest
                    == controlRoster.controlRosterDigest else {
                throw .controlRosterDigestMismatch
            }
            guard roleElection.controlRosterDigest
                    == controlRoster.controlRosterDigest else {
                throw .roleElectionControlRosterMismatch
            }
            guard core.roleSeed == roleElection.roleSeed else {
                throw .roleSeedMismatch
            }
            guard core.roster == roleElection.roster else {
                throw .rosterMismatch
            }
            guard candidateSelection.opaquePoolIdentifier
                    == opaquePool.opaqueIdentifier else {
                throw .opaquePoolMismatch
            }
            guard candidateSelection.relaySetDigest == relaySet.digest else {
                throw .relaySetDigestMismatch
            }
            guard core.opaquePoolIdentifier == opaquePool.opaqueIdentifier else {
                throw .opaquePoolMismatch
            }
            guard core.relaySetDigest == relaySet.digest else {
                throw .relaySetDigestMismatch
            }
            guard core.contributorNonceAllocationDigest
                    == nonceAllocation.digest else {
                throw .nonceAllocationDigestMismatch
            }
            guard core.controlRosterDigest
                    == nonceAllocation.controlRosterDigest else {
                throw .nonceAllocationControlRosterMismatch
            }
            let manifestContributors = Set(
                core.roster.contributors.map { Data($0.validatedBytes) }
            )
            let allocationContributors = Set(
                nonceAllocation.allocations.map {
                    Data($0.contributor.validatedBytes)
                }
            )
            guard manifestContributors == allocationContributors else {
                throw .nonceAllocationContributorMismatch
            }
            let preManifestDeadlines: PreManifestDeadlineSchedule
            let expectedDeadlines: DeadlineSchedule
            do {
                preManifestDeadlines = try policy.preManifestDeadlines(
                    forEpochStartingAt: discoveryEpochStartUnixSeconds
                )
                expectedDeadlines = try policy.postManifestDeadlines(
                    forPhaseStartingAt: core.deadlines.phaseStart
                )
            } catch {
                throw .invalidDeadlineOverflow
            }
            guard core.deadlines.phaseStart
                    == preManifestDeadlines.manifestAgreement else {
                throw .phaseStartPolicyMismatch
            }
            guard core.deadlines == expectedDeadlines else {
                throw .deadlinePolicyMismatch
            }
            self.discoveryEpochStartUnixSeconds =
                discoveryEpochStartUnixSeconds
            self.core = core
            self.candidateSelection = candidateSelection
            self.controlRoster = controlRoster
            self.roleElection = roleElection
            self.opaquePool = opaquePool
            self.relaySet = relaySet
            self.nonceAllocation = nonceAllocation
            reservationLeaseExpirationUnixSeconds = policy
                .reservationLeaseExpirationUnixSeconds(for: expectedDeadlines)
        }
    }
}

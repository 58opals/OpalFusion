// OpalFusion+MosaicPrivateAlphaRuntime+PrivateDeploymentFormationState.swift

#if os(macOS)
extension OpalFusion.MosaicPrivateAlphaRuntime {
    /// Package-decoded state for one canonical pre-manifest recovery prefix.
    enum PrivateDeploymentFormationState {
        typealias Alpha = OpalFusion.Mosaic.OpalMainnetAlpha
        typealias Attempt = OpalFusion.Mosaic.Attempt

        case uninitialized
        case discovery(
            pool: Alpha.OpaquePoolDocument,
            relaySet: Alpha.RelaySetDocument,
            events: [PrivateDeploymentEvent],
            beacons: [Alpha.AvailabilityBeaconDocument]
        )
        case candidateSetAgreement(
            selection: Alpha.CandidateSelectionValidation,
            events: [PrivateDeploymentEvent],
            acknowledgements: [Alpha.CandidateSetAcknowledgementDocument]
        )
        case admission(
            selection: Alpha.CandidateSelectionValidation,
            acknowledgementSet: Alpha.CandidateSetAcknowledgementSetDocument,
            events: [PrivateDeploymentEvent],
            admissions: [Alpha.CandidateAdmissionDocument]
        )
        case controlRosterAgreement(
            candidateSelection: Alpha.CandidateSelectionValidation,
            controlRoster: Alpha.ControlRosterValidation,
            events: [PrivateDeploymentEvent],
            commitments: [Attempt.RoleCommitment]
        )
        case roleElection(
            candidateSelection: Alpha.CandidateSelectionValidation,
            controlRoster: Alpha.ControlRosterValidation,
            commitmentSet: Attempt.RoleCommitmentSet,
            events: [PrivateDeploymentEvent],
            reveals: [Attempt.RoleReveal]
        )
        case nonceAllocationPending(
            candidateSelection: Alpha.CandidateSelectionValidation,
            controlRoster: Alpha.ControlRosterValidation,
            roleElection: Attempt.RoleElectionResult
        )
        case nonceAllocationAccepted(
            candidateSelection: Alpha.CandidateSelectionValidation,
            controlRoster: Alpha.ControlRosterValidation,
            roleElection: Attempt.RoleElectionResult,
            nonceAllocation: Alpha.ContributorNonceAllocationDocument
        )
        case manifestProposalPending(
            pool: Alpha.OpaquePoolDocument,
            relaySet: Alpha.RelaySetDocument,
            candidateSelection: Alpha.CandidateSelectionValidation,
            controlRoster: Alpha.ControlRosterValidation,
            roleElection: Attempt.RoleElectionResult,
            nonceAllocation: Alpha.ContributorNonceAllocationDocument
        )
        case manifestSignatures(
            proposal: Alpha.PrivateDeploymentManifestProposalValidation,
            events: [PrivateDeploymentEvent],
            signatures: [Alpha.PrivateDeploymentManifestSignatureValidation]
        )
    }
}
#endif

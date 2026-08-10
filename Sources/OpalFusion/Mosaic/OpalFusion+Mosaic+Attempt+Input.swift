// OpalFusion+Mosaic+Attempt+Input.swift

extension OpalFusion.Mosaic.Attempt {
    enum Input: Sendable, Equatable {
        enum Kind: String, Sendable, Equatable {
            case discoveryCompleted
            case candidateSetAgreementValidated
            case controlRosterValidated
            case roleCommitmentsReceived
            case roleElectionValidated
            case manifestSignaturesValidated
            case walletReservationsPrepared
            case groupedCommitmentSetReceived
            case anonymousComponentSetReceived
            case transcriptAgreementValidated
            case signedTransactionValidated
            case completeTransactionValidated
            case abort
            case cancel
            case retryRequested
        }

        case discoveryCompleted(candidateCount: Int)
        case candidateSetAgreementValidated
        case controlRosterValidated(ControlRosterBinding)
        case roleCommitmentsReceived([RoleCommitment])
        case roleElectionValidated(RoleSeedValidation)
        case manifestSignaturesValidated([ManifestSignatureValidation])
        case walletReservationsPrepared(contributors: [ControlIdentity])
        case groupedCommitmentSetReceived(
            OpalFusion.Mosaic.OpalV0.CommitmentSet
        )
        case anonymousComponentSetReceived(
            OpalFusion.Mosaic.OpalV0.ComponentSet
        )
        case transcriptAgreementValidated([TranscriptAcknowledgementValidation])
        case signedTransactionValidated(contributorSigners: [ControlIdentity])
        /// An exact complete transaction was independently validated for an anonymous-signature
        /// profile. The profile-specific runtime owns the sealed evidence for this fact.
        case completeTransactionValidated
        case abort(AbortReason)
        case cancel
        case retryRequested

        var kind: Kind {
            switch self {
            case .discoveryCompleted:
                .discoveryCompleted
            case .candidateSetAgreementValidated:
                .candidateSetAgreementValidated
            case .controlRosterValidated:
                .controlRosterValidated
            case .roleCommitmentsReceived:
                .roleCommitmentsReceived
            case .roleElectionValidated:
                .roleElectionValidated
            case .manifestSignaturesValidated:
                .manifestSignaturesValidated
            case .walletReservationsPrepared:
                .walletReservationsPrepared
            case .groupedCommitmentSetReceived:
                .groupedCommitmentSetReceived
            case .anonymousComponentSetReceived:
                .anonymousComponentSetReceived
            case .transcriptAgreementValidated:
                .transcriptAgreementValidated
            case .signedTransactionValidated:
                .signedTransactionValidated
            case .completeTransactionValidated:
                .completeTransactionValidated
            case .abort:
                .abort
            case .cancel:
                .cancel
            case .retryRequested:
                .retryRequested
            }
        }
    }
}

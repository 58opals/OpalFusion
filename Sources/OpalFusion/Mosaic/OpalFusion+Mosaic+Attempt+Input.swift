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
            case groupedCommitmentsValidated
            case anonymousComponentsValidated
            case transcriptAgreementValidated
            case signedTransactionValidated
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
        case groupedCommitmentsValidated(contributors: [ControlIdentity])
        case anonymousComponentsValidated(contributors: [ControlIdentity])
        case transcriptAgreementValidated([TranscriptAcknowledgementValidation])
        case signedTransactionValidated(contributorSigners: [ControlIdentity])
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
            case .groupedCommitmentsValidated:
                .groupedCommitmentsValidated
            case .anonymousComponentsValidated:
                .anonymousComponentsValidated
            case .transcriptAgreementValidated:
                .transcriptAgreementValidated
            case .signedTransactionValidated:
                .signedTransactionValidated
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

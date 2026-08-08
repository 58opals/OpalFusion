// OpalFusion+Mosaic+Attempt+Input.swift

extension OpalFusion.Mosaic.Attempt {
    /// An opaque transcript root that an upstream canonicalization seam has validated.
    struct TranscriptRoot: Sendable, Hashable {
        let validatedBytes: [UInt8]

        init(validatedBytes: [UInt8]) {
            self.validatedBytes = validatedBytes
        }
    }

    /// One already signature-validated pre-sign acknowledgement.
    struct TranscriptAcknowledgement: Sendable, Equatable {
        let contributor: ControlIdentity
        let transcriptRoot: TranscriptRoot

        init(
            contributor: ControlIdentity,
            transcriptRoot: TranscriptRoot
        ) {
            self.contributor = contributor
            self.transcriptRoot = transcriptRoot
        }
    }

    enum Input: Sendable, Equatable {
        enum Kind: String, Sendable, Equatable {
            case discoveryCompleted
            case candidateSetAgreementValidated
            case controlRosterValidated
            case rolesSelected
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
        case controlRosterValidated([ControlIdentity])
        case rolesSelected(Roster)
        case manifestSignaturesValidated([ManifestSignatureValidation])
        case walletReservationsPrepared(contributors: [ControlIdentity])
        case groupedCommitmentsValidated(contributors: [ControlIdentity])
        case anonymousComponentsValidated(contributors: [ControlIdentity])
        case transcriptAgreementValidated([TranscriptAcknowledgement])
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
            case .rolesSelected:
                .rolesSelected
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

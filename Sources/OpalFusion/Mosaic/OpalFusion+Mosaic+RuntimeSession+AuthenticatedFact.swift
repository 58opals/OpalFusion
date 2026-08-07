// OpalFusion+Mosaic+RuntimeSession+AuthenticatedFact.swift

extension OpalFusion.Mosaic.RuntimeSession {
    /// A protocol fact permitted to cross the authenticated network boundary.
    ///
    /// Local cancellation, retry, and wallet-host results are intentionally absent.
    enum AuthenticatedFact: Sendable, Equatable {
        case manifestAgreementValidated(
            [OpalFusion.Mosaic.Attempt.ManifestAcknowledgement]
        )
        case groupedCommitmentsValidated(
            contributors: [OpalFusion.Mosaic.Attempt.ControlIdentity]
        )
        case anonymousComponentsValidated(
            contributors: [OpalFusion.Mosaic.Attempt.ControlIdentity]
        )
        case transcriptAgreementValidated(
            [OpalFusion.Mosaic.Attempt.TranscriptAcknowledgement]
        )
        case abort(OpalFusion.Mosaic.Attempt.AbortReason)

        var attemptInput: OpalFusion.Mosaic.Attempt.Input {
            switch self {
            case let .manifestAgreementValidated(acknowledgements):
                .manifestAgreementValidated(acknowledgements)
            case let .groupedCommitmentsValidated(contributors):
                .groupedCommitmentsValidated(contributors: contributors)
            case let .anonymousComponentsValidated(contributors):
                .anonymousComponentsValidated(contributors: contributors)
            case let .transcriptAgreementValidated(acknowledgements):
                .transcriptAgreementValidated(acknowledgements)
            case let .abort(reason):
                .abort(reason)
            }
        }
    }
}

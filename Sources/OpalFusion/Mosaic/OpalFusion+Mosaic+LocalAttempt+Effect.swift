// OpalFusion+Mosaic+LocalAttempt+Effect.swift

extension OpalFusion.Mosaic.LocalAttempt {
    enum Effect: Sendable, Equatable {
        case walletReservationEligible(
            contributor: OpalFusion.Mosaic.Attempt.ControlIdentity,
            materialIdentifier: MaterialIdentifier,
            manifest: OpalFusion.Mosaic.Attempt.ManifestIdentifier
        )
        case bchSigningEligible(
            contributor: OpalFusion.Mosaic.Attempt.ControlIdentity,
            materialIdentifier: MaterialIdentifier,
            transcriptRoot: OpalFusion.Mosaic.Attempt.TranscriptRoot
        )
        case walletReservationReleaseRequired(
            contributor: OpalFusion.Mosaic.Attempt.ControlIdentity,
            materialIdentifier: MaterialIdentifier
        )
        case walletReservationCommitRequired(
            contributor: OpalFusion.Mosaic.Attempt.ControlIdentity,
            materialIdentifier: MaterialIdentifier
        )
        case attemptTerminated(OpalFusion.Mosaic.Attempt.Outcome)
        case inputRejected(Failure)
    }
}

// OpalFusion+Mosaic+LocalAttempt+Effect.swift

extension OpalFusion.Mosaic.LocalAttempt {
    enum Effect: Sendable, Equatable {
        case walletReservationEligible(
            contributor: OpalFusion.Mosaic.Attempt.ControlIdentity,
            materialIdentifier: MaterialIdentifier,
            manifest: OpalFusion.Mosaic.Attempt.ManifestBinding
        )
        case transcriptInclusionValidationRequired(
            contributor: OpalFusion.Mosaic.Attempt.ControlIdentity,
            materialIdentifier: MaterialIdentifier,
            transcript: OpalFusion.Mosaic.OpalV0.UnsignedTransactionTranscript
        )
        case preSignAcknowledgementRequired(
            contributor: OpalFusion.Mosaic.Attempt.ControlIdentity,
            materialIdentifier: MaterialIdentifier,
            roundIdentifier: [UInt8],
            transcriptRoot: OpalFusion.Mosaic.Attempt.TranscriptRoot
        )
        case bchSigningEligible(
            contributor: OpalFusion.Mosaic.Attempt.ControlIdentity,
            materialIdentifier: MaterialIdentifier,
            transcript: OpalFusion.Mosaic.OpalV0.UnsignedTransactionTranscript
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

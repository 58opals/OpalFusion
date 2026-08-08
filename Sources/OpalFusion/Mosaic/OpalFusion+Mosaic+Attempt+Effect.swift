// OpalFusion+Mosaic+Attempt+Effect.swift

extension OpalFusion.Mosaic.Attempt {
    enum Effect: Sendable, Equatable {
        case walletReservationEligible(
            contributors: [ControlIdentity],
            manifest: ManifestBinding
        )
        /// A future host adapter must idempotently release reservations created after eligibility.
        case walletReservationReleaseRequired(contributors: [ControlIdentity])
        case transcriptInclusionValidationRequired(
            contributors: [ControlIdentity],
            transcript: OpalFusion.Mosaic.OpalV0.UnsignedTransactionTranscript
        )
        case bchSigningEligible(
            contributors: [ControlIdentity],
            transcript: OpalFusion.Mosaic.OpalV0.UnsignedTransactionTranscript
        )
        case attemptTerminated(Outcome)
        case inputRejected(Failure)
    }
}

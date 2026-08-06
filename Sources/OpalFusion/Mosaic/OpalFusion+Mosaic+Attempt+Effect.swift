// OpalFusion+Mosaic+Attempt+Effect.swift

extension OpalFusion.Mosaic.Attempt {
    enum Effect: Sendable, Equatable {
        case walletReservationEligible(
            contributors: [ControlIdentity],
            manifest: ManifestIdentifier
        )
        /// A future host adapter must idempotently release reservations created after eligibility.
        case walletReservationReleaseRequired(contributors: [ControlIdentity])
        case bchSigningEligible(
            contributors: [ControlIdentity],
            transcriptRoot: TranscriptRoot
        )
        case attemptTerminated(Outcome)
        case inputRejected(Failure)
    }
}

// OpalFusion+Host+MosaicTransactionHost.swift

public extension OpalFusion.Host {
    /// Wallet authority used only by a local Mosaic contributor after the protocol gates permit it.
    ///
    /// Implementations must make reservation, release, and commit callbacks idempotent for an exact
    /// reservation reference. A stale generation must never affect a newer lease. Releasing a failed
    /// attempt must make its fresh outputs unavailable to every retry, even if they were not disclosed.
    protocol MosaicTransactionHost: Sendable {
        /// Atomically reserves eligible inputs and fresh outputs after unanimous manifest agreement.
        func reserveMosaicContribution(
            for request: MosaicReservationRequest
        ) async throws -> MosaicReservationLease

        /// Independently validates the complete transcript-bound transaction and signs only local inputs.
        func finalizeMosaicTransaction(
            for request: MosaicTransactionSigningRequest
        ) async throws -> FinalizedTransaction

        /// Releases the exact failed or cancelled lease while permanently retiring its fresh outputs.
        func releaseMosaicReservation(
            _ reservationReference: MosaicReservationReference
        ) async throws

        /// Commits the exact completed lease after the signed transaction passes host policy.
        func commitMosaicReservation(
            _ reservationReference: MosaicReservationReference,
            finalizedTransaction: FinalizedTransaction
        ) async throws
    }
}

// OpalFusion+Host+MosaicCompleteTransactionHost.swift

public extension OpalFusion.Host {
    /// Mosaic wallet authority that can independently verify and commit a fully assembled transaction.
    ///
    /// This refines ``MosaicTransactionHost`` without changing its existing source contract. Live Mosaic
    /// integration must require this refinement before it may treat a reservation as committed.
    protocol MosaicCompleteTransactionHost: MosaicTransactionHost {
        /// Verifies and commits the exact complete transaction associated with the reservation.
        func commitMosaicReservation(
            _ reservationReference: MosaicReservationReference,
            completeTransaction: MosaicCompleteTransaction
        ) async throws
    }
}

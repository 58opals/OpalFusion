// OpalFusion+Runtime+PrimaryRuntimeSession+Input.swift

extension OpalFusion.Runtime.PrimaryRuntimeSession {
    enum Input: Sendable, Equatable {
        case invalidConfiguration(summary: String)
        case connected
        case disconnected
        case stopped
        case primaryTransportFailed(summary: String)
        case diagnosedPrimaryTransportFailed(summary: String)
        case receivedPrimaryBytes([UInt8])
        case covertPrepared
        case covertPreparationFailed(summary: String)
        case receivedCovertResponseBytes([UInt8])
        case covertRequestFailed(summary: String)
        case participantReservationLoaded(OpalFusion.Host.ParticipantReservation)
        case participantReservationRejected(OpalFusion.Host.ParticipantReservationFailure)
        case finalizedTransactionLoaded(OpalFusion.Host.FinalizedTransaction)
        case transactionFinalizationRejected(OpalFusion.Host.TransactionFinalizationFailure)
        case clockAdvanced
    }
}

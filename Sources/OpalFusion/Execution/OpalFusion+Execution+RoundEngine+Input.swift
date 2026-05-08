// OpalFusion+Execution+RoundEngine+Input.swift

extension OpalFusion.Execution.RoundEngine {
    enum Input: Sendable, Equatable {
        case configurationRejected(summary: String)
        case primaryConnected
        case primaryDisconnected
        case stopped
        case primaryTransportFailed(summary: String)
        case covertTransportFailed(summary: String)
        case protocolRejected(summary: String)
        case primaryMessage(OpalFusion.ProtocolModel.ServerMessage)
        case covertResponse(OpalFusion.ProtocolModel.CovertResponse)
        case participantReservationLoaded(OpalFusion.Host.ParticipantReservation)
        case participantReservationRejected
        case finalizedTransactionLoaded(OpalFusion.Host.FinalizedTransaction)
        case transactionFinalizationRejected(OpalFusion.Host.TransactionFinalizationFailure)
        case clockAdvanced
    }
}

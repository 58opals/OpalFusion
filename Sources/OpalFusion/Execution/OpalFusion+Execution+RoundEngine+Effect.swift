// OpalFusion+Execution+RoundEngine+Effect.swift

extension OpalFusion.Execution.RoundEngine {
    enum Effect: Sendable, Equatable {
        case sendPrimary(OpalFusion.ProtocolModel.ClientMessage)
        case prepareCovert(OpalFusion.Runtime.CovertEndpointContext)
        case submitCovert(OpalFusion.ProtocolModel.CovertMessage)
        case requestParticipantReservation(roundIdentifier: OpalFusion.Round.Identifier)
        case requestTransactionFinalization(
            roundIdentifier: OpalFusion.Round.Identifier,
            proposal: OpalFusion.Host.TransactionFinalizationProposal
        )
        case emitHostEvent(
            roundIdentifier: OpalFusion.Round.Identifier?,
            event: OpalFusion.Host.Event
        )
    }
}

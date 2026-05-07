// OpalFusion+Runtime+PrimaryRuntimeSession+Effect.swift

extension OpalFusion.Runtime.PrimaryRuntimeSession {
    enum Effect: Sendable, Equatable {
        case writePrimaryBytes([UInt8])
        case prepareCovertEndpoint(plan: OpalFusion.Runtime.CovertPreparationPlan)
        case performCovertRequest(request: OpalFusion.Runtime.CovertRequest)
        case requestParticipantReservation(context: OpalFusion.Host.ParticipantReservationContext)
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

// OpalFusion+Runtime+CovertRuntimeSession+Effect.swift

extension OpalFusion.Runtime.CovertRuntimeSession {
    enum Effect: Sendable, Equatable {
        case prepareCovertEndpoint(plan: OpalFusion.Runtime.CovertPreparationPlan)
        case performCovertRequest(request: OpalFusion.Runtime.CovertRequest)
        case deliverCovertResponse(OpalFusion.ProtocolModel.CovertResponse)
        case emitProtocolFailure(summary: String)
        case emitTransportFailure(summary: String)
    }
}

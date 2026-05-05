// OpalFusion+Runtime+CovertRuntimeSession+Input.swift

extension OpalFusion.Runtime.CovertRuntimeSession {
    enum Input: Sendable, Equatable {
        case prepare(endpointContext: OpalFusion.Runtime.CovertEndpointContext)
        case enqueue(message: OpalFusion.ProtocolModel.CovertMessage)
        case covertPrepared
        case covertPreparationFailed(summary: String)
        case covertResponseBytesReceived([UInt8])
        case covertRequestFailed(summary: String)
        case clockAdvanced
        case reset
    }
}

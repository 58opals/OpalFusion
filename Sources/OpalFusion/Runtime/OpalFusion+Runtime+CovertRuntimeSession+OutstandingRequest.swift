// OpalFusion+Runtime+CovertRuntimeSession+OutstandingRequest.swift

extension OpalFusion.Runtime.CovertRuntimeSession {
    struct OutstandingRequest: Sendable, Equatable {
        let request: OpalFusion.Runtime.CovertRequest
        let message: OpalFusion.ProtocolModel.CovertMessage
    }
}

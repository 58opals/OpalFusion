// OpalFusion+Runtime+CovertRequest.swift

extension OpalFusion.Runtime {
    struct CovertRequest: Sendable, Equatable {
        let endpoint: OpalFusion.Runtime.CovertEndpointContext
        let payload: [UInt8]
        let startedAt: OpalFusion.Execution.Instant
        let deadline: OpalFusion.Execution.Instant
    }
}

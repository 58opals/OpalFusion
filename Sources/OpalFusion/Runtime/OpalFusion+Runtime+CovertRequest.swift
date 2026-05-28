// OpalFusion+Runtime+CovertRequest.swift

extension OpalFusion.Runtime {
    struct CovertRequest: Sendable, Equatable {
        let endpoint: OpalFusion.Runtime.CovertEndpointContext
        let roundIdentifier: OpalFusion.Round.Identifier?
        let payload: [UInt8]
        let startedAt: OpalFusion.Execution.Instant
        let deadline: OpalFusion.Execution.Instant

        init(
            endpoint: OpalFusion.Runtime.CovertEndpointContext,
            roundIdentifier: OpalFusion.Round.Identifier? = nil,
            payload: [UInt8],
            startedAt: OpalFusion.Execution.Instant,
            deadline: OpalFusion.Execution.Instant
        ) {
            self.endpoint = endpoint
            self.roundIdentifier = roundIdentifier ?? endpoint.roundIdentifier
            self.payload = payload
            self.startedAt = startedAt
            self.deadline = deadline
        }
    }
}

// OpalFusion+Runtime+CovertPreparationPlan.swift

extension OpalFusion.Runtime {
    struct CovertPreparationPlan: Sendable, Equatable {
        let endpoint: OpalFusion.Runtime.CovertEndpointContext
        let startedAt: OpalFusion.Execution.Instant
        let deadline: OpalFusion.Execution.Instant
    }
}

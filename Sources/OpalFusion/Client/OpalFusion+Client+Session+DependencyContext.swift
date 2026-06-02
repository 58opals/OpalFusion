// OpalFusion+Client+Session+DependencyContext.swift

extension OpalFusion.Client.Session {
    struct DependencyContext: Sendable {
        let workflow: OpalFusion.Execution.WorkflowContext?
        let baseline: OpalFusion.Transport.BaselineConfiguration
        let nowProvider: @Sendable () async -> OpalFusion.Execution.Instant
        let clockTickInterval: Duration
        let primaryTransportFactory: @Sendable () async -> (any OpalFusion.Runtime.PrimaryTransporting)?
        let covertTransportFactory: @Sendable () async -> (any OpalFusion.Runtime.CovertTransporting)?
        let snapshotDeliveryHook: @Sendable (
            OpalFusion.Client.Session.Snapshot
        ) async -> Void

        static let defaults = Self(
            workflow: nil,
            baseline: .electronCash443,
            nowProvider: { .current },
            clockTickInterval: .milliseconds(250),
            primaryTransportFactory: { nil },
            covertTransportFactory: { nil },
            snapshotDeliveryHook: { _ in }
        )
    }
}

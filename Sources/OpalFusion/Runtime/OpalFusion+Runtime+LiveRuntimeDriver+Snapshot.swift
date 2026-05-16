// OpalFusion+Runtime+LiveRuntimeDriver+Snapshot.swift

extension OpalFusion.Runtime.LiveRuntimeDriver {
    struct Snapshot: Sendable, Equatable {
        let clientState: OpalFusion.Client.State
        let lastError: OpalFusion.Client.Error?
        let lastErrorSummary: String?
        let diagnostics: OpalFusion.Client.Diagnostics
        let coordinatorStatus: OpalFusion.Client.Session.Snapshot.CoordinatorStatus
        let allowsReconnect: Bool
    }
}

// OpalFusion+Client+Session+Snapshot.swift

public extension OpalFusion.Client.Session {
    /// Display-safe session state for observers and UI surfaces.
    ///
    /// This snapshot intentionally carries coordinator/session state only. Raw transaction bytes, scripts, addresses, private keys, session keys, and wallet snapshots stay behind explicit host APIs.
    struct Snapshot: Sendable, Equatable {
        public let state: OpalFusion.Client.State
        public let lastError: OpalFusion.Client.Error?
        public let lastErrorSummary: String?
        public let coordinatorStatus: CoordinatorStatus

        public init(
            state: OpalFusion.Client.State = .init(),
            lastError: OpalFusion.Client.Error? = nil,
            lastErrorSummary: String? = nil,
            coordinatorStatus: CoordinatorStatus = .init()
        ) {
            self.state = state
            self.lastError = lastError
            self.lastErrorSummary = lastErrorSummary
            self.coordinatorStatus = coordinatorStatus
        }

        init(runtimeSnapshot snapshot: OpalFusion.Runtime.LiveRuntimeDriver.Snapshot) {
            self.init(
                state: snapshot.clientState,
                lastError: snapshot.lastError,
                lastErrorSummary: snapshot.lastErrorSummary,
                coordinatorStatus: snapshot.coordinatorStatus
            )
        }
    }
}

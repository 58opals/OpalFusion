// OpalFusion+Client+StateObserver.swift

public extension OpalFusion.Client {
    /// Receives display-safe session snapshots for UI or host orchestration.
    protocol StateObserver: Sendable {
        func receive(_ snapshot: OpalFusion.Client.Session.Snapshot) async
    }
}

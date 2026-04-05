// OpalFusion+Client+StateObserver.swift

public extension OpalFusion.Client {
    protocol StateObserver: Sendable {
        func receive(_ snapshot: OpalFusion.Client.Session.Snapshot) async
    }
}

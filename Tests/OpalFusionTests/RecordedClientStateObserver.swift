// RecordedClientStateObserver.swift

@testable import OpalFusion
import Foundation

actor RecordedClientStateObserver: OpalFusion.Client.StateObserver {
    private var snapshots: [OpalFusion.Client.Session.Snapshot] = []
    private var timedSnapshots: [TimedClientSessionSnapshot] = []

    func receive(_ snapshot: OpalFusion.Client.Session.Snapshot) async {
        timedSnapshots.append(
            .init(
                snapshot: snapshot,
                recordedAt: Date()
            )
        )
        snapshots.append(snapshot)
    }

    func snapshot() -> [OpalFusion.Client.Session.Snapshot] {
        snapshots
    }

    func timedSnapshot() -> [TimedClientSessionSnapshot] {
        timedSnapshots
    }
}

// RecordedClientStateObserver.swift

@testable import OpalFusion
import Foundation

actor RecordedClientStateObserver: OpalFusion.Client.StateObserver {
    private var snapshots: [OpalFusion.Client.Session.Snapshot] = []
    private var timedSnapshotRecords: [TimedClientSessionSnapshot] = []

    func receive(_ snapshot: OpalFusion.Client.Session.Snapshot) async {
        timedSnapshotRecords.append(
            .init(
                snapshot: snapshot,
                recordedAt: Date()
            )
        )
        snapshots.append(snapshot)
    }

    var recordedSnapshots: [OpalFusion.Client.Session.Snapshot] {
        snapshots
    }

    var timedSnapshots: [TimedClientSessionSnapshot] {
        timedSnapshotRecords
    }
}

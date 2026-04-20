// SessionSnapshotDeliveryGate.swift

@testable import OpalFusion

actor SessionSnapshotDeliveryGate {
    private var blockedSnapshot: OpalFusion.Client.Session.Snapshot?
    private var blockedSnapshotWaiters: [CheckedContinuation<
        OpalFusion.Client.Session.Snapshot,
        Never
    >] = []
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []
    private var isReleased = false

    func waitForBlockedSnapshot() async -> OpalFusion.Client.Session.Snapshot {
        if let blockedSnapshot {
            return blockedSnapshot
        }

        return await withCheckedContinuation { continuation in
            blockedSnapshotWaiters.append(continuation)
        }
    }

    func block(_ snapshot: OpalFusion.Client.Session.Snapshot) async {
        if blockedSnapshot == nil {
            blockedSnapshot = snapshot
            let waiters = blockedSnapshotWaiters
            self.blockedSnapshotWaiters.removeAll()
            for waiter in waiters {
                waiter.resume(returning: snapshot)
            }
        }

        if isReleased {
            return
        }

        await withCheckedContinuation { continuation in
            releaseWaiters.append(continuation)
        }
    }

    func release() {
        isReleased = true
        let waiters = releaseWaiters
        self.releaseWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
    }
}

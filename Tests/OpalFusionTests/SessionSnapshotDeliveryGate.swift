// SessionSnapshotDeliveryGate.swift

@testable import OpalFusion
import Foundation

actor SessionSnapshotDeliveryGate {
    private var blockedSnapshot: OpalFusion.Client.Session.Snapshot?
    private var blockedSnapshotWaiters: [UUID: CheckedContinuation<
        OpalFusion.Client.Session.Snapshot,
        Error
    >] = [:]
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []
    private var isReleased = false

    func waitForBlockedSnapshot() async throws -> OpalFusion.Client.Session.Snapshot {
        if let blockedSnapshot {
            return blockedSnapshot
        }

        let waiterID = UUID()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                blockedSnapshotWaiters[waiterID] = continuation
            }
        } onCancel: {
            Task {
                await self.cancelBlockedSnapshotWaiter(waiterID)
            }
        }
    }

    func block(_ snapshot: OpalFusion.Client.Session.Snapshot) async {
        if blockedSnapshot == nil {
            blockedSnapshot = snapshot
            let waiters = blockedSnapshotWaiters.values
            blockedSnapshotWaiters.removeAll()
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
        releaseWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
    }

    private func cancelBlockedSnapshotWaiter(_ waiterID: UUID) {
        guard let waiter = blockedSnapshotWaiters.removeValue(forKey: waiterID) else {
            return
        }

        waiter.resume(throwing: CancellationError())
    }
}

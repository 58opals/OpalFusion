// OpalFusion+Client+Session+ImplementationGroup2.swift

import OpalDiagnostics

extension OpalFusion.Client.Session {
    func scheduleRetry(
        attempt: Int,
        delay: Duration
    ) async {
        let retryDelayMilliseconds = delay.opalFusionMillisecondsRoundedUp
        OpalDiagnostics.logger(category: .fusionPrimary).record(
            event: .primaryRetryScheduled,
            level: .opalFusionDefault(for: .primaryRetryScheduled),
            fields: [
                .operation("primary_reconnect"),
                .retryAttempt(attempt),
                .retryDelayMilliseconds(retryDelayMilliseconds)
            ]
        )

        let scheduledGeneration = runtimeDriverGeneration
        pendingRetryTask?.cancel()
        pendingRetryTask = Task { [delay, scheduledGeneration] in
            do {
                try await Task.sleep(for: delay)
            } catch {
                return
            }

            await self.runScheduledRetry(generation: scheduledGeneration)
        }
    }

    func runScheduledRetry(
        generation: Int
    ) async {
        guard isActive,
              isCurrentGeneration(generation) else {
            return
        }

        pendingRetryTask = nil
        await startRuntimeDriver()
    }

    func isCurrentRuntimeDriver(
        _ runtimeDriver: OpalFusion.Runtime.LiveRuntimeDriver,
        generation: Int
    ) -> Bool {
        self.runtimeDriver === runtimeDriver && isCurrentGeneration(generation)
    }

    func isCurrentGeneration(_ generation: Int) -> Bool {
        generation == runtimeDriverGeneration
    }

    func stoppedSnapshot() -> OpalFusion.Client.Session.Snapshot {
        .init(
            state: .init(),
            lastError: nil,
            lastErrorSummary: nil,
            coordinatorStatus: lastEmittedSnapshot.coordinatorStatus
        )
    }

    func updateSnapshotIfNeeded(
        _ snapshot: OpalFusion.Client.Session.Snapshot
    ) async {
        if snapshot.state.isConnected,
           snapshot.lastError == nil {
            retryAttempt = 0
        }

        guard snapshot != lastEmittedSnapshot else {
            return
        }

        lastEmittedSnapshot = snapshot
        await stateObserver?.receive(snapshot)
    }
}

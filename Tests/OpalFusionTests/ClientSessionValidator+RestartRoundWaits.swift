// ClientSessionValidator+RestartRoundWaits.swift

@testable import OpalFusion

extension ClientSessionValidator {
    func enqueueAcknowledgement(
        scriptedCovertTransport: ScriptedCovertTransport
    ) async throws {
        await scriptedCovertTransport.enqueueResponse(
            try PrimaryRuntimeTestFixtures.encodeCovertResponsePayload(
                PrimaryRuntimeTestFixtures.acknowledgement
            )
        )
    }

    func waitForCovertPreparationCount(
        _ count: Int,
        recordingCovertTransport: RecordingCovertTransport
    ) async throws {
        try await LiveRuntimeTestHarness.withTimeout(.seconds(1)) {
            while (await recordingCovertTransport.recordedPreparationPlans).count < count {
                try await Task.sleep(for: .milliseconds(10))
            }
        }
    }

    func waitForCovertRequestCount(
        _ count: Int,
        recordingCovertTransport: RecordingCovertTransport
    ) async throws {
        try await LiveRuntimeTestHarness.withTimeout(.seconds(1)) {
            while (await recordingCovertTransport.recordedRequests).count < count {
                try await Task.sleep(for: .milliseconds(10))
            }
        }
    }

    func waitForRestartedConnectedSnapshot(
        session: OpalFusion.Client.Session
    ) async throws {
        try await LiveRuntimeTestHarness.withTimeout(.seconds(1)) {
            while true {
                let snapshot = await session.currentSnapshot
                if snapshot.state.isConnected && snapshot.state.round == nil {
                    return
                }
                try await Task.sleep(for: .milliseconds(10))
            }
        }
    }

    func waitForSuccessfulSnapshot(
        session: OpalFusion.Client.Session
    ) async throws -> OpalFusion.Client.Session.Snapshot {
        try await LiveRuntimeTestHarness.withTimeout(.seconds(1)) {
            while true {
                let snapshot = await session.currentSnapshot
                if snapshot.state.round?.completionStatus == .success {
                    return snapshot
                }
                try await Task.sleep(for: .milliseconds(10))
            }
        }
    }
}

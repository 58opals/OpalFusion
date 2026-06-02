// LiveRuntimeDriverValidator+ValidationGroup12.swift

@testable import OpalFusion
import Foundation
import Network
import Testing

extension LiveRuntimeDriverValidator {
    @Test("Live runtime driver ignores stale covert completions after stop")
    func validateStaleCovertCompletionIsIgnoredAfterStop() async throws {
        let primaryTransport = ScriptedPrimaryTransport()
        let covertTransport = BlockingCovertTransport(blocksPerform: true)
        let eventSink = RecordedHostEventSink()
        let nowProvider = ScriptedInstantClock(unixSeconds: 995)
        let driver = OpalFusion.Runtime.LiveRuntimeDriver(
            configuration: PrimaryRuntimeTestFixtures.configuration,
            genesisHash: PrimaryRuntimeTestFixtures.clientHello.genesisHash,
            joinPools: PrimaryRuntimeTestFixtures.joinPools,
            workflow: PrimaryRuntimeTestFixtures.workflow,
            participantReservationSource: DelayedParticipantReservationSource(
                participantInputs: [PrimaryRuntimeTestFixtures.participantInput]
            ),
            transactionAssembler: DelayedTransactionAssembler(
                finalizedTransaction: PrimaryRuntimeTestFixtures.finalizedTransaction
            ),
            hostEventSink: { roundIdentifier, event in
                await eventSink.record(
                    roundIdentifier: roundIdentifier,
                    event: event
                )
            },
            nowProvider: { await nowProvider.current },
            clockTickInterval: .milliseconds(100),
            primaryTransport: primaryTransport,
            covertTransport: covertTransport
        )

        await driver.start()
        try await LiveRuntimeTestHarness.withTimeout(.seconds(1)) {
            while (await primaryTransport.recordedWrittenPayloads).isEmpty {
                try await Task.sleep(for: .milliseconds(10))
            }
        }

        await nowProvider.update(unixSeconds: 996)
        await primaryTransport.yieldInboundBytes(
            try PrimaryRuntimeTestFixtures.encodeServerFrame(
                .serverHello(PrimaryRuntimeTestFixtures.serverHello)
            )
        )
        try await LiveRuntimeTestHarness.withTimeout(.seconds(1)) {
            while (await primaryTransport.recordedWrittenPayloads).count < 2 {
                try await Task.sleep(for: .milliseconds(10))
            }
        }

        await nowProvider.update(unixSeconds: 1_000)
        await primaryTransport.yieldInboundBytes(
            try PrimaryRuntimeTestFixtures.encodeServerFrame(
                .fusionBegin(PrimaryRuntimeTestFixtures.fusionBegin)
            )
        )
        try await LiveRuntimeTestHarness.withTimeout(.seconds(1)) {
            while (await covertTransport.recordedPreparationPlans).isEmpty {
                try await Task.sleep(for: .milliseconds(10))
            }
        }

        await nowProvider.update(unixSeconds: 1_030)
        await primaryTransport.yieldInboundBytes(
            try PrimaryRuntimeTestFixtures.encodeServerFrame(
                .startRound(PrimaryRuntimeTestFixtures.startRound)
            )
        )
        try await LiveRuntimeTestHarness.withTimeout(.seconds(1)) {
            while (await primaryTransport.recordedWrittenPayloads).count < 3 {
                try await Task.sleep(for: .milliseconds(10))
            }
        }

        await nowProvider.update(unixSeconds: 1_032)
        await primaryTransport.yieldInboundBytes(
            try PrimaryRuntimeTestFixtures.encodeServerFrame(
                .blindSignatureResponses(PrimaryRuntimeTestFixtures.blindSignatureResponses)
            )
        )

        await nowProvider.update(unixSeconds: 1_034)
        await primaryTransport.yieldInboundBytes(
            try PrimaryRuntimeTestFixtures.encodeServerFrame(
                .allCommitments(PrimaryRuntimeTestFixtures.allCommitments)
            )
        )
        await nowProvider.update(unixSeconds: 1_035)
        try await LiveRuntimeTestHarness.withTimeout(.seconds(1)) {
            while (await covertTransport.recordedRequests).count < 1 {
                try await Task.sleep(for: .milliseconds(10))
            }
        }

        let snapshotBeforeStop = await driver.currentSnapshot
        #expect(snapshotBeforeStop.clientState.round?.phase == .awaitingCommitments)
        #expect(snapshotBeforeStop.lastError == nil)

        await driver.stop()

        let stoppedSnapshot = try await LiveRuntimeTestHarness.withTimeout(.seconds(1)) {
            while true {
                let snapshot = await driver.currentSnapshot
                if snapshot.lastError == nil &&
                    snapshot.lastErrorSummary == nil &&
                    snapshot.clientState.isConnected == false {
                    return snapshot
                }
                try await Task.sleep(for: .milliseconds(10))
            }
        }
        #expect(stoppedSnapshot.lastError == nil)
        #expect(stoppedSnapshot.lastErrorSummary == nil)
        #expect(stoppedSnapshot.clientState.isConnected == false)
        #expect(stoppedSnapshot.clientState.round == nil)
        #expect(await covertTransport.recordedResetCount > 0)

        let eventsAfterStop = await eventSink.recordedSnapshots
        #expect(eventsAfterStop.contains { $0.event.summary == "Primary channel disconnected" } == false)

        await covertTransport.releasePerform(
            response: try PrimaryRuntimeTestFixtures.encodeCovertResponsePayload(
                PrimaryRuntimeTestFixtures.acknowledgement
            )
        )
        try await Task.sleep(for: .milliseconds(50))

        let finalSnapshot = await driver.currentSnapshot
        #expect(finalSnapshot == stoppedSnapshot)

        let eventsAfterRelease = await eventSink.recordedSnapshots
        #expect(eventsAfterRelease == eventsAfterStop)
    }
}

// LiveRuntimeDriverValidator+ValidationGroup13.swift

@testable import OpalFusion
import Foundation
import Network
import Testing

extension LiveRuntimeDriverValidator {
    @Test("Live runtime driver ignores stale participant reservations after stop")
    func validateStaleParticipantReservationIsIgnoredAfterStop() async throws {
        let primaryTransport = ScriptedPrimaryTransport()
        let covertTransport = ScriptedCovertTransport()
        let participantReservationSource = BlockingParticipantReservationSource(
            reservation: .init(
                inputs: [PrimaryRuntimeTestFixtures.participantInput],
                outputs: [PrimaryRuntimeTestFixtures.participantOutput]
            )
        )
        let eventSink = RecordedHostEventSink()
        let nowProvider = ScriptedInstantClock(unixSeconds: 995)
        let driver = OpalFusion.Runtime.LiveRuntimeDriver(
            configuration: PrimaryRuntimeTestFixtures.configuration,
            genesisHash: PrimaryRuntimeTestFixtures.clientHello.genesisHash,
            joinPools: PrimaryRuntimeTestFixtures.joinPools,
            workflow: PrimaryRuntimeTestFixtures.workflow,
            participantReservationSource: participantReservationSource,
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
        try await Task.sleep(for: .milliseconds(50))

        #expect((await primaryTransport.recordedWrittenPayloads).count == 2)

        await driver.stop()
        let stoppedSnapshot = await driver.currentSnapshot
        #expect(stoppedSnapshot.lastError == nil)
        #expect(stoppedSnapshot.lastErrorSummary == nil)
        #expect(stoppedSnapshot.clientState.isConnected == false)
        #expect(stoppedSnapshot.clientState.round == nil)

        await participantReservationSource.releaseReservation()
        try await Task.sleep(for: .milliseconds(100))

        let finalSnapshot = await driver.currentSnapshot
        #expect(finalSnapshot == stoppedSnapshot)
        #expect((await primaryTransport.recordedWrittenPayloads).count == 2)

        let events = await eventSink.recordedSnapshots
        #expect(events.contains { $0.event.summary == "Primary channel disconnected" } == false)
        #expect(events.contains { $0.event.summary == "Submitting player commitments and blind requests" } == false)
    }
}

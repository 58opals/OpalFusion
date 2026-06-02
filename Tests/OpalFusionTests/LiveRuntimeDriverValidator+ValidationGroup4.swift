// LiveRuntimeDriverValidator+ValidationGroup4.swift

@testable import OpalFusion
import Foundation
import Network
import Testing

extension LiveRuntimeDriverValidator {
    @Test("Live runtime driver maps primary connect failure to transport unavailable")
    func validatePrimaryConnectFailureProjection() async throws {
        let primaryTransport = ScriptedPrimaryTransport(
            connectError: NSError(domain: "LiveRuntimeDriverValidator", code: 1)
        )
        let eventSink = RecordedHostEventSink()
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
            primaryTransport: primaryTransport,
            covertTransport: ScriptedCovertTransport()
        )

        await driver.start()

        let snapshot = await driver.currentSnapshot
        #expect(snapshot.lastError == .transportUnavailable)
        #expect(snapshot.lastErrorSummary == "Primary connection failed")
        #expect(snapshot.clientState.isConnected == false)

        let events = await eventSink.recordedSnapshots
        guard let event = events.last else {
            Issue.record("Expected a transport failure event")
            return
        }
        #expect(event.roundIdentifier == nil)
        #expect(event.event.kind == .failure)
        #expect(event.event.phase == .connecting)
        #expect(event.event.summary == "Primary connection failed")
    }

    @Test("Live runtime driver keeps a pending primary connect alive past the startup clock tick")
    func validatePendingPrimaryConnectIsNotCancelledByStartupClock() async throws {
        let primaryTransport = ScriptedPrimaryTransport(blocksConnect: true)
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
            clockTickInterval: .milliseconds(250),
            primaryTransport: primaryTransport,
            covertTransport: ScriptedCovertTransport()
        )

        let startTask = Task {
            await driver.start()
        }

        try await Task.sleep(for: .milliseconds(400))

        let pendingSnapshot = await driver.currentSnapshot
        #expect(pendingSnapshot.clientState.isConnected == false)
        #expect(pendingSnapshot.lastError == nil)
        #expect(pendingSnapshot.lastErrorSummary == nil)
        #expect(await primaryTransport.recordedConnectCallCount == 1)
        #expect(await primaryTransport.recordedCloseCallCount == 0)
        #expect(await primaryTransport.hasPendingConnect)

        await primaryTransport.releaseConnect()
        await startTask.value

        let connectedSnapshot = await driver.currentSnapshot
        #expect(connectedSnapshot.clientState.isConnected)
        #expect(connectedSnapshot.lastError == nil)
        #expect(connectedSnapshot.lastErrorSummary == nil)
        #expect((await primaryTransport.recordedWrittenPayloads).isEmpty == false)
        #expect(await primaryTransport.recordedCloseCallCount == 0)
        #expect(await primaryTransport.hasPendingConnect == false)

        await driver.stop()
    }

    @Test("Live runtime driver treats explicit stop as a non-error terminal state")
    func validateExplicitStopIsNonErrorTerminalState() async throws {
        let primaryTransport = ScriptedPrimaryTransport()
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
            primaryTransport: primaryTransport,
            covertTransport: ScriptedCovertTransport()
        )

        await driver.start()
        let runningSnapshot = await driver.currentSnapshot
        #expect(runningSnapshot.clientState.isConnected)
        #expect(runningSnapshot.lastError == nil)
        #expect(runningSnapshot.lastErrorSummary == nil)

        await driver.stop()
        await driver.stop()

        let stoppedSnapshot = await driver.currentSnapshot
        #expect(stoppedSnapshot.clientState.isConnected == false)
        #expect(stoppedSnapshot.clientState.round == nil)
        #expect(stoppedSnapshot.lastError == nil)
        #expect(stoppedSnapshot.lastErrorSummary == nil)
        #expect(await primaryTransport.recordedCloseCallCount == 1)
    }
}

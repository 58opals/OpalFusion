// LiveRuntimeDriverValidator+ValidationGroup5.swift

@testable import OpalFusion
import Foundation
import Network
import Testing

extension LiveRuntimeDriverValidator {
    @Test("Live runtime driver defers startup teardown until a real connect failure arrives")
    func validatePendingPrimaryConnectTearsDownOnlyAfterRealFailure() async throws {
        let connectError = NSError(domain: "LiveRuntimeDriverValidator", code: 3)
        let primaryTransport = ScriptedPrimaryTransport(blocksConnect: true)
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
        #expect(await primaryTransport.recordedCloseCallCount == 0)
        #expect(await primaryTransport.hasPendingConnect)

        await primaryTransport.failConnect(connectError)
        await startTask.value

        let failedSnapshot = await driver.currentSnapshot
        #expect(failedSnapshot.clientState.isConnected == false)
        #expect(failedSnapshot.lastError == .transportUnavailable)
        #expect(failedSnapshot.lastErrorSummary == "Primary connection failed")
        #expect(await primaryTransport.recordedCloseCallCount == 1)
        #expect(await primaryTransport.hasPendingConnect == false)

        let events = await eventSink.recordedSnapshots
        guard let event = events.last else {
            Issue.record("Expected a delayed connect failure event")
            return
        }
        #expect(event.roundIdentifier == nil)
        #expect(event.event.kind == .failure)
        #expect(event.event.phase == .connecting)
        #expect(event.event.summary == "Primary connection failed")
    }

    @Test("Live runtime driver stops a pending primary connect without surfacing cancellation as failure")
    func validatePendingPrimaryConnectStopIsNonErrorTerminalState() async throws {
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
            primaryTransport: primaryTransport,
            covertTransport: ScriptedCovertTransport()
        )

        let startTask = Task {
            await driver.start()
        }

        try await Task.sleep(for: .milliseconds(100))
        #expect(await primaryTransport.hasPendingConnect)

        await driver.stop()
        await startTask.value

        let snapshot = await driver.currentSnapshot
        #expect(snapshot.clientState.isConnected == false)
        #expect(snapshot.lastError == nil)
        #expect(snapshot.lastErrorSummary == nil)
        #expect(await primaryTransport.recordedCloseCallCount == 1)
        #expect(await primaryTransport.hasPendingConnect == false)
    }

    @Test("Live runtime driver preserves startup waiting errors when cancellation follows restart")
    func validateStartupWaitingCancellationPreservesUnderlyingErrorProjection() async throws {
        let underlyingError = NWError.posix(.ECONNRESET)
        let expectedSummary = "Primary connection failed"
        let eventSink = RecordedHostEventSink()
        let factory = ScriptedNetworkPrimaryConnectionFixture(
            startStates: [.waiting(underlyingError)],
            restartStates: [.cancelled]
        )
        let primaryTransport = OpalFusion.Runtime.LivePrimaryTransport(
            host: "127.0.0.1",
            port: PrimaryRuntimeTestFixtures.configuration.coordinatorPort,
            restartDelay: .zero,
            connectionFactory: { host, port, parameters in
                factory.make(
                    host: host,
                    port: port,
                    parameters: parameters
                )
            }
        )
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
        #expect(snapshot.lastErrorSummary == expectedSummary)
        #expect(snapshot.lastErrorSummary?.contains("primaryConnectionCancelled") == false)

        let events = await eventSink.recordedSnapshots
        guard let event = events.last else {
            Issue.record("Expected a transport failure event")
            return
        }
        #expect(event.roundIdentifier == nil)
        #expect(event.event.kind == .failure)
        #expect(event.event.phase == .connecting)
        #expect(event.event.summary == expectedSummary)
    }
}

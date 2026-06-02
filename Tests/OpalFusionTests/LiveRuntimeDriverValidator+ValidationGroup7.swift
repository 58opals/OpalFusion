// LiveRuntimeDriverValidator+ValidationGroup7.swift

@testable import OpalFusion
import Foundation
import Network
import Testing

extension LiveRuntimeDriverValidator {
    @Test("Live runtime driver treats a clean pre-round EOF after ServerHello as a disconnect")
    func validatePreRoundEOFAfterServerHelloSurfacesDisconnect() async throws {
        let coordinator = try await LoopbackPrimaryCoordinator.start()
        let eventSink = RecordedHostEventSink()
        let driver = OpalFusion.Runtime.LiveRuntimeDriver(
            configuration: .init(
                coordinatorHost: "127.0.0.1",
                coordinatorPort: await coordinator.port,
                covertChannel: PrimaryRuntimeTestFixtures.configuration.covertChannel
            ),
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
            covertTransport: ScriptedCovertTransport()
        )

        await driver.start()
        #expect(
            try await coordinator.readNextClientMessage()
                == .clientHello(PrimaryRuntimeTestFixtures.clientHello)
        )

        try await coordinator.send(.serverHello(PrimaryRuntimeTestFixtures.serverHello))
        #expect(
            try await coordinator.readNextClientMessage()
                == .joinPools(PrimaryRuntimeTestFixtures.joinPools)
        )

        await coordinator.closeConnection()

        let snapshot = try await LiveRuntimeTestHarness.withTimeout(.seconds(1)) {
            while true {
                let snapshot = await driver.currentSnapshot
                if snapshot.lastError == .transportUnavailable,
                   snapshot.lastErrorSummary == "Primary channel disconnected",
                   snapshot.clientState.isConnected == false {
                    return snapshot
                }
                try await Task.sleep(for: .milliseconds(10))
            }
        }

        #expect(snapshot.lastError == .transportUnavailable)
        #expect(snapshot.lastErrorSummary == "Primary channel disconnected")
        #expect(snapshot.lastErrorSummary?.contains("primaryConnectionCancelled") == false)
        #expect(
            await coordinator.recordedClientMessages
                == [
                    .clientHello(PrimaryRuntimeTestFixtures.clientHello),
                    .joinPools(PrimaryRuntimeTestFixtures.joinPools)
                ]
        )

        let events = await eventSink.recordedSnapshots
        let lastEvent = try #require(events.last)
        #expect(lastEvent.event.summary == "Primary channel disconnected")

        await coordinator.stop()
    }

    @Test("Live runtime driver preserves a decoded pre-round server rejection across clean EOF")
    func validatePreRoundServerFailurePreservesCoordinatorSummary() async throws {
        let coordinator = try await LoopbackPrimaryCoordinator.start()
        let eventSink = RecordedHostEventSink()
        let rejectionSummary = "Coordinator rejected JoinPools"
        let driver = OpalFusion.Runtime.LiveRuntimeDriver(
            configuration: .init(
                coordinatorHost: "127.0.0.1",
                coordinatorPort: await coordinator.port,
                covertChannel: PrimaryRuntimeTestFixtures.configuration.covertChannel
            ),
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
            covertTransport: ScriptedCovertTransport()
        )

        await driver.start()
        #expect(
            try await coordinator.readNextClientMessage()
                == .clientHello(PrimaryRuntimeTestFixtures.clientHello)
        )

        try await coordinator.send(.serverHello(PrimaryRuntimeTestFixtures.serverHello))
        #expect(
            try await coordinator.readNextClientMessage()
                == .joinPools(PrimaryRuntimeTestFixtures.joinPools)
        )

        try await coordinator.send(.serverFailure(.init(message: rejectionSummary)))
        await coordinator.closeConnection()

        let snapshot = try await LiveRuntimeTestHarness.withTimeout(.seconds(1)) {
            while true {
                let snapshot = await driver.currentSnapshot
                if snapshot.lastError == .coordinatorRejected,
                   snapshot.lastErrorSummary == rejectionSummary,
                   snapshot.clientState.isConnected == false {
                    return snapshot
                }
                try await Task.sleep(for: .milliseconds(10))
            }
        }

        #expect(snapshot.lastError == .coordinatorRejected)
        #expect(snapshot.lastErrorSummary == rejectionSummary)
        #expect(snapshot.lastErrorSummary?.contains("primaryConnectionCancelled") == false)

        let events = await eventSink.recordedSnapshots
        let lastEvent = try #require(events.last)
        #expect(lastEvent.event.summary == rejectionSummary)

        await coordinator.stop()
    }
}

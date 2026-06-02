// LiveRuntimeDriverValidator+ValidationGroup8.swift

@testable import OpalFusion
import Foundation
import Network
import Testing

extension LiveRuntimeDriverValidator {
    @Test("Live runtime driver completes a scripted round over a loopback coordinator")
    func validateHappyPathLoopbackRuntime() async throws {
        let coordinator = try await LoopbackPrimaryCoordinator.start()

        let covertTransport = ScriptedCovertTransport()
        let eventSink = RecordedHostEventSink()
        let participantReservationSource = DelayedParticipantReservationSource(
            participantInputs: [PrimaryRuntimeTestFixtures.participantInput],
            delay: .milliseconds(10)
        )
        let transactionAssembler = DelayedTransactionAssembler(
            finalizedTransaction: PrimaryRuntimeTestFixtures.finalizedTransaction,
            delay: .milliseconds(10)
        )
        let nowProvider = ScriptedInstantClock(unixSeconds: 995)
        let configuration = OpalFusion.Client.Configuration(
            coordinatorHost: "127.0.0.1",
            coordinatorPort: await coordinator.port,
            covertChannel: PrimaryRuntimeTestFixtures.configuration.covertChannel
        )
        let driver = OpalFusion.Runtime.LiveRuntimeDriver(
            configuration: configuration,
            genesisHash: PrimaryRuntimeTestFixtures.clientHello.genesisHash,
            joinPools: PrimaryRuntimeTestFixtures.joinPools,
            workflow: PrimaryRuntimeTestFixtures.workflow,
            participantReservationSource: participantReservationSource,
            transactionAssembler: transactionAssembler,
            hostEventSink: { roundIdentifier, event in
                await eventSink.record(
                    roundIdentifier: roundIdentifier,
                    event: event
                )
            },
            nowProvider: { await nowProvider.current },
            clockTickInterval: .milliseconds(100),
            covertTransport: covertTransport
        )

        await driver.start()
        #expect(
            try await coordinator.readNextClientMessage()
                == .clientHello(PrimaryRuntimeTestFixtures.clientHello)
        )

        await nowProvider.update(unixSeconds: 996)
        try await coordinator.send(.serverHello(PrimaryRuntimeTestFixtures.serverHello))
        #expect(
            try await coordinator.readNextClientMessage()
                == .joinPools(PrimaryRuntimeTestFixtures.joinPools)
        )

        await nowProvider.update(unixSeconds: 1_000)
        try await coordinator.send(.fusionBegin(PrimaryRuntimeTestFixtures.fusionBegin))
        try await LiveRuntimeTestHarness.withTimeout(.seconds(1)) {
            while (await covertTransport.recordedPreparationPlans).isEmpty {
                try await Task.sleep(for: .milliseconds(10))
            }
        }

        await nowProvider.update(unixSeconds: 1_030)
        try await coordinator.send(.startRound(PrimaryRuntimeTestFixtures.startRound))
        #expect(
            try await coordinator.readNextClientMessage()
                == .playerCommit(PrimaryRuntimeTestFixtures.playerCommit)
        )

        await nowProvider.update(unixSeconds: 1_032)
        try await coordinator.send(
            .blindSignatureResponses(PrimaryRuntimeTestFixtures.blindSignatureResponses)
        )

        await nowProvider.update(unixSeconds: 1_034)
        try await coordinator.send(.allCommitments(PrimaryRuntimeTestFixtures.allCommitments))

        await covertTransport.enqueueResponse(
            try PrimaryRuntimeTestFixtures.encodeCovertResponsePayload(
                PrimaryRuntimeTestFixtures.acknowledgement
            )
        )
        await nowProvider.update(unixSeconds: 1_035)
        try await LiveRuntimeTestHarness.withTimeout(.seconds(1)) {
            while (await covertTransport.recordedRequests).count < 1 {
                try await Task.sleep(for: .milliseconds(10))
            }
        }

        await nowProvider.update(unixSeconds: 1_040)
        try await coordinator.send(.shareCovertComponents(PrimaryRuntimeTestFixtures.sharedComponents))

        await covertTransport.enqueueResponse(
            try PrimaryRuntimeTestFixtures.encodeCovertResponsePayload(
                PrimaryRuntimeTestFixtures.acknowledgement
            )
        )
        await nowProvider.update(unixSeconds: 1_050)
        try await LiveRuntimeTestHarness.withTimeout(.seconds(1)) {
            while (await covertTransport.recordedRequests).count < 2 {
                try await Task.sleep(for: .milliseconds(10))
            }
        }

        await nowProvider.update(unixSeconds: 1_055)
        try await coordinator.send(.fusionResult(PrimaryRuntimeTestFixtures.successResult))

        let snapshot = try await LiveRuntimeTestHarness.withTimeout(.seconds(1)) {
            while true {
                let snapshot = await driver.currentSnapshot
                if snapshot.clientState.round?.completionStatus == .success {
                    return snapshot
                }
                try await Task.sleep(for: .milliseconds(10))
            }
        }

        #expect(snapshot.lastError == nil)
        #expect(snapshot.clientState.isConnected)
        #expect(snapshot.clientState.round?.phase == .completed)
        #expect(snapshot.clientState.round?.completionStatus == .success)
        #expect(await participantReservationSource.requestedRounds == [PrimaryRuntimeTestFixtures.roundIdentifier])
        #expect(
            await participantReservationSource.requestedContexts
                == [PrimaryRuntimeTestFixtures.participantReservationContext]
        )
        #expect(await transactionAssembler.requestedRounds == [PrimaryRuntimeTestFixtures.roundIdentifier])

        let events = await eventSink.recordedSnapshots
        #expect(events.contains { $0.event.summary == "Round completed successfully" })

        await driver.stop()
        await coordinator.stop()
    }
}

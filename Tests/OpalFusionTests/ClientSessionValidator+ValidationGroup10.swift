// ClientSessionValidator+ValidationGroup10.swift

@testable import OpalFusion
import Foundation
import Testing

extension ClientSessionValidator {
    @Test("Public client session completes a scripted loopback round and forwards observers")
    func validateScriptedLoopbackRound() async throws {
        let coordinator = try await LoopbackPrimaryCoordinator.start()
        let covertTransport = ScriptedCovertTransport()
        let stateObserver = RecordedClientStateObserver()
        let eventObserver = RecordedRoundEventObserver()
        let participantReservationSource = DelayedParticipantReservationSource(
            participantInputs: [PrimaryRuntimeTestFixtures.participantInput],
            participantOutputs: [PrimaryRuntimeTestFixtures.participantOutput],
            delay: .milliseconds(10)
        )
        let transactionAssembler = DelayedTransactionAssembler(
            finalizedTransaction: PrimaryRuntimeTestFixtures.finalizedTransaction,
            delay: .milliseconds(10)
        )
        let nowProvider = ScriptedInstantClock(unixSeconds: 995)
        let session = OpalFusion.Client.Session(
            configuration: .init(
                coordinatorHost: "127.0.0.1",
                coordinatorPort: await coordinator.port,
                covertChannel: PrimaryRuntimeTestFixtures.configuration.covertChannel
            ),
            genesisHash: PrimaryRuntimeTestFixtures.clientHello.genesisHash,
            joinPools: PrimaryRuntimeTestFixtures.joinPools,
            participantReservationSource: participantReservationSource,
            transactionAssembler: transactionAssembler,
            eventObserver: eventObserver,
            stateObserver: stateObserver,
            workflow: PrimaryRuntimeTestFixtures.workflow,
            nowProvider: { await nowProvider.current },
            clockTickInterval: .milliseconds(100),
            covertTransportFactory: { covertTransport }
        )

        await session.start()
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

        let snapshot = try await SessionTranscriptHarness.waitForSessionSuccessOrFatalTermination(
            session: session,
            timeout: .seconds(1),
            pollInterval: .milliseconds(10)
        )

        #expect(snapshot.lastError == nil)
        #expect(snapshot.state.isConnected)
        #expect(snapshot.state.round?.phase == .completed)
        #expect(snapshot.state.round?.completionStatus == .success)

        let observedEvents = await eventObserver.recordedSnapshots
        #expect(observedEvents.contains { $0.event.summary == "Round completed successfully" })

        let observedSnapshots = try await LiveRuntimeTestHarness.withTimeout(.seconds(1)) {
            while true {
                let observedSnapshots = await stateObserver.recordedSnapshots
                if observedSnapshots.contains(
                    where: { $0.state.round?.completionStatus == .success }
                ) {
                    return observedSnapshots
                }
                try await Task.sleep(for: .milliseconds(10))
            }
        }
        #expect(observedSnapshots.contains { $0.state.isConnected && $0.state.round == nil })
        #expect(observedSnapshots.contains { $0.state.round?.completionStatus == .success })

        await session.stop()
        await coordinator.stop()
    }
}

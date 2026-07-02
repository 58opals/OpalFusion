// ClientSessionValidator+ValidationGroup11.swift

@testable import OpalFusion
import Foundation
import Testing

extension ClientSessionValidator {
    @Test("Public client session completes a production-workflow round over a loopback coordinator")
    func validateProductionWorkflowLoopbackRound() async throws {
        var scenario = try ProductionWorkflowTestFixtures.makeScenario()
        let coordinator = try await LoopbackPrimaryCoordinator.start()
        let covertTransport = ScriptedCovertTransport()
        let participantReservationSource = DelayedParticipantReservationSource(
            participantInputs: scenario.reservation.inputs,
            participantOutputs: scenario.reservation.outputs,
            delay: .milliseconds(10)
        )
        let transactionAssembler = SigningTransactionAssembler(
            participantInput: scenario.reservation.inputs[0],
            participantInputPrivateKey: scenario.participantInputPrivateKey,
            delay: .milliseconds(10)
        )
        let nowProvider = ScriptedInstantClock(unixSeconds: 995)
        let stateObserver = RecordedClientStateObserver()
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
            stateObserver: stateObserver,
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
        try await coordinator.send(.serverHello(scenario.serverHello))
        #expect(
            try await coordinator.readNextClientMessage()
                == .joinPools(PrimaryRuntimeTestFixtures.joinPools)
        )

        await nowProvider.update(unixSeconds: 1_000)
        try await coordinator.send(.fusionBegin(scenario.fusionBegin))
        try await LiveRuntimeTestHarness.withTimeout(.seconds(1)) {
            while (await covertTransport.recordedPreparationPlans).isEmpty {
                try await Task.sleep(for: .milliseconds(10))
            }
        }

        await nowProvider.update(unixSeconds: 1_030)
        try await coordinator.send(.startRound(scenario.startRound))
        let playerCommitMessage = try await coordinator.readNextClientMessage()
        guard case let .playerCommit(playerCommit) = playerCommitMessage else {
            Issue.record("Expected a production PlayerCommit after StartRound")
            await session.stop()
            await coordinator.stop()
            return
        }

        let blindResponses = try await scenario.buildBlindSignatureResponses(for: playerCommit)
        await nowProvider.update(unixSeconds: 1_032)
        try await coordinator.send(.blindSignatureResponses(blindResponses))

        await nowProvider.update(unixSeconds: 1_034)
        try await coordinator.send(
            .allCommitments(.init(initialCommitments: playerCommit.initialCommitments))
        )

        for _ in 0..<playerCommit.initialCommitments.count {
            await covertTransport.enqueueResponse(
                try PrimaryRuntimeTestFixtures.encodeCovertResponsePayload(
                    PrimaryRuntimeTestFixtures.acknowledgement
                )
            )
        }
        await nowProvider.update(unixSeconds: 1_035)
        let componentRequests = try await LiveRuntimeTestHarness.withTimeout(.seconds(1)) {
            while true {
                let requests = await covertTransport.recordedRequests
                if requests.count == playerCommit.initialCommitments.count {
                    return requests
                }
                try await Task.sleep(for: .milliseconds(10))
            }
        }
        let sharedSerializedComponents = try componentRequests.map { request in
            guard case let .component(componentMessage) = try PrimaryRuntimeTestFixtures
                .extractCovertMessage(from: request) else {
                throw LiveRuntimeTestHarnessError.inboundStreamClosed
            }
            return componentMessage.serializedComponent
        }

        await nowProvider.update(unixSeconds: 1_040)
        try await coordinator.send(
            .shareCovertComponents(
                .init(
                    serializedComponents: sharedSerializedComponents,
                    skipSignatures: false,
                    sessionHash: nil
                )
            )
        )

        try await LiveRuntimeTestHarness.withTimeout(.seconds(1)) {
            while (await transactionAssembler.recordedProposals).isEmpty {
                try await Task.sleep(for: .milliseconds(10))
            }
        }

        await covertTransport.enqueueResponse(
            try PrimaryRuntimeTestFixtures.encodeCovertResponsePayload(
                PrimaryRuntimeTestFixtures.acknowledgement
            )
        )
        await nowProvider.update(unixSeconds: 1_050)
        try await LiveRuntimeTestHarness.withTimeout(.seconds(1)) {
            while (await covertTransport.recordedRequests).count < playerCommit.initialCommitments.count + 1 {
                try await Task.sleep(for: .milliseconds(10))
            }
        }

        await nowProvider.update(unixSeconds: 1_055)
        try await coordinator.send(
            .fusionResult(
                .init(
                    isSuccess: true,
                    transactionSignatures: [],
                    badComponentIndices: []
                )
            )
        )

        let snapshot = try await LiveRuntimeTestHarness.withTimeout(.seconds(1)) {
            while true {
                let snapshot = await session.currentSnapshot
                if snapshot.state.round?.completionStatus == .success {
                    return snapshot
                }
                try await Task.sleep(for: .milliseconds(10))
            }
        }

        #expect(snapshot.lastError == nil)
        #expect(snapshot.state.isConnected)
        #expect(snapshot.state.round?.phase == .completed)
        #expect(snapshot.state.round?.completionStatus == .success)
        #expect(
            await participantReservationSource.requestedRounds
                == [scenario.round.identifier!]
        )
        #expect(
            await transactionAssembler.requestedRounds
                == [scenario.round.identifier!]
        )
        let observedSnapshots = await stateObserver.recordedSnapshots
        #expect(observedSnapshots.contains { $0.state.round?.completionStatus == .success })

        await session.stop()
        await coordinator.stop()
    }
}

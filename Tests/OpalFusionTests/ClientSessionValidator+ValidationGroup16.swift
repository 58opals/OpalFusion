// ClientSessionValidator+ValidationGroup16.swift

@testable import OpalFusion
import Foundation
import Testing

extension ClientSessionValidator {
    @Test("Public client session fails unsupported finalized transactions before signature submission")
    func validateUnsupportedFinalizedTransactionProjection() async throws {
        var scenario = try ProductionWorkflowTestFixtures.makeScenario()
        let coordinator = try await LoopbackPrimaryCoordinator.start()
        let covertTransport = ScriptedCovertTransport()
        let stateObserver = RecordedClientStateObserver()
        let eventObserver = RecordedRoundEventObserver()
        let participantReservationSource = DelayedParticipantReservationSource(
            participantInputs: scenario.reservation.inputs,
            participantOutputs: scenario.reservation.outputs,
            delay: .milliseconds(10)
        )
        let transactionAssembler = SigningTransactionAssembler(
            participantInput: scenario.reservation.inputs[0],
            participantInputPrivateKey: scenario.participantInputPrivateKey,
            unlockingScriptBuilder: { signature, publicKey in
                [0x4C, 0x40] + signature + [0x21] + publicKey
            },
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
            hostParticipantReservationSource: participantReservationSource,
            hostTransactionAssembler: transactionAssembler,
            eventObserver: eventObserver,
            stateObserver: stateObserver,
            nowProvider: { await nowProvider.current },
            clockTickInterval: .milliseconds(100),
            covertTransportFactory: { covertTransport }
        )

        await session.start()
        _ = try await coordinator.readNextClientMessage()

        await nowProvider.update(unixSeconds: 996)
        try await coordinator.send(.serverHello(scenario.serverHello))
        _ = try await coordinator.readNextClientMessage()

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
            Issue.record("Expected a production PlayerCommit before finalized-transaction failure coverage")
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

        let snapshot = try await LiveRuntimeTestHarness.withTimeout(.seconds(1)) {
            while true {
                let snapshot = await session.currentSnapshot
                if snapshot.lastError == .notImplemented {
                    return snapshot
                }
                try await Task.sleep(for: .milliseconds(10))
            }
        }

        #expect(snapshot.state.round?.phase == .completed)
        #expect(snapshot.state.round?.completionStatus == .hostRejected)
        #expect(await transactionAssembler.requestedRounds == [scenario.round.identifier!])
        #expect(
            (await covertTransport.recordedRequests).count
                == playerCommit.initialCommitments.count
        )

        let observedEvents = await eventObserver.recordedSnapshots
        #expect(
            observedEvents.contains {
                $0.event.summary == OpalFusion.Execution.ProtocolPrimitives.supportedUnlockingScriptSummary
            }
        )
        #expect(
            observedEvents.contains {
                $0.event.summary == "Shared components received; requesting transaction finalization"
            }
        )

        let observedSnapshots = await stateObserver.recordedSnapshots
        #expect(
            observedSnapshots.contains {
                $0.lastError == .notImplemented &&
                    $0.state.round?.completionStatus == .hostRejected
            }
        )

        await session.stop()
        await coordinator.stop()
    }
}

// ClientSessionValidator.swift

@testable import OpalFusion
import Foundation
import Testing

struct ClientSessionValidator {
    @Test("Public client session projects invalid configuration through snapshots and state observation")
    func validateInvalidConfigurationProjection() async throws {
        let stateObserver = RecordedClientStateObserver()
        let session = OpalFusion.Client.Session(
            configuration: .init(
                coordinatorHost: "",
                coordinatorPort: PrimaryRuntimeTestFixtures.configuration.coordinatorPort,
                covertChannel: PrimaryRuntimeTestFixtures.configuration.covertChannel
            ),
            genesisHash: PrimaryRuntimeTestFixtures.clientHello.genesisHash,
            joinPools: PrimaryRuntimeTestFixtures.joinPools,
            participantInputProvider: HostParticipantInputProviderAdapter(
                participantInputs: [PrimaryRuntimeTestFixtures.participantInput]
            ),
            transactionAssembler: HostTransactionAssemblerAdapter(
                finalizedTransaction: PrimaryRuntimeTestFixtures.finalizedTransaction
            ),
            stateObserver: stateObserver
        )

        await session.start()

        let snapshot = await session.snapshot()
        #expect(snapshot.lastError == .invalidConfiguration)
        #expect(snapshot.state.isConnected == false)
        #expect(snapshot.state.round == nil)

        let observedSnapshots = await stateObserver.snapshot()
        #expect(observedSnapshots.contains(snapshot))
    }

    @Test("Public client session maps primary connect failure to transport unavailable")
    func validateConnectFailureProjection() async throws {
        let stateObserver = RecordedClientStateObserver()
        let transportFactories = SessionTransportFactoryRecorder(
            primaryConnectError: NSError(domain: "ClientSessionValidator", code: 1)
        )
        let session = OpalFusion.Client.Session(
            configuration: PrimaryRuntimeTestFixtures.configuration,
            genesisHash: PrimaryRuntimeTestFixtures.clientHello.genesisHash,
            joinPools: PrimaryRuntimeTestFixtures.joinPools,
            participantInputProvider: HostParticipantInputProviderAdapter(
                participantInputs: [PrimaryRuntimeTestFixtures.participantInput]
            ),
            transactionAssembler: HostTransactionAssemblerAdapter(
                finalizedTransaction: PrimaryRuntimeTestFixtures.finalizedTransaction
            ),
            stateObserver: stateObserver,
            primaryTransportFactory: { transportFactories.makePrimary() },
            covertTransportFactory: { transportFactories.makeCovert() }
        )

        await session.start()

        let snapshot = await session.snapshot()
        #expect(snapshot.lastError == .transportUnavailable)
        #expect(snapshot.state.isConnected == false)
        #expect(transportFactories.primaryCount() == 1)

        let observedSnapshots = await stateObserver.snapshot()
        #expect(observedSnapshots.contains(snapshot))
    }

    @Test("Public client session start and stop are idempotent and restart creates a fresh driver")
    func validateLifecycleIdempotenceAndRestart() async throws {
        let stateObserver = RecordedClientStateObserver()
        let transportFactories = SessionTransportFactoryRecorder()
        let session = OpalFusion.Client.Session(
            configuration: PrimaryRuntimeTestFixtures.configuration,
            genesisHash: PrimaryRuntimeTestFixtures.clientHello.genesisHash,
            joinPools: PrimaryRuntimeTestFixtures.joinPools,
            participantInputProvider: HostParticipantInputProviderAdapter(
                participantInputs: [PrimaryRuntimeTestFixtures.participantInput]
            ),
            transactionAssembler: HostTransactionAssemblerAdapter(
                finalizedTransaction: PrimaryRuntimeTestFixtures.finalizedTransaction
            ),
            stateObserver: stateObserver,
            primaryTransportFactory: { transportFactories.makePrimary() },
            covertTransportFactory: { transportFactories.makeCovert() }
        )

        await session.start()
        await session.start()

        let runningSnapshot = try await withTimeout(.seconds(1)) {
            while true {
                let snapshot = await session.snapshot()
                if snapshot.state.isConnected {
                    return snapshot
                }
                try await Task.sleep(for: .milliseconds(10))
            }
        }
        #expect(runningSnapshot.lastError == nil)
        #expect(transportFactories.primaryCount() == 1)

        await session.stop()
        await session.stop()

        let stoppedSnapshot = await session.snapshot()
        #expect(stoppedSnapshot == runningSnapshot)

        await session.start()
        let restartedSnapshot = try await withTimeout(.seconds(1)) {
            while true {
                let snapshot = await session.snapshot()
                if snapshot.state.isConnected {
                    return snapshot
                }
                try await Task.sleep(for: .milliseconds(10))
            }
        }

        #expect(restartedSnapshot.lastError == nil)
        #expect(transportFactories.primaryCount() == 2)

        let observedSnapshots = await stateObserver.snapshot()
        #expect(observedSnapshots.contains(runningSnapshot))
        #expect(
            observedSnapshots.contains(
                .init(
                    state: .init(),
                    lastError: nil
                )
            )
        )
    }

    @Test("Public client session completes a scripted loopback round and forwards observers")
    func validateScriptedLoopbackRound() async throws {
        let coordinator = try await LoopbackPrimaryCoordinator.start()
        let covertTransport = ScriptedCovertTransport()
        let stateObserver = RecordedClientStateObserver()
        let eventObserver = RecordedRoundEventObserver()
        let participantInputProvider = DelayedParticipantInputProvider(
            participantInputs: [PrimaryRuntimeTestFixtures.participantInput],
            participantOutputs: [PrimaryRuntimeTestFixtures.participantOutput],
            delay: .milliseconds(10)
        )
        let transactionAssembler = DelayedTransactionAssembler(
            finalizedTransaction: PrimaryRuntimeTestFixtures.finalizedTransaction,
            delay: .milliseconds(10)
        )
        let nowProvider = ScriptedNowProvider(unixSeconds: 995)
        let session = OpalFusion.Client.Session(
            configuration: .init(
                coordinatorHost: "127.0.0.1",
                coordinatorPort: await coordinator.port,
                covertChannel: PrimaryRuntimeTestFixtures.configuration.covertChannel
            ),
            genesisHash: PrimaryRuntimeTestFixtures.clientHello.genesisHash,
            joinPools: PrimaryRuntimeTestFixtures.joinPools,
            participantInputProvider: participantInputProvider,
            transactionAssembler: transactionAssembler,
            eventObserver: eventObserver,
            stateObserver: stateObserver,
            workflow: PrimaryRuntimeTestFixtures.workflow,
            nowProvider: { nowProvider.now() },
            clockTickInterval: .milliseconds(10),
            covertTransportFactory: { covertTransport }
        )

        await session.start()
        #expect(
            try await coordinator.nextClientMessage()
                == .clientHello(PrimaryRuntimeTestFixtures.clientHello)
        )

        nowProvider.set(unixSeconds: 996)
        try await coordinator.send(.serverHello(PrimaryRuntimeTestFixtures.serverHello))
        #expect(
            try await coordinator.nextClientMessage()
                == .joinPools(PrimaryRuntimeTestFixtures.joinPools)
        )

        nowProvider.set(unixSeconds: 1_000)
        try await coordinator.send(.fusionBegin(PrimaryRuntimeTestFixtures.fusionBegin))
        try await withTimeout(.seconds(1)) {
            while await covertTransport.recordedPreparationPlans().isEmpty {
                try await Task.sleep(for: .milliseconds(10))
            }
        }

        nowProvider.set(unixSeconds: 1_030)
        try await coordinator.send(.startRound(PrimaryRuntimeTestFixtures.startRound))
        #expect(
            try await coordinator.nextClientMessage()
                == .playerCommit(PrimaryRuntimeTestFixtures.playerCommit)
        )

        nowProvider.set(unixSeconds: 1_032)
        try await coordinator.send(
            .blindSignatureResponses(PrimaryRuntimeTestFixtures.blindSignatureResponses)
        )

        nowProvider.set(unixSeconds: 1_034)
        try await coordinator.send(.allCommitments(PrimaryRuntimeTestFixtures.allCommitments))

        await covertTransport.enqueueResponse(
            try PrimaryRuntimeTestFixtures.encodeCovertResponsePayload(
                PrimaryRuntimeTestFixtures.acknowledgement
            )
        )
        nowProvider.set(unixSeconds: 1_035)
        try await withTimeout(.seconds(1)) {
            while await covertTransport.recordedRequests().count < 1 {
                try await Task.sleep(for: .milliseconds(10))
            }
        }

        nowProvider.set(unixSeconds: 1_040)
        try await coordinator.send(.shareCovertComponents(PrimaryRuntimeTestFixtures.sharedComponents))

        await covertTransport.enqueueResponse(
            try PrimaryRuntimeTestFixtures.encodeCovertResponsePayload(
                PrimaryRuntimeTestFixtures.acknowledgement
            )
        )
        nowProvider.set(unixSeconds: 1_050)
        try await withTimeout(.seconds(1)) {
            while await covertTransport.recordedRequests().count < 2 {
                try await Task.sleep(for: .milliseconds(10))
            }
        }

        nowProvider.set(unixSeconds: 1_055)
        try await coordinator.send(.fusionResult(PrimaryRuntimeTestFixtures.successResult))

        let snapshot = try await withTimeout(.seconds(1)) {
            while true {
                let snapshot = await session.snapshot()
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

        let observedEvents = await eventObserver.snapshot()
        #expect(observedEvents.contains { $0.event.summary == "Round completed successfully" })

        let observedSnapshots = await stateObserver.snapshot()
        #expect(observedSnapshots.contains { $0.state.isConnected && $0.state.round == nil })
        #expect(observedSnapshots.contains { $0.state.round?.completionStatus == .success })

        await session.stop()
        await coordinator.stop()
    }

    @Test("Public client session completes a production-workflow round over a loopback coordinator")
    func validateProductionWorkflowLoopbackRound() async throws {
        var scenario = try ProductionWorkflowTestFixtures.makeScenario()
        let coordinator = try await LoopbackPrimaryCoordinator.start()
        let covertTransport = ScriptedCovertTransport()
        let participantInputProvider = DelayedParticipantInputProvider(
            participantInputs: scenario.reservation.inputs,
            participantOutputs: scenario.reservation.outputs,
            delay: .milliseconds(10)
        )
        let transactionAssembler = SigningTransactionAssembler(
            participantInput: scenario.reservation.inputs[0],
            participantInputPrivateKey: scenario.participantInputPrivateKey,
            delay: .milliseconds(10)
        )
        let nowProvider = ScriptedNowProvider(unixSeconds: 995)
        let stateObserver = RecordedClientStateObserver()
        let session = OpalFusion.Client.Session(
            configuration: .init(
                coordinatorHost: "127.0.0.1",
                coordinatorPort: await coordinator.port,
                covertChannel: PrimaryRuntimeTestFixtures.configuration.covertChannel
            ),
            genesisHash: PrimaryRuntimeTestFixtures.clientHello.genesisHash,
            joinPools: PrimaryRuntimeTestFixtures.joinPools,
            participantInputProvider: participantInputProvider,
            transactionAssembler: transactionAssembler,
            stateObserver: stateObserver,
            nowProvider: { nowProvider.now() },
            clockTickInterval: .milliseconds(10),
            covertTransportFactory: { covertTransport }
        )

        await session.start()
        _ = try await coordinator.nextClientMessage()

        nowProvider.set(unixSeconds: 996)
        try await coordinator.send(.serverHello(scenario.serverHello))
        _ = try await coordinator.nextClientMessage()

        nowProvider.set(unixSeconds: 1_000)
        try await coordinator.send(.fusionBegin(scenario.fusionBegin))
        try await withTimeout(.seconds(1)) {
            while await covertTransport.recordedPreparationPlans().isEmpty {
                try await Task.sleep(for: .milliseconds(10))
            }
        }

        nowProvider.set(unixSeconds: 1_030)
        try await coordinator.send(.startRound(scenario.startRound))
        let playerCommitMessage = try await coordinator.nextClientMessage()
        guard case let .playerCommit(playerCommit) = playerCommitMessage else {
            Issue.record("Expected a production PlayerCommit after StartRound")
            await session.stop()
            await coordinator.stop()
            return
        }

        let blindResponses = try scenario.buildBlindSignatureResponses(for: playerCommit)
        nowProvider.set(unixSeconds: 1_032)
        try await coordinator.send(.blindSignatureResponses(blindResponses))

        nowProvider.set(unixSeconds: 1_034)
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
        nowProvider.set(unixSeconds: 1_035)
        let componentRequests = try await withTimeout(.seconds(1)) {
            while true {
                let requests = await covertTransport.recordedRequests()
                if requests.count == playerCommit.initialCommitments.count {
                    return requests
                }
                try await Task.sleep(for: .milliseconds(10))
            }
        }
        let sharedSerializedComponents = try componentRequests.map { request in
            guard case let .component(componentMessage) = try PrimaryRuntimeTestFixtures
                .extractCovertMessage(from: request) else {
                throw LiveRuntimeTestSupportError.inboundStreamClosed
            }
            return componentMessage.serializedComponent
        }

        nowProvider.set(unixSeconds: 1_040)
        try await coordinator.send(
            .shareCovertComponents(
                .init(
                    serializedComponents: sharedSerializedComponents,
                    skipSignatures: false,
                    sessionHash: nil
                )
            )
        )

        try await withTimeout(.seconds(1)) {
            while await transactionAssembler.recordedProposals().isEmpty {
                try await Task.sleep(for: .milliseconds(10))
            }
        }

        await covertTransport.enqueueResponse(
            try PrimaryRuntimeTestFixtures.encodeCovertResponsePayload(
                PrimaryRuntimeTestFixtures.acknowledgement
            )
        )
        nowProvider.set(unixSeconds: 1_050)
        try await withTimeout(.seconds(1)) {
            while await covertTransport.recordedRequests().count < playerCommit.initialCommitments.count + 1 {
                try await Task.sleep(for: .milliseconds(10))
            }
        }

        nowProvider.set(unixSeconds: 1_055)
        try await coordinator.send(
            .fusionResult(
                .init(
                    isSuccess: true,
                    transactionSignatures: [],
                    badComponentIndices: []
                )
            )
        )

        let snapshot = try await withTimeout(.seconds(1)) {
            while true {
                let snapshot = await session.snapshot()
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
            await participantInputProvider.requestedRounds()
                == [scenario.round.identifier!]
        )
        #expect(
            await transactionAssembler.requestedRounds()
                == [scenario.round.identifier!]
        )
        let observedSnapshots = await stateObserver.snapshot()
        #expect(observedSnapshots.contains { $0.state.round?.completionStatus == .success })

        await session.stop()
        await coordinator.stop()
    }
}

private final class SessionTransportFactoryRecorder: @unchecked Sendable {
    private let primaryConnectError: Error?
    private let lock = NSLock()
    private var primaryTransports: [ScriptedPrimaryTransport] = []
    private var covertTransports: [ScriptedCovertTransport] = []

    init(primaryConnectError: Error? = nil) {
        self.primaryConnectError = primaryConnectError
    }

    func makePrimary() -> any OpalFusion.Runtime.PrimaryTransporting {
        let transport = ScriptedPrimaryTransport(connectError: primaryConnectError)
        lock.lock()
        primaryTransports.append(transport)
        lock.unlock()
        return transport
    }

    func makeCovert() -> any OpalFusion.Runtime.CovertTransporting {
        let transport = ScriptedCovertTransport()
        lock.lock()
        covertTransports.append(transport)
        lock.unlock()
        return transport
    }

    func primaryCount() -> Int {
        lock.withLock {
            primaryTransports.count
        }
    }
}

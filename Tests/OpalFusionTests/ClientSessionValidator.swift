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
        #expect(snapshot.lastErrorSummary == "Coordinator host must not be empty")
        #expect(snapshot.state.isConnected == false)
        #expect(snapshot.state.round == nil)

        let observedSnapshots = await stateObserver.snapshot()
        #expect(observedSnapshots.contains(snapshot))
        #expect(observedSnapshots.contains {
            $0.lastError == .invalidConfiguration &&
                $0.lastErrorSummary == "Coordinator host must not be empty"
        })
    }

    @Test("Public client configuration keeps coordinator TLS opt-in disabled by default")
    func validateCoordinatorRequiresTLSDefault() {
        let configuration = OpalFusion.Client.Configuration(
            coordinatorHost: "fusion.example.org",
            coordinatorPort: 8_787,
            covertChannel: PrimaryRuntimeTestFixtures.configuration.covertChannel
        )

        #expect(configuration.coordinatorRequiresTLS == false)
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
        #expect(snapshot.lastErrorSummary?.hasPrefix("Primary connect failed:") == true)
        #expect(snapshot.state.isConnected == false)
        #expect(transportFactories.primaryCount() == 1)

        let observedSnapshots = await stateObserver.snapshot()
        #expect(observedSnapshots.contains(snapshot))
        #expect(observedSnapshots.contains {
            $0.lastError == .transportUnavailable &&
                $0.lastErrorSummary?.hasPrefix("Primary connect failed:") == true
        })
    }

    @Test("Public client session surfaces TLS connect failures through primary diagnostics")
    func validateTLSConnectFailureProjection() async throws {
        let coordinator = try await LoopbackPrimaryCoordinator.start(requiresTLS: true)
        let port = await coordinator.port
        let stateObserver = RecordedClientStateObserver()
        let primaryTransport = OpalFusion.Runtime.LivePrimaryTransport(
            host: LoopbackPrimaryTLSTestFixture.host,
            port: port,
            requiresTLS: true
        )
        let session = OpalFusion.Client.Session(
            configuration: .init(
                coordinatorHost: LoopbackPrimaryTLSTestFixture.host,
                coordinatorPort: port,
                coordinatorRequiresTLS: true,
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
            stateObserver: stateObserver,
            primaryTransportFactory: { primaryTransport }
        )

        await session.start()

        let snapshot = await session.snapshot()
        #expect(snapshot.lastError == .transportUnavailable)
        #expect(snapshot.lastErrorSummary?.hasPrefix("Primary connect failed:") == true)
        #expect(snapshot.state.isConnected == false)

        let observedSnapshots = await stateObserver.snapshot()
        #expect(observedSnapshots.contains(snapshot))
        #expect(observedSnapshots.contains {
            $0.lastError == .transportUnavailable &&
                $0.lastErrorSummary?.hasPrefix("Primary connect failed:") == true
        })

        await session.stop()
        await coordinator.stop()
    }

    @Test("Public client session can exchange primary handshake messages over TLS")
    func validateTLSHandshakeProjection() async throws {
        let coordinator = try await LoopbackPrimaryCoordinator.start(requiresTLS: true)
        let port = await coordinator.port
        let stateObserver = RecordedClientStateObserver()
        let primaryTransport = try makeTrustedTLSPrimaryTransport(port: port)
        let session = OpalFusion.Client.Session(
            configuration: .init(
                coordinatorHost: LoopbackPrimaryTLSTestFixture.host,
                coordinatorPort: port,
                coordinatorRequiresTLS: true,
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
            stateObserver: stateObserver,
            primaryTransportFactory: { primaryTransport }
        )

        await session.start()
        #expect(
            try await coordinator.nextClientMessage()
                == .clientHello(PrimaryRuntimeTestFixtures.clientHello)
        )

        try await coordinator.send(.serverHello(PrimaryRuntimeTestFixtures.serverHello))
        #expect(
            try await coordinator.nextClientMessage()
                == .joinPools(PrimaryRuntimeTestFixtures.joinPools)
        )

        let snapshot = try await withTimeout(.seconds(1)) {
            while true {
                let snapshot = await session.snapshot()
                if snapshot.state.isConnected {
                    return snapshot
                }
                try await Task.sleep(for: .milliseconds(10))
            }
        }
        #expect(snapshot.lastError == nil)
        #expect(snapshot.lastErrorSummary == nil)

        let observedSnapshots = await stateObserver.snapshot()
        #expect(observedSnapshots.contains { $0.state.isConnected && $0.lastError == nil })

        await session.stop()
        await coordinator.stop()
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
        #expect(runningSnapshot.lastErrorSummary == nil)
        #expect(transportFactories.primaryCount() == 1)

        await session.stop()
        await session.stop()

        let stoppedSnapshot = try await withTimeout(.seconds(1)) {
            while true {
                let snapshot = await session.snapshot()
                if snapshot.state.isConnected == false {
                    return snapshot
                }
                try await Task.sleep(for: .milliseconds(10))
            }
        }
        #expect(stoppedSnapshot.lastError == .transportUnavailable)
        #expect(stoppedSnapshot.lastErrorSummary == "Primary channel disconnected")
        #expect(stoppedSnapshot.state.isConnected == false)
        #expect(stoppedSnapshot.state.round == runningSnapshot.state.round)

        let observedSnapshotsAfterStop = await stateObserver.snapshot()
        #expect(observedSnapshotsAfterStop.last == stoppedSnapshot)

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
        #expect(restartedSnapshot.lastErrorSummary == nil)
        #expect(transportFactories.primaryCount() == 2)

        let observedSnapshots = await stateObserver.snapshot()
        #expect(observedSnapshots.contains(runningSnapshot))
        #expect(
            observedSnapshots.contains(
                .init(
                    state: .init(),
                    lastError: nil,
                    lastErrorSummary: nil
                )
            )
        )
    }

    @Test("Public client session clears failure summaries on a fresh restart")
    func validateRestartClearsFailureSummary() async throws {
        let stateObserver = RecordedClientStateObserver()
        let transportFactories = SessionTransportFactoryRecorder(
            primaryConnectErrors: [
                NSError(domain: "ClientSessionValidator", code: 7),
                nil
            ]
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

        let failedSnapshot = await session.snapshot()
        #expect(failedSnapshot.lastError == .transportUnavailable)
        #expect(failedSnapshot.lastErrorSummary?.hasPrefix("Primary connect failed:") == true)

        await session.stop()
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
        #expect(restartedSnapshot.lastErrorSummary == nil)
        #expect(transportFactories.primaryCount() == 2)

        let observedSnapshots = await stateObserver.snapshot()
        #expect(observedSnapshots.contains {
            $0.lastError == .transportUnavailable &&
                $0.lastErrorSummary?.hasPrefix("Primary connect failed:") == true
        })
        #expect(
            observedSnapshots.contains(
                .init(
                    state: .init(),
                    lastError: nil,
                    lastErrorSummary: nil
                )
            )
        )
        #expect(observedSnapshots.contains(restartedSnapshot))
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
            clockTickInterval: .milliseconds(100),
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

        let snapshot = try await SessionTranscriptSupport.waitForSessionSuccessOrFatalTermination(
            session: session,
            timeout: .seconds(1),
            pollInterval: .milliseconds(10)
        )

        #expect(snapshot.lastError == nil)
        #expect(snapshot.state.isConnected)
        #expect(snapshot.state.round?.phase == .completed)
        #expect(snapshot.state.round?.completionStatus == .success)

        let observedEvents = await eventObserver.snapshot()
        #expect(observedEvents.contains { $0.event.summary == "Round completed successfully" })

        let observedSnapshots = try await withTimeout(.seconds(1)) {
            while true {
                let observedSnapshots = await stateObserver.snapshot()
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
            clockTickInterval: .milliseconds(100),
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

    @Test("Public client session reaches eventual success after a blame restart in one session")
    func validateEventualSessionSuccessAfterRestart() async throws {
        let coordinator = try await LoopbackPrimaryCoordinator.start()
        let scriptedCovertTransport = ScriptedCovertTransport()
        let recordingCovertTransport = RecordingCovertTransport(base: scriptedCovertTransport)
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
        let firstStartRound = PrimaryRuntimeTestFixtures.startRound
        let secondStartRound = OpalFusion.ProtocolModel.StartRound(
            roundPublicKey: [0xCC, 0xDD],
            blindNoncePoints: PrimaryRuntimeTestFixtures.startRound.blindNoncePoints,
            serverTimeUnixSeconds: 1_090
        )
        let secondFusionBegin = OpalFusion.ProtocolModel.FusionBegin(
            tier: PrimaryRuntimeTestFixtures.fusionBegin.tier,
            covertDomain: PrimaryRuntimeTestFixtures.fusionBegin.covertDomain,
            covertPort: PrimaryRuntimeTestFixtures.fusionBegin.covertPort,
            covertSsl: PrimaryRuntimeTestFixtures.fusionBegin.covertSsl,
            serverTimeUnixSeconds: 1_060
        )
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
            workflow: makeRoundAwareScriptedWorkflow(),
            nowProvider: { nowProvider.now() },
            clockTickInterval: .milliseconds(100),
            covertTransportFactory: { recordingCovertTransport }
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
            while await recordingCovertTransport.recordedPreparationPlans().isEmpty {
                try await Task.sleep(for: .milliseconds(10))
            }
        }

        nowProvider.set(unixSeconds: 1_030)
        try await coordinator.send(.startRound(firstStartRound))
        _ = try await coordinator.nextClientMessage()

        nowProvider.set(unixSeconds: 1_032)
        try await coordinator.send(
            .blindSignatureResponses(PrimaryRuntimeTestFixtures.blindSignatureResponses)
        )
        nowProvider.set(unixSeconds: 1_034)
        try await coordinator.send(.allCommitments(PrimaryRuntimeTestFixtures.allCommitments))

        await scriptedCovertTransport.enqueueResponse(
            try PrimaryRuntimeTestFixtures.encodeCovertResponsePayload(
                PrimaryRuntimeTestFixtures.acknowledgement
            )
        )
        nowProvider.set(unixSeconds: 1_035)
        try await withTimeout(.seconds(1)) {
            while await recordingCovertTransport.recordedRequests().count < 1 {
                try await Task.sleep(for: .milliseconds(10))
            }
        }

        nowProvider.set(unixSeconds: 1_040)
        try await coordinator.send(.shareCovertComponents(PrimaryRuntimeTestFixtures.sharedComponents))

        await scriptedCovertTransport.enqueueResponse(
            try PrimaryRuntimeTestFixtures.encodeCovertResponsePayload(
                PrimaryRuntimeTestFixtures.acknowledgement
            )
        )
        nowProvider.set(unixSeconds: 1_050)
        try await withTimeout(.seconds(1)) {
            while await recordingCovertTransport.recordedRequests().count < 2 {
                try await Task.sleep(for: .milliseconds(10))
            }
        }

        nowProvider.set(unixSeconds: 1_055)
        try await coordinator.send(.fusionResult(PrimaryRuntimeTestFixtures.failureResult))
        #expect(
            try await coordinator.nextClientMessage()
                == .myProofsList(PrimaryRuntimeTestFixtures.myProofsList)
        )

        nowProvider.set(unixSeconds: 1_056)
        try await coordinator.send(.theirProofsList(PrimaryRuntimeTestFixtures.theirProofsList))
        #expect(
            try await coordinator.nextClientMessage()
                == .blames(PrimaryRuntimeTestFixtures.blames)
        )

        nowProvider.set(unixSeconds: 1_060)
        try await coordinator.send(.restartRound(.init()))

        try await withTimeout(.seconds(1)) {
            while true {
                let snapshot = await session.snapshot()
                if snapshot.state.isConnected && snapshot.state.round == nil {
                    return
                }
                try await Task.sleep(for: .milliseconds(10))
            }
        }

        nowProvider.set(unixSeconds: 1_060)
        try await coordinator.send(.fusionBegin(secondFusionBegin))
        try await withTimeout(.seconds(1)) {
            while await recordingCovertTransport.recordedPreparationPlans().count < 2 {
                try await Task.sleep(for: .milliseconds(10))
            }
        }

        nowProvider.set(unixSeconds: 1_090)
        try await coordinator.send(.startRound(secondStartRound))
        _ = try await coordinator.nextClientMessage()

        nowProvider.set(unixSeconds: 1_092)
        try await coordinator.send(
            .blindSignatureResponses(PrimaryRuntimeTestFixtures.blindSignatureResponses)
        )
        nowProvider.set(unixSeconds: 1_094)
        try await coordinator.send(.allCommitments(PrimaryRuntimeTestFixtures.allCommitments))

        await scriptedCovertTransport.enqueueResponse(
            try PrimaryRuntimeTestFixtures.encodeCovertResponsePayload(
                PrimaryRuntimeTestFixtures.acknowledgement
            )
        )
        nowProvider.set(unixSeconds: 1_095)
        try await withTimeout(.seconds(1)) {
            while await recordingCovertTransport.recordedRequests().count < 3 {
                try await Task.sleep(for: .milliseconds(10))
            }
        }

        nowProvider.set(unixSeconds: 1_100)
        try await coordinator.send(.shareCovertComponents(PrimaryRuntimeTestFixtures.sharedComponents))

        await scriptedCovertTransport.enqueueResponse(
            try PrimaryRuntimeTestFixtures.encodeCovertResponsePayload(
                PrimaryRuntimeTestFixtures.acknowledgement
            )
        )
        nowProvider.set(unixSeconds: 1_110)
        try await withTimeout(.seconds(1)) {
            while await recordingCovertTransport.recordedRequests().count < 4 {
                try await Task.sleep(for: .milliseconds(10))
            }
        }

        nowProvider.set(unixSeconds: 1_115)
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

        let firstRoundIdentifier = SessionTranscriptSupport.makeRoundIdentifier(
            from: firstStartRound.roundPublicKey
        )
        let secondRoundIdentifier = SessionTranscriptSupport.makeRoundIdentifier(
            from: secondStartRound.roundPublicKey
        )
        let transcript = SessionTranscript(
            clientMessageKinds: await coordinator.recordedClientMessages().map(
                SessionTranscriptSupport.clientKind
            ),
            serverMessageKinds: await coordinator.recordedServerMessages().map(
                SessionTranscriptSupport.serverKind
            ),
            covertMessageKinds: await recordingCovertTransport.recordedRequestMessages().map(
                SessionTranscriptSupport.covertKind
            ),
            roundEvents: await eventObserver.timedSnapshot(),
            stateSnapshots: await stateObserver.timedSnapshot(),
            reservationRequests: await participantInputProvider.timedRequestRecords(),
            transactionProposals: await transactionAssembler.timedProposalRecords()
        )

        #expect(transcript.reservationRequests.map(\.roundIdentifier) == [firstRoundIdentifier, secondRoundIdentifier])
        #expect(transcript.transactionProposals.map(\.roundIdentifier) == [firstRoundIdentifier, secondRoundIdentifier])
        #expect(
            transcript.roundOutcomes.contains {
                $0.roundIdentifier == firstRoundIdentifier && $0.outcome == .blameRequired
            }
        )
        #expect(
            transcript.roundOutcomes.contains {
                $0.roundIdentifier == firstRoundIdentifier && $0.outcome == .restarted
            }
        )
        #expect(
            transcript.roundOutcomes.contains {
                $0.roundIdentifier == secondRoundIdentifier && $0.outcome == .success
            }
        )
        #expect(
            SessionTranscriptSupport.containsSubsequence(
                transcript.roundEvents.map(\.event.summary),
                subsequence: [
                    "Round result requires blame handling",
                    "Submitting blame proofs and awaiting restart",
                    "Restarting round after blame handling",
                    "Round completed successfully",
                ]
            )
        )
        #expect(
            transcript.stateSnapshots.contains {
                $0.snapshot.state.isConnected && $0.snapshot.state.round == nil
            }
        )
        #expect(
            transcript.stateSnapshots.contains {
                $0.snapshot.state.round?.completionStatus == .success
            }
        )
        guard
            let restartedConnectedSnapshotTime = transcript.stateSnapshots.first(where: {
                $0.snapshot.state.isConnected && $0.snapshot.state.round == nil
            })?.recordedAt,
            let successSnapshotTime = transcript.stateSnapshots.first(where: {
                $0.snapshot.state.round?.completionStatus == .success
            })?.recordedAt
        else {
            Issue.record("Expected timed restart and success snapshots for ordering coverage")
            await session.stop()
            await coordinator.stop()
            return
        }
        #expect(restartedConnectedSnapshotTime <= successSnapshotTime)

        await session.stop()
        await coordinator.stop()
    }

    @Test("Public client session surfaces unsupported participant reservations early")
    func validateUnsupportedReservationProjection() async throws {
        let scenario = try ProductionWorkflowTestFixtures.makeScenario()
        let coordinator = try await LoopbackPrimaryCoordinator.start()
        let covertTransport = ScriptedCovertTransport()
        let stateObserver = RecordedClientStateObserver()
        let eventObserver = RecordedRoundEventObserver()
        let unsupportedInput = OpalFusion.Host.ParticipantInput(
            outpointTransactionHash: scenario.reservation.inputs[0].outpointTransactionHash,
            outpointIndex: scenario.reservation.inputs[0].outpointIndex,
            amountSatoshis: scenario.reservation.inputs[0].amountSatoshis,
            lockingScript: [0x51],
            publicKey: scenario.reservation.inputs[0].publicKey
        )
        let participantInputProvider = DelayedParticipantInputProvider(
            participantInputs: [unsupportedInput],
            participantOutputs: scenario.reservation.outputs,
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
            nowProvider: { nowProvider.now() },
            clockTickInterval: .milliseconds(100),
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

        let snapshot = try await withTimeout(.seconds(1)) {
            while true {
                let snapshot = await session.snapshot()
                if snapshot.lastError == .notImplemented {
                    return snapshot
                }
                try await Task.sleep(for: .milliseconds(10))
            }
        }

        #expect(snapshot.state.round?.phase == .completed)
        #expect(snapshot.state.round?.completionStatus == .hostRejected)
        #expect(await transactionAssembler.requestedRounds().isEmpty)

        let observedEvents = await eventObserver.snapshot()
        #expect(
            observedEvents.contains {
                $0.event.summary == OpalFusion.Execution.ProtocolPrimitives.supportedParticipantInputSummary
            }
        )

        let observedSnapshots = await stateObserver.snapshot()
        #expect(
            observedSnapshots.contains {
                $0.lastError == .notImplemented &&
                    $0.state.round?.completionStatus == .hostRejected
            }
        )

        await session.stop()
        let stoppedSnapshot = await session.snapshot()
        #expect(stoppedSnapshot.lastError == .notImplemented)
        #expect(stoppedSnapshot.state.isConnected == false)
        #expect(stoppedSnapshot.state.round == snapshot.state.round)

        await coordinator.stop()
    }

    @Test("Public client session snapshot polling does not suppress observer delivery")
    func validateSnapshotPollingDoesNotSuppressObserverDelivery() async throws {
        let scenario = try ProductionWorkflowTestFixtures.makeScenario()
        let coordinator = try await LoopbackPrimaryCoordinator.start()
        let covertTransport = ScriptedCovertTransport()
        let stateObserver = RecordedClientStateObserver()
        let eventObserver = RecordedRoundEventObserver()
        let snapshotDeliveryGate = SessionSnapshotDeliveryGate()
        let unsupportedInput = OpalFusion.Host.ParticipantInput(
            outpointTransactionHash: scenario.reservation.inputs[0].outpointTransactionHash,
            outpointIndex: scenario.reservation.inputs[0].outpointIndex,
            amountSatoshis: scenario.reservation.inputs[0].amountSatoshis,
            lockingScript: [0x51],
            publicKey: scenario.reservation.inputs[0].publicKey
        )
        let participantInputProvider = DelayedParticipantInputProvider(
            participantInputs: [unsupportedInput],
            participantOutputs: scenario.reservation.outputs,
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
            nowProvider: { nowProvider.now() },
            clockTickInterval: .milliseconds(100),
            covertTransportFactory: { covertTransport },
            snapshotDeliveryHook: { snapshot in
                if isUnsupportedReservationConnectedTerminalSnapshot(snapshot) {
                    await snapshotDeliveryGate.block(snapshot)
                }
            }
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

        let blockedSnapshot = try await withTimeout(.seconds(1)) {
            await snapshotDeliveryGate.waitForBlockedSnapshot()
        }
        #expect(isUnsupportedReservationConnectedTerminalSnapshot(blockedSnapshot))

        let polledSnapshot = await session.snapshot()
        #expect(polledSnapshot.lastError == .notImplemented)
        #expect(polledSnapshot.state.round?.completionStatus == .hostRejected)
        #expect(
            (await stateObserver.snapshot()).contains(
                where: isUnsupportedReservationConnectedTerminalSnapshot
            ) == false
        )

        await snapshotDeliveryGate.release()

        let observedSnapshots = try await withTimeout(.seconds(1)) {
            while true {
                let observedSnapshots = await stateObserver.snapshot()
                if observedSnapshots.filter(
                    isUnsupportedReservationConnectedTerminalSnapshot
                ).count == 1 {
                    return observedSnapshots
                }
                try await Task.sleep(for: .milliseconds(10))
            }
        }

        #expect(
            observedSnapshots.filter(
                isUnsupportedReservationConnectedTerminalSnapshot
            ).count == 1
        )

        await session.stop()
        await coordinator.stop()
    }

    @Test("Public client session fails unsupported finalized transactions before signature submission")
    func validateUnsupportedFinalizedTransactionProjection() async throws {
        var scenario = try ProductionWorkflowTestFixtures.makeScenario()
        let coordinator = try await LoopbackPrimaryCoordinator.start()
        let covertTransport = ScriptedCovertTransport()
        let stateObserver = RecordedClientStateObserver()
        let eventObserver = RecordedRoundEventObserver()
        let participantInputProvider = DelayedParticipantInputProvider(
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
            nowProvider: { nowProvider.now() },
            clockTickInterval: .milliseconds(100),
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
            Issue.record("Expected a production PlayerCommit before finalized-transaction failure coverage")
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

        let snapshot = try await withTimeout(.seconds(1)) {
            while true {
                let snapshot = await session.snapshot()
                if snapshot.lastError == .notImplemented {
                    return snapshot
                }
                try await Task.sleep(for: .milliseconds(10))
            }
        }

        #expect(snapshot.state.round?.phase == .completed)
        #expect(snapshot.state.round?.completionStatus == .hostRejected)
        #expect(await transactionAssembler.requestedRounds() == [scenario.round.identifier!])
        #expect(
            await covertTransport.recordedRequests().count
                == playerCommit.initialCommitments.count
        )

        let observedEvents = await eventObserver.snapshot()
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

        let observedSnapshots = await stateObserver.snapshot()
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

private func isUnsupportedReservationConnectedTerminalSnapshot(
    _ snapshot: OpalFusion.Client.Session.Snapshot
) -> Bool {
    snapshot.lastError == .notImplemented &&
        snapshot.state.round?.completionStatus == .hostRejected &&
        snapshot.state.isConnected
}

private actor SessionSnapshotDeliveryGate {
    private var blockedSnapshot: OpalFusion.Client.Session.Snapshot?
    private var blockedSnapshotWaiters: [CheckedContinuation<
        OpalFusion.Client.Session.Snapshot,
        Never
    >] = []
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []
    private var isReleased = false

    func waitForBlockedSnapshot() async -> OpalFusion.Client.Session.Snapshot {
        if let blockedSnapshot {
            return blockedSnapshot
        }

        return await withCheckedContinuation { continuation in
            blockedSnapshotWaiters.append(continuation)
        }
    }

    func block(_ snapshot: OpalFusion.Client.Session.Snapshot) async {
        if blockedSnapshot == nil {
            blockedSnapshot = snapshot
            let waiters = blockedSnapshotWaiters
            self.blockedSnapshotWaiters.removeAll()
            for waiter in waiters {
                waiter.resume(returning: snapshot)
            }
        }

        if isReleased {
            return
        }

        await withCheckedContinuation { continuation in
            releaseWaiters.append(continuation)
        }
    }

    func release() {
        isReleased = true
        let waiters = releaseWaiters
        self.releaseWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
    }
}

private final class SessionTransportFactoryRecorder: @unchecked Sendable {
    private let defaultPrimaryConnectError: Error?
    private let lock = NSLock()
    private var primaryTransports: [ScriptedPrimaryTransport] = []
    private var covertTransports: [ScriptedCovertTransport] = []
    private var pendingPrimaryConnectErrors: [Error?]

    init(primaryConnectError: Error? = nil) {
        self.defaultPrimaryConnectError = primaryConnectError
        self.pendingPrimaryConnectErrors = []
    }

    init(primaryConnectErrors: [Error?]) {
        self.defaultPrimaryConnectError = primaryConnectErrors.last ?? nil
        self.pendingPrimaryConnectErrors = primaryConnectErrors
    }

    func makePrimary() -> any OpalFusion.Runtime.PrimaryTransporting {
        let connectError = lock.withLock { () -> Error? in
            if pendingPrimaryConnectErrors.isEmpty == false {
                return pendingPrimaryConnectErrors.removeFirst()
            }

            return defaultPrimaryConnectError
        }
        let transport = ScriptedPrimaryTransport(connectError: connectError)
        lock.withLock {
            primaryTransports.append(transport)
        }
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

private func makeTrustedTLSPrimaryTransport(
    port: UInt16
) throws -> OpalFusion.Runtime.LivePrimaryTransport {
    OpalFusion.Runtime.LivePrimaryTransport(
        host: LoopbackPrimaryTLSTestFixture.host,
        port: port,
        requiresTLS: true,
        tlsTrustAnchorCertificateDERs: try LoopbackPrimaryTLSTestFixture
            .trustAnchorCertificateDERs()
    )
}

private func makeRoundAwareScriptedWorkflow() -> OpalFusion.Execution.WorkflowContext {
    .init(
        buildPlayerCommit: { _ in
            PrimaryRuntimeTestFixtures.playerCommit
        },
        buildCovertComponentMessages: { round in
            let roundPublicKey = round.startRound?.roundPublicKey ?? []
            return [
                .component(
                    .init(
                        roundPublicKey: roundPublicKey,
                        signature: [0x30],
                        serializedComponent: [0x31]
                    )
                )
            ]
        },
        buildTransactionFinalizationProposal: { _ in
            PrimaryRuntimeTestFixtures.transactionProposal
        },
        buildCovertSignatureMessages: { round in
            let roundPublicKey = round.startRound?.roundPublicKey ?? []
            return [
                .transactionSignature(
                    .init(
                        roundPublicKey: roundPublicKey,
                        inputIndex: 0,
                        transactionSignature: [0x61]
                    )
                )
            ]
        },
        buildMyProofsList: { _ in
            PrimaryRuntimeTestFixtures.myProofsList
        },
        buildBlames: { _ in
            PrimaryRuntimeTestFixtures.blames
        }
    )
}

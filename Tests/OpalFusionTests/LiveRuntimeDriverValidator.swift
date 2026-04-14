// LiveRuntimeDriverValidator.swift

@testable import OpalFusion
import Foundation
import Network
import Testing

private final class MutableBoolBox: @unchecked Sendable {
    var value: Bool?
}

struct LiveRuntimeDriverValidator {
    @Test("Live runtime driver rejects invalid startup configuration before transport connect")
    func validateInvalidConfiguration() async throws {
        let primaryTransport = ScriptedPrimaryTransport()
        let covertTransport = ScriptedCovertTransport()
        let eventSink = RecordedHostEventSink()
        let participantReservationSource = DelayedParticipantReservationSource(
            participantInputs: [PrimaryRuntimeTestFixtures.participantInput]
        )
        let transactionAssembler = DelayedTransactionAssembler(
            finalizedTransaction: PrimaryRuntimeTestFixtures.finalizedTransaction
        )

        let driver = OpalFusion.Runtime.LiveRuntimeDriver(
            configuration: .init(
                coordinatorHost: "",
                coordinatorPort: PrimaryRuntimeTestFixtures.configuration.coordinatorPort,
                covertChannel: PrimaryRuntimeTestFixtures.configuration.covertChannel
            ),
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
            primaryTransport: primaryTransport,
            covertTransport: covertTransport
        )

        await driver.start()

        let snapshot = await driver.snapshot()
        #expect(snapshot.lastError == .invalidConfiguration)
        #expect(snapshot.lastErrorSummary == "Coordinator host must not be empty")
        #expect(snapshot.clientState.isConnected == false)
        #expect(await primaryTransport.recordedConnectCallCount() == 0)

        let events = await eventSink.snapshot()
        #expect(
            events == [
                .init(
                    roundIdentifier: nil,
                    event: .init(
                        kind: .failure,
                        phase: .connecting,
                        summary: "Coordinator host must not be empty"
                    )
                )
            ]
        )
    }

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

        let snapshot = await driver.snapshot()
        #expect(snapshot.lastError == .transportUnavailable)
        #expect(snapshot.lastErrorSummary?.hasPrefix("Primary connect failed:") == true)
        #expect(snapshot.clientState.isConnected == false)

        let events = await eventSink.snapshot()
        guard let event = events.last else {
            Issue.record("Expected a transport failure event")
            return
        }
        #expect(event.roundIdentifier == nil)
        #expect(event.event.kind == .failure)
        #expect(event.event.phase == .connecting)
        #expect(event.event.summary.hasPrefix("Primary connect failed:"))
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

        let pendingSnapshot = await driver.snapshot()
        #expect(pendingSnapshot.clientState.isConnected == false)
        #expect(pendingSnapshot.lastError == nil)
        #expect(pendingSnapshot.lastErrorSummary == nil)
        #expect(await primaryTransport.recordedConnectCallCount() == 1)
        #expect(await primaryTransport.recordedCloseCallCount() == 0)
        #expect(await primaryTransport.hasPendingConnect())

        await primaryTransport.releaseConnect()
        await startTask.value

        let connectedSnapshot = await driver.snapshot()
        #expect(connectedSnapshot.clientState.isConnected)
        #expect(connectedSnapshot.lastError == nil)
        #expect(connectedSnapshot.lastErrorSummary == nil)
        #expect(await primaryTransport.recordedWrittenPayloads().isEmpty == false)
        #expect(await primaryTransport.recordedCloseCallCount() == 0)
        #expect(await primaryTransport.hasPendingConnect() == false)

        await driver.stop()
    }

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

        let pendingSnapshot = await driver.snapshot()
        #expect(pendingSnapshot.clientState.isConnected == false)
        #expect(pendingSnapshot.lastError == nil)
        #expect(pendingSnapshot.lastErrorSummary == nil)
        #expect(await primaryTransport.recordedCloseCallCount() == 0)
        #expect(await primaryTransport.hasPendingConnect())

        await primaryTransport.failConnect(connectError)
        await startTask.value

        let failedSnapshot = await driver.snapshot()
        #expect(failedSnapshot.clientState.isConnected == false)
        #expect(failedSnapshot.lastError == .transportUnavailable)
        #expect(failedSnapshot.lastErrorSummary?.hasPrefix("Primary connect failed:") == true)
        #expect(await primaryTransport.recordedCloseCallCount() == 1)
        #expect(await primaryTransport.hasPendingConnect() == false)

        let events = await eventSink.snapshot()
        guard let event = events.last else {
            Issue.record("Expected a delayed connect failure event")
            return
        }
        #expect(event.roundIdentifier == nil)
        #expect(event.event.kind == .failure)
        #expect(event.event.phase == .connecting)
        #expect(event.event.summary.hasPrefix("Primary connect failed:"))
    }

    @Test("Live runtime driver preserves startup waiting errors when cancellation follows restart")
    func validateStartupWaitingCancellationPreservesUnderlyingErrorProjection() async throws {
        let underlyingError = NWError.posix(.ECONNRESET)
        let expectedSummary = "Primary connect failed: \(String(describing: underlyingError))"
        let eventSink = RecordedHostEventSink()
        let factory = ScriptedNetworkPrimaryConnectionFactory(
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

        let snapshot = await driver.snapshot()
        #expect(snapshot.lastError == .transportUnavailable)
        #expect(snapshot.lastErrorSummary == expectedSummary)
        #expect(snapshot.lastErrorSummary?.contains("primaryConnectionCancelled") == false)

        let events = await eventSink.snapshot()
        guard let event = events.last else {
            Issue.record("Expected a transport failure event")
            return
        }
        #expect(event.roundIdentifier == nil)
        #expect(event.event.kind == .failure)
        #expect(event.event.phase == .connecting)
        #expect(event.event.summary == expectedSummary)
    }

    @Test("Live runtime driver stops queued handshake effects after a primary write failure")
    func validatePrimaryWriteFailureDoesNotEmitQueuedHandshakeStatus() async throws {
        let primaryTransport = ScriptedPrimaryTransport(
            writeError: NSError(domain: "LiveRuntimeDriverValidator", code: 2)
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

        let snapshot = await driver.snapshot()
        #expect(snapshot.lastError == .transportUnavailable)
        #expect(snapshot.lastErrorSummary?.hasPrefix("Primary write failed:") == true)

        let events = await eventSink.snapshot()
        #expect(events.count == 1)
        #expect(events[0].roundIdentifier == nil)
        #expect(events[0].event.kind == .failure)
        #expect(events[0].event.summary.hasPrefix("Primary write failed:"))
        #expect(events.contains { $0.event.summary == "Primary channel connected; sending ClientHello" } == false)
    }

    @Test("Live runtime driver uses a TLS-required coordinator when configuration opts in")
    func validateTLSRequiredCoordinatorPath() async throws {
        let coordinator = try await LoopbackPrimaryCoordinator.start(requiresTLS: true)
        let covertTransport = ScriptedCovertTransport()
        let eventSink = RecordedHostEventSink()
        let observedRequiresTLS = MutableBoolBox()
        let driver = OpalFusion.Runtime.LiveRuntimeDriver(
            configuration: .init(
                coordinatorHost: LoopbackPrimaryTLSTestFixture.host,
                coordinatorPort: await coordinator.port,
                coordinatorRequiresTLS: true,
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
            primaryTransportFactory: { configuration in
                observedRequiresTLS.value = configuration.coordinatorRequiresTLS
                return OpalFusion.Runtime.LivePrimaryTransport(
                    host: configuration.coordinatorHost,
                    port: configuration.coordinatorPort,
                    requiresTLS: configuration.coordinatorRequiresTLS,
                    tlsTrustAnchorCertificateDERs: try! LoopbackPrimaryTLSTestFixture
                        .trustAnchorCertificateDERs()
                )
            },
            covertTransport: covertTransport
        )

        await driver.start()
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
                let snapshot = await driver.snapshot()
                if snapshot.clientState.isConnected {
                    return snapshot
                }
                try await Task.sleep(for: .milliseconds(10))
            }
        }

        #expect(snapshot.lastError == nil)
        #expect(snapshot.lastErrorSummary == nil)
        #expect(observedRequiresTLS.value == true)

        let events = await eventSink.snapshot()
        #expect(events.contains { $0.event.summary == "Primary channel connected; sending ClientHello" })

        await driver.stop()
        await coordinator.stop()
    }

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
            try await coordinator.nextClientMessage()
                == .clientHello(PrimaryRuntimeTestFixtures.clientHello)
        )

        try await coordinator.send(.serverHello(PrimaryRuntimeTestFixtures.serverHello))
        #expect(
            try await coordinator.nextClientMessage()
                == .joinPools(PrimaryRuntimeTestFixtures.joinPools)
        )

        await coordinator.closeConnection()

        let snapshot = try await withTimeout(.seconds(1)) {
            while true {
                let snapshot = await driver.snapshot()
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
            await coordinator.recordedClientMessages()
                == [
                    .clientHello(PrimaryRuntimeTestFixtures.clientHello),
                    .joinPools(PrimaryRuntimeTestFixtures.joinPools)
                ]
        )

        let events = await eventSink.snapshot()
        #expect(events.last?.event.summary == "Primary channel disconnected")

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
            try await coordinator.nextClientMessage()
                == .clientHello(PrimaryRuntimeTestFixtures.clientHello)
        )

        try await coordinator.send(.serverHello(PrimaryRuntimeTestFixtures.serverHello))
        #expect(
            try await coordinator.nextClientMessage()
                == .joinPools(PrimaryRuntimeTestFixtures.joinPools)
        )

        try await coordinator.send(
            .serverFailure(.init(message: rejectionSummary))
        )
        await coordinator.closeConnection()

        let snapshot = try await withTimeout(.seconds(1)) {
            while true {
                let snapshot = await driver.snapshot()
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

        let events = await eventSink.snapshot()
        #expect(events.last?.event.summary == rejectionSummary)

        await coordinator.stop()
    }

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
        let nowProvider = ScriptedNowProvider(unixSeconds: 995)
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
            nowProvider: { nowProvider.now() },
            clockTickInterval: .milliseconds(100),
            covertTransport: covertTransport
        )

        await driver.start()
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
                let snapshot = await driver.snapshot()
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
        #expect(await participantReservationSource.requestedRounds() == [PrimaryRuntimeTestFixtures.roundIdentifier])
        #expect(await transactionAssembler.requestedRounds() == [PrimaryRuntimeTestFixtures.roundIdentifier])

        let events = await eventSink.snapshot()
        #expect(events.contains { $0.event.summary == "Round completed successfully" })

        await driver.stop()
        await coordinator.stop()
    }

    @Test("Live runtime driver completes a production-workflow round over a loopback coordinator")
    func validateProductionWorkflowLoopbackRuntime() async throws {
        var scenario = try ProductionWorkflowTestFixtures.makeScenario()
        let coordinator = try await LoopbackPrimaryCoordinator.start()

        let covertTransport = ScriptedCovertTransport()
        let eventSink = RecordedHostEventSink()
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
        let nowProvider = ScriptedNowProvider(unixSeconds: 995)
        let configuration = OpalFusion.Client.Configuration(
            coordinatorHost: "127.0.0.1",
            coordinatorPort: await coordinator.port,
            covertChannel: PrimaryRuntimeTestFixtures.configuration.covertChannel
        )
        let driver = OpalFusion.Runtime.LiveRuntimeDriver(
            configuration: configuration,
            genesisHash: PrimaryRuntimeTestFixtures.clientHello.genesisHash,
            joinPools: PrimaryRuntimeTestFixtures.joinPools,
            participantReservationSource: participantReservationSource,
            transactionAssembler: transactionAssembler,
            hostEventSink: { roundIdentifier, event in
                await eventSink.record(
                    roundIdentifier: roundIdentifier,
                    event: event
                )
            },
            nowProvider: { nowProvider.now() },
            clockTickInterval: .milliseconds(100),
            covertTransport: covertTransport
        )

        await driver.start()
        #expect(
            try await coordinator.nextClientMessage()
                == .clientHello(PrimaryRuntimeTestFixtures.clientHello)
        )

        nowProvider.set(unixSeconds: 996)
        try await coordinator.send(.serverHello(scenario.serverHello))
        #expect(
            try await coordinator.nextClientMessage()
                == .joinPools(PrimaryRuntimeTestFixtures.joinPools)
        )

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
            await driver.stop()
            await coordinator.stop()
            return
        }

        let blindResponses = try await scenario.buildBlindSignatureResponses(for: playerCommit)
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
        let allRequests = try await withTimeout(.seconds(1)) {
            while true {
                let requests = await covertTransport.recordedRequests()
                if requests.count == playerCommit.initialCommitments.count + 1 {
                    return requests
                }
                try await Task.sleep(for: .milliseconds(10))
            }
        }

        guard let signatureRequest = allRequests.last else {
            Issue.record("Expected a covert transaction-signature request")
            await driver.stop()
            await coordinator.stop()
            return
        }
        let signatureMessage = try PrimaryRuntimeTestFixtures.extractCovertMessage(
            from: signatureRequest
        )
        guard case let .transactionSignature(signaturePayload) = signatureMessage else {
            Issue.record("Expected the final covert request to carry a transaction signature")
            await driver.stop()
            await coordinator.stop()
            return
        }
        let recordedSignatures = await transactionAssembler.recordedSignatures()
        #expect(recordedSignatures == [signaturePayload.transactionSignature])
        #expect(signaturePayload.roundPublicKey == scenario.startRound.roundPublicKey)
        #expect(signaturePayload.inputIndex == 0)

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
                let snapshot = await driver.snapshot()
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
        #expect(
            await participantReservationSource.requestedRounds()
                == [scenario.round.identifier!]
        )
        #expect(
            await transactionAssembler.requestedRounds()
                == [scenario.round.identifier!]
        )

        let events = await eventSink.snapshot()
        #expect(events.contains { $0.event.summary == "Round completed successfully" })

        await driver.stop()
        await coordinator.stop()
    }

    @Test("Signing transaction assembler signs the matching input instead of assuming input zero")
    func validateSigningAssemblerMatchesOutpoint() async throws {
        let scenario = try ProductionWorkflowTestFixtures.makeScenario()
        let assembler = SigningTransactionAssembler(
            participantInput: scenario.reservation.inputs[0],
            participantInputPrivateKey: scenario.participantInputPrivateKey
        )

        let unsignedTransaction = OpalFusion.Execution.BCHTransaction(
            version: 1,
            inputs: [
                .init(
                    previousTransactionHashLittleEndian: [UInt8](repeating: 0xEE, count: 32),
                    previousOutputIndex: 0,
                    unlockingScript: [],
                    sequence: .max
                ),
                .init(
                    previousTransactionHashLittleEndian: Array(
                        scenario.reservation.inputs[0].outpointTransactionHashBytes.reversed()
                    ),
                    previousOutputIndex: scenario.reservation.inputs[0].outpointIndex,
                    unlockingScript: [],
                    sequence: .max
                ),
            ],
            outputs: [
                .init(
                    amountSatoshis: scenario.reservation.outputs[0].amountSatoshis,
                    lockingScript: scenario.reservation.outputs[0].lockingScriptBytes
                )
            ],
            lockTime: 0
        )
        let proposal = OpalFusion.Host.TransactionFinalizationProposal(
            unsignedTransactionBytes: try unsignedTransaction.serialized()
        )

        let finalizedTransaction = try await assembler.finalizeTransaction(
            for: scenario.round.identifier!,
            proposal: proposal
        )
        let parsedTransaction = try OpalFusion.Execution.BCHTransaction.parse(
            finalizedTransaction.transactionBytes
        )

        #expect(parsedTransaction.inputs[0].unlockingScript.isEmpty)
        #expect(parsedTransaction.inputs[1].unlockingScript.isEmpty == false)
        #expect(parsedTransaction.inputs[1].unlockingScript[0] == 0x41)
    }

    @Test("Live runtime driver clears covert state on restart while keeping primary continuity")
    func validateRestartPath() async throws {
        let coordinator = try await LoopbackPrimaryCoordinator.start()

        let covertTransport = ScriptedCovertTransport()
        let nowProvider = ScriptedNowProvider(unixSeconds: 995)
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
            nowProvider: { nowProvider.now() },
            clockTickInterval: .milliseconds(100),
            covertTransport: covertTransport
        )

        await driver.start()
        _ = try await coordinator.nextClientMessage()

        nowProvider.set(unixSeconds: 996)
        try await coordinator.send(.serverHello(PrimaryRuntimeTestFixtures.serverHello))
        _ = try await coordinator.nextClientMessage()

        nowProvider.set(unixSeconds: 1_000)
        try await coordinator.send(.fusionBegin(PrimaryRuntimeTestFixtures.fusionBegin))
        try await withTimeout(.seconds(1)) {
            while await covertTransport.recordedPreparationPlans().isEmpty {
                try await Task.sleep(for: .milliseconds(10))
            }
        }

        nowProvider.set(unixSeconds: 1_030)
        try await coordinator.send(.startRound(PrimaryRuntimeTestFixtures.startRound))
        _ = try await coordinator.nextClientMessage()

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

        let resetCountBeforeRestart = await covertTransport.recordedResetCount()

        nowProvider.set(unixSeconds: 1_060)
        try await coordinator.send(.restartRound(.init()))

        let snapshot = try await withTimeout(.seconds(1)) {
            while true {
                let snapshot = await driver.snapshot()
                if snapshot.clientState.isConnected && snapshot.clientState.round == nil {
                    return snapshot
                }
                try await Task.sleep(for: .milliseconds(10))
            }
        }

        #expect(snapshot.clientState.isConnected)
        #expect(snapshot.clientState.round == nil)
        #expect(await covertTransport.recordedResetCount() > resetCountBeforeRestart)

        await driver.stop()
        await coordinator.stop()
    }

    @Test("Live runtime driver ignores stale covert completions after stop")
    func validateStaleCovertCompletionIsIgnoredAfterStop() async throws {
        let primaryTransport = ScriptedPrimaryTransport()
        let covertTransport = BlockingCovertTransport(blocksPerform: true)
        let eventSink = RecordedHostEventSink()
        let nowProvider = ScriptedNowProvider(unixSeconds: 995)
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
            nowProvider: { nowProvider.now() },
            clockTickInterval: .milliseconds(100),
            primaryTransport: primaryTransport,
            covertTransport: covertTransport
        )

        await driver.start()
        try await withTimeout(.seconds(1)) {
            while await primaryTransport.recordedWrittenPayloads().isEmpty {
                try await Task.sleep(for: .milliseconds(10))
            }
        }

        nowProvider.set(unixSeconds: 996)
        await primaryTransport.yieldInboundBytes(
            try PrimaryRuntimeTestFixtures.encodeServerFrame(
                .serverHello(PrimaryRuntimeTestFixtures.serverHello)
            )
        )
        try await withTimeout(.seconds(1)) {
            while await primaryTransport.recordedWrittenPayloads().count < 2 {
                try await Task.sleep(for: .milliseconds(10))
            }
        }

        nowProvider.set(unixSeconds: 1_000)
        await primaryTransport.yieldInboundBytes(
            try PrimaryRuntimeTestFixtures.encodeServerFrame(
                .fusionBegin(PrimaryRuntimeTestFixtures.fusionBegin)
            )
        )
        try await withTimeout(.seconds(1)) {
            while await covertTransport.recordedPreparationPlans().isEmpty {
                try await Task.sleep(for: .milliseconds(10))
            }
        }

        nowProvider.set(unixSeconds: 1_030)
        await primaryTransport.yieldInboundBytes(
            try PrimaryRuntimeTestFixtures.encodeServerFrame(
                .startRound(PrimaryRuntimeTestFixtures.startRound)
            )
        )
        try await withTimeout(.seconds(1)) {
            while await primaryTransport.recordedWrittenPayloads().count < 3 {
                try await Task.sleep(for: .milliseconds(10))
            }
        }

        nowProvider.set(unixSeconds: 1_032)
        await primaryTransport.yieldInboundBytes(
            try PrimaryRuntimeTestFixtures.encodeServerFrame(
                .blindSignatureResponses(PrimaryRuntimeTestFixtures.blindSignatureResponses)
            )
        )

        nowProvider.set(unixSeconds: 1_034)
        await primaryTransport.yieldInboundBytes(
            try PrimaryRuntimeTestFixtures.encodeServerFrame(
                .allCommitments(PrimaryRuntimeTestFixtures.allCommitments)
            )
        )
        nowProvider.set(unixSeconds: 1_035)
        try await withTimeout(.seconds(1)) {
            while await covertTransport.recordedRequests().count < 1 {
                try await Task.sleep(for: .milliseconds(10))
            }
        }

        let snapshotBeforeStop = await driver.snapshot()
        #expect(snapshotBeforeStop.clientState.round?.phase == .awaitingCommitments)
        #expect(snapshotBeforeStop.lastError == nil)

        await driver.stop()

        let stoppedSnapshot = try await withTimeout(.seconds(1)) {
            while true {
                let snapshot = await driver.snapshot()
                if snapshot.lastError == .transportUnavailable &&
                    snapshot.lastErrorSummary == "Primary channel disconnected" &&
                    snapshot.clientState.isConnected == false {
                    return snapshot
                }
                try await Task.sleep(for: .milliseconds(10))
            }
        }
        #expect(stoppedSnapshot.lastError == .transportUnavailable)
        #expect(stoppedSnapshot.lastErrorSummary == "Primary channel disconnected")
        #expect(stoppedSnapshot.clientState.isConnected == false)
        #expect(await covertTransport.recordedResetCount() > 0)

        let eventsAfterStop = try await withTimeout(.seconds(1)) {
            while true {
                let events = await eventSink.snapshot()
                if events.last?.event.summary == "Primary channel disconnected" {
                    return events
                }
                try await Task.sleep(for: .milliseconds(10))
            }
        }
        #expect(eventsAfterStop.last?.event.summary == "Primary channel disconnected")

        await covertTransport.releasePerform(
            response: try PrimaryRuntimeTestFixtures.encodeCovertResponsePayload(
                PrimaryRuntimeTestFixtures.acknowledgement
            )
        )
        try await Task.sleep(for: .milliseconds(50))

        let finalSnapshot = await driver.snapshot()
        #expect(finalSnapshot == stoppedSnapshot)

        let eventsAfterRelease = await eventSink.snapshot()
        #expect(eventsAfterRelease == eventsAfterStop)
    }

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
        let nowProvider = ScriptedNowProvider(unixSeconds: 995)
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
            nowProvider: { nowProvider.now() },
            clockTickInterval: .milliseconds(100),
            primaryTransport: primaryTransport,
            covertTransport: covertTransport
        )

        await driver.start()
        try await withTimeout(.seconds(1)) {
            while await primaryTransport.recordedWrittenPayloads().isEmpty {
                try await Task.sleep(for: .milliseconds(10))
            }
        }

        nowProvider.set(unixSeconds: 996)
        await primaryTransport.yieldInboundBytes(
            try PrimaryRuntimeTestFixtures.encodeServerFrame(
                .serverHello(PrimaryRuntimeTestFixtures.serverHello)
            )
        )
        try await withTimeout(.seconds(1)) {
            while await primaryTransport.recordedWrittenPayloads().count < 2 {
                try await Task.sleep(for: .milliseconds(10))
            }
        }

        nowProvider.set(unixSeconds: 1_000)
        await primaryTransport.yieldInboundBytes(
            try PrimaryRuntimeTestFixtures.encodeServerFrame(
                .fusionBegin(PrimaryRuntimeTestFixtures.fusionBegin)
            )
        )
        try await withTimeout(.seconds(1)) {
            while await covertTransport.recordedPreparationPlans().isEmpty {
                try await Task.sleep(for: .milliseconds(10))
            }
        }

        nowProvider.set(unixSeconds: 1_030)
        await primaryTransport.yieldInboundBytes(
            try PrimaryRuntimeTestFixtures.encodeServerFrame(
                .startRound(PrimaryRuntimeTestFixtures.startRound)
            )
        )
        try await Task.sleep(for: .milliseconds(50))

        #expect(await primaryTransport.recordedWrittenPayloads().count == 2)

        await driver.stop()
        let stoppedSnapshot = await driver.snapshot()
        #expect(stoppedSnapshot.lastError == .transportUnavailable)
        #expect(stoppedSnapshot.lastErrorSummary == "Primary channel disconnected")
        #expect(stoppedSnapshot.clientState.isConnected == false)

        await participantReservationSource.releaseReservation()
        try await Task.sleep(for: .milliseconds(100))

        let finalSnapshot = await driver.snapshot()
        #expect(finalSnapshot == stoppedSnapshot)
        #expect(await primaryTransport.recordedWrittenPayloads().count == 2)

        let events = await eventSink.snapshot()
        #expect(events.last?.event.summary == "Primary channel disconnected")
        #expect(events.contains { $0.event.summary == "Submitting player commitments and blind requests" } == false)
    }

    @Test("Live runtime driver ignores stale transaction finalization after stop")
    func validateStaleTransactionFinalizationIsIgnoredAfterStop() async throws {
        let primaryTransport = ScriptedPrimaryTransport()
        let covertTransport = ScriptedCovertTransport()
        let eventSink = RecordedHostEventSink()
        let nowProvider = ScriptedNowProvider(unixSeconds: 995)
        let transactionAssembler = BlockingTransactionAssembler(
            finalizedTransaction: PrimaryRuntimeTestFixtures.finalizedTransaction
        )
        let driver = OpalFusion.Runtime.LiveRuntimeDriver(
            configuration: PrimaryRuntimeTestFixtures.configuration,
            genesisHash: PrimaryRuntimeTestFixtures.clientHello.genesisHash,
            joinPools: PrimaryRuntimeTestFixtures.joinPools,
            workflow: PrimaryRuntimeTestFixtures.workflow,
            participantReservationSource: DelayedParticipantReservationSource(
                participantInputs: [PrimaryRuntimeTestFixtures.participantInput],
                participantOutputs: [PrimaryRuntimeTestFixtures.participantOutput]
            ),
            transactionAssembler: transactionAssembler,
            hostEventSink: { roundIdentifier, event in
                await eventSink.record(
                    roundIdentifier: roundIdentifier,
                    event: event
                )
            },
            nowProvider: { nowProvider.now() },
            clockTickInterval: .milliseconds(100),
            primaryTransport: primaryTransport,
            covertTransport: covertTransport
        )

        await driver.start()
        try await withTimeout(.seconds(1)) {
            while await primaryTransport.recordedWrittenPayloads().isEmpty {
                try await Task.sleep(for: .milliseconds(10))
            }
        }

        nowProvider.set(unixSeconds: 996)
        await primaryTransport.yieldInboundBytes(
            try PrimaryRuntimeTestFixtures.encodeServerFrame(
                .serverHello(PrimaryRuntimeTestFixtures.serverHello)
            )
        )
        try await withTimeout(.seconds(1)) {
            while await primaryTransport.recordedWrittenPayloads().count < 2 {
                try await Task.sleep(for: .milliseconds(10))
            }
        }

        nowProvider.set(unixSeconds: 1_000)
        await primaryTransport.yieldInboundBytes(
            try PrimaryRuntimeTestFixtures.encodeServerFrame(
                .fusionBegin(PrimaryRuntimeTestFixtures.fusionBegin)
            )
        )
        try await withTimeout(.seconds(1)) {
            while await covertTransport.recordedPreparationPlans().isEmpty {
                try await Task.sleep(for: .milliseconds(10))
            }
        }

        nowProvider.set(unixSeconds: 1_030)
        await primaryTransport.yieldInboundBytes(
            try PrimaryRuntimeTestFixtures.encodeServerFrame(
                .startRound(PrimaryRuntimeTestFixtures.startRound)
            )
        )
        try await withTimeout(.seconds(1)) {
            while await primaryTransport.recordedWrittenPayloads().count < 3 {
                try await Task.sleep(for: .milliseconds(10))
            }
        }

        nowProvider.set(unixSeconds: 1_032)
        await primaryTransport.yieldInboundBytes(
            try PrimaryRuntimeTestFixtures.encodeServerFrame(
                .blindSignatureResponses(PrimaryRuntimeTestFixtures.blindSignatureResponses)
            )
        )

        nowProvider.set(unixSeconds: 1_034)
        await primaryTransport.yieldInboundBytes(
            try PrimaryRuntimeTestFixtures.encodeServerFrame(
                .allCommitments(PrimaryRuntimeTestFixtures.allCommitments)
            )
        )

        await covertTransport.enqueueResponse(
            try PrimaryRuntimeTestFixtures.encodeCovertResponsePayload(
                PrimaryRuntimeTestFixtures.acknowledgement
            )
        )
        nowProvider.set(unixSeconds: 1_035)
        try await Task.sleep(for: .milliseconds(150))
        #expect(await covertTransport.recordedRequests().count == 1)

        nowProvider.set(unixSeconds: 1_040)
        await primaryTransport.yieldInboundBytes(
            try PrimaryRuntimeTestFixtures.encodeServerFrame(
                .shareCovertComponents(PrimaryRuntimeTestFixtures.sharedComponents)
            )
        )
        try await Task.sleep(for: .milliseconds(50))

        #expect(await covertTransport.recordedRequests().count == 1)

        await driver.stop()
        let stoppedSnapshot = await driver.snapshot()
        #expect(stoppedSnapshot.lastError == .transportUnavailable)
        #expect(stoppedSnapshot.lastErrorSummary == "Primary channel disconnected")
        #expect(stoppedSnapshot.clientState.isConnected == false)

        await transactionAssembler.releaseTransaction()
        try await Task.sleep(for: .milliseconds(100))

        let finalSnapshot = await driver.snapshot()
        #expect(finalSnapshot == stoppedSnapshot)
        #expect(await covertTransport.recordedRequests().count == 1)

        let events = await eventSink.snapshot()
        #expect(events.last?.event.summary == "Primary channel disconnected")
        #expect(events.contains { $0.event.summary == "Transaction finalized; waiting for signature window" } == false)
        #expect(events.contains { $0.event.summary == "Submitting covert transaction signatures" } == false)
    }
}

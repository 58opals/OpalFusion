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
            participantReservationSource: HostParticipantReservationSourceAdapter(
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

        await session.stop()
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
            participantReservationSource: HostParticipantReservationSourceAdapter(
                participantInputs: [PrimaryRuntimeTestFixtures.participantInput]
            ),
            transactionAssembler: HostTransactionAssemblerAdapter(
                finalizedTransaction: PrimaryRuntimeTestFixtures.finalizedTransaction
            ),
            stateObserver: stateObserver,
            primaryTransportFactory: { await transportFactories.makePrimary() },
            covertTransportFactory: { await transportFactories.makeCovert() }
        )

        await session.start()

        let snapshot = await session.snapshot()
        #expect(snapshot.lastError == .transportUnavailable)
        #expect(snapshot.lastErrorSummary == "Primary connection failed")
        #expect(snapshot.state.isConnected == false)
        #expect(await transportFactories.primaryCount() == 1)

        let observedSnapshots = await stateObserver.snapshot()
        #expect(observedSnapshots.contains(snapshot))
        #expect(observedSnapshots.contains {
            $0.lastError == .transportUnavailable &&
                $0.lastErrorSummary == "Primary connection failed"
        })

        await session.stop()
    }

    @Test("Public client session preserves pre-round coordinator rejection messages")
    func validatePreRoundServerFailureMessageProjection() async throws {
        let rejectionMessage = "This server is on a different chain, please switch servers"
        let stateObserver = RecordedClientStateObserver()
        let transportFactories = SessionTransportFactoryRecorder()
        let session = OpalFusion.Client.Session(
            configuration: PrimaryRuntimeTestFixtures.configuration,
            genesisHash: PrimaryRuntimeTestFixtures.clientHello.genesisHash,
            joinPools: PrimaryRuntimeTestFixtures.joinPools,
            participantReservationSource: HostParticipantReservationSourceAdapter(
                participantInputs: [PrimaryRuntimeTestFixtures.participantInput]
            ),
            transactionAssembler: HostTransactionAssemblerAdapter(
                finalizedTransaction: PrimaryRuntimeTestFixtures.finalizedTransaction
            ),
            stateObserver: stateObserver,
            primaryTransportFactory: { await transportFactories.makePrimary() },
            covertTransportFactory: { await transportFactories.makeCovert() }
        )

        await session.start()

        let transport = try await Self.waitForPrimaryTransport(
            transportFactories,
            at: 0
        )
        try await Self.waitForWrittenPayloadCount(transport, count: 1)
        await transport.yieldInboundBytes(
            try PrimaryRuntimeTestFixtures.encodeServerFrame(
                .serverFailure(.init(message: rejectionMessage))
            )
        )

        let snapshot = try await Self.waitForSessionSnapshot(session) {
            $0.lastError == .coordinatorRejected &&
                $0.lastErrorSummary == rejectionMessage &&
                $0.state.isConnected == false
        }
        #expect(snapshot.state.round == nil)

        let observedSnapshots = await stateObserver.snapshot()
        #expect(observedSnapshots.contains {
            $0.lastError == .coordinatorRejected &&
                $0.lastErrorSummary == rejectionMessage
        })

        await session.stop()
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
            participantReservationSource: HostParticipantReservationSourceAdapter(
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
        #expect(snapshot.lastErrorSummary == "Primary connection failed")
        #expect(snapshot.state.isConnected == false)

        let observedSnapshots = await stateObserver.snapshot()
        #expect(observedSnapshots.contains(snapshot))
        #expect(observedSnapshots.contains {
            $0.lastError == .transportUnavailable &&
                $0.lastErrorSummary == "Primary connection failed"
        })

        await session.stop()
        await coordinator.stop()
    }

    @Test("Public client session can exchange primary handshake messages over TLS")
    func validateTLSHandshakeProjection() async throws {
        let coordinator = try await LoopbackPrimaryCoordinator.start(requiresTLS: true)
        let port = await coordinator.port
        let stateObserver = RecordedClientStateObserver()
        let primaryTransport = try await ClientSessionValidationHarness.makeTrustedTLSPrimaryTransport(port: port)
        let session = OpalFusion.Client.Session(
            configuration: .init(
                coordinatorHost: LoopbackPrimaryTLSTestFixture.host,
                coordinatorPort: port,
                coordinatorRequiresTLS: true,
                covertChannel: PrimaryRuntimeTestFixtures.configuration.covertChannel
            ),
            genesisHash: PrimaryRuntimeTestFixtures.clientHello.genesisHash,
            joinPools: PrimaryRuntimeTestFixtures.joinPools,
            participantReservationSource: HostParticipantReservationSourceAdapter(
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

        let snapshot = try await LiveRuntimeTestHarness.withTimeout(.seconds(1)) {
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
            participantReservationSource: HostParticipantReservationSourceAdapter(
                participantInputs: [PrimaryRuntimeTestFixtures.participantInput]
            ),
            transactionAssembler: HostTransactionAssemblerAdapter(
                finalizedTransaction: PrimaryRuntimeTestFixtures.finalizedTransaction
            ),
            stateObserver: stateObserver,
            primaryTransportFactory: { await transportFactories.makePrimary() },
            covertTransportFactory: { await transportFactories.makeCovert() }
        )

        await session.start()
        await session.start()

        let runningSnapshot = try await LiveRuntimeTestHarness.withTimeout(.seconds(1)) {
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
        #expect(await transportFactories.primaryCount() == 1)

        await session.stop()
        await session.stop()

        let stoppedSnapshot = try await LiveRuntimeTestHarness.withTimeout(.seconds(1)) {
            while true {
                let snapshot = await session.snapshot()
                if snapshot.state.isConnected == false {
                    return snapshot
                }
                try await Task.sleep(for: .milliseconds(10))
            }
        }
        #expect(stoppedSnapshot.lastError == nil)
        #expect(stoppedSnapshot.lastErrorSummary == nil)
        #expect(stoppedSnapshot.state.isConnected == false)
        #expect(stoppedSnapshot.state.round == nil)

        let observedSnapshotsAfterStop = await stateObserver.snapshot()
        #expect(observedSnapshotsAfterStop.last == stoppedSnapshot)

        await session.start()
        let restartedSnapshot = try await LiveRuntimeTestHarness.withTimeout(.seconds(1)) {
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
        #expect(await transportFactories.primaryCount() == 2)

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

        await session.stop()
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
            participantReservationSource: HostParticipantReservationSourceAdapter(
                participantInputs: [PrimaryRuntimeTestFixtures.participantInput]
            ),
            transactionAssembler: HostTransactionAssemblerAdapter(
                finalizedTransaction: PrimaryRuntimeTestFixtures.finalizedTransaction
            ),
            stateObserver: stateObserver,
            primaryTransportFactory: { await transportFactories.makePrimary() },
            covertTransportFactory: { await transportFactories.makeCovert() }
        )

        await session.start()

        let failedSnapshot = await session.snapshot()
        #expect(failedSnapshot.lastError == .transportUnavailable)
        #expect(failedSnapshot.lastErrorSummary == "Primary connection failed")

        await session.stop()
        await session.start()

        let restartedSnapshot = try await LiveRuntimeTestHarness.withTimeout(.seconds(1)) {
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
        #expect(await transportFactories.primaryCount() == 2)

        let observedSnapshots = await stateObserver.snapshot()
        #expect(observedSnapshots.contains {
            $0.lastError == .transportUnavailable &&
                $0.lastErrorSummary == "Primary connection failed"
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

        await session.stop()
    }

    @Test("Public client session can retry start after a terminal start failure")
    func validateStartRetryAfterConnectFailure() async throws {
        let stateObserver = RecordedClientStateObserver()
        let transportFactories = SessionTransportFactoryRecorder(
            primaryConnectErrors: [
                NSError(domain: "ClientSessionValidator", code: 8),
                nil
            ]
        )
        let session = OpalFusion.Client.Session(
            configuration: PrimaryRuntimeTestFixtures.configuration,
            genesisHash: PrimaryRuntimeTestFixtures.clientHello.genesisHash,
            joinPools: PrimaryRuntimeTestFixtures.joinPools,
            participantReservationSource: HostParticipantReservationSourceAdapter(
                participantInputs: [PrimaryRuntimeTestFixtures.participantInput]
            ),
            transactionAssembler: HostTransactionAssemblerAdapter(
                finalizedTransaction: PrimaryRuntimeTestFixtures.finalizedTransaction
            ),
            stateObserver: stateObserver,
            primaryTransportFactory: { await transportFactories.makePrimary() },
            covertTransportFactory: { await transportFactories.makeCovert() }
        )

        await session.start()

        let failedSnapshot = await session.snapshot()
        #expect(failedSnapshot.lastError == .transportUnavailable)
        #expect(failedSnapshot.lastErrorSummary == "Primary connection failed")
        #expect(failedSnapshot.state.isConnected == false)

        await session.start()

        let restartedSnapshot = try await LiveRuntimeTestHarness.withTimeout(.seconds(1)) {
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
        #expect(await transportFactories.primaryCount() == 2)

        let observedSnapshots = await stateObserver.snapshot()
        #expect(observedSnapshots.contains(failedSnapshot))
        #expect(observedSnapshots.contains(restartedSnapshot))

        await session.stop()
    }

    @Test("Public client session can retry start after an async primary failure")
    func validateStartRetryAfterAsyncPrimaryFailure() async throws {
        let stateObserver = RecordedClientStateObserver()
        let transportFactories = SessionTransportFactoryRecorder()
        let session = OpalFusion.Client.Session(
            configuration: PrimaryRuntimeTestFixtures.configuration,
            genesisHash: PrimaryRuntimeTestFixtures.clientHello.genesisHash,
            joinPools: PrimaryRuntimeTestFixtures.joinPools,
            participantReservationSource: HostParticipantReservationSourceAdapter(
                participantInputs: [PrimaryRuntimeTestFixtures.participantInput]
            ),
            transactionAssembler: HostTransactionAssemblerAdapter(
                finalizedTransaction: PrimaryRuntimeTestFixtures.finalizedTransaction
            ),
            stateObserver: stateObserver,
            primaryTransportFactory: { await transportFactories.makePrimary() },
            covertTransportFactory: { await transportFactories.makeCovert() }
        )

        await session.start()
        let runningSnapshot = try await LiveRuntimeTestHarness.withTimeout(.seconds(1)) {
            while true {
                let snapshot = await session.snapshot()
                if snapshot.state.isConnected {
                    return snapshot
                }
                try await Task.sleep(for: .milliseconds(10))
            }
        }
        #expect(runningSnapshot.lastError == nil)

        guard let firstTransport = await transportFactories.primaryTransport(at: 0) else {
            Issue.record("Expected first primary transport")
            return
        }
        await firstTransport.finishInbound(
            throwing: NSError(domain: "ClientSessionValidator", code: 9)
        )

        let failedSnapshot = try await LiveRuntimeTestHarness.withTimeout(.seconds(1)) {
            while true {
                let snapshot = await session.snapshot()
                if snapshot.lastError == .transportUnavailable {
                    return snapshot
                }
                try await Task.sleep(for: .milliseconds(10))
            }
        }
        #expect(failedSnapshot.lastErrorSummary == "Primary read failed")
        #expect(failedSnapshot.state.isConnected == false)

        await session.start()

        let restartedSnapshot = try await LiveRuntimeTestHarness.withTimeout(.seconds(1)) {
            while true {
                let snapshot = await session.snapshot()
                if snapshot.state.isConnected && snapshot.lastError == nil {
                    return snapshot
                }
                try await Task.sleep(for: .milliseconds(10))
            }
        }

        #expect(restartedSnapshot.lastErrorSummary == nil)
        #expect(await transportFactories.primaryCount() == 2)

        await session.stop()
    }

    @Test("Public client session reconnect policy retries connect failure and reports retry diagnostics")
    func validateReconnectPolicyRetriesConnectFailure() async throws {
        let stateObserver = RecordedClientStateObserver()
        let transportFactories = SessionTransportFactoryRecorder(
            primaryConnectErrors: [
                NSError(domain: "ClientSessionValidator", code: 10),
                nil
            ]
        )
        let session = OpalFusion.Client.Session(
            configuration: PrimaryRuntimeTestFixtures.configuration,
            genesisHash: PrimaryRuntimeTestFixtures.clientHello.genesisHash,
            joinPools: PrimaryRuntimeTestFixtures.joinPools,
            participantReservationSource: HostParticipantReservationSourceAdapter(
                participantInputs: [PrimaryRuntimeTestFixtures.participantInput]
            ),
            transactionAssembler: HostTransactionAssemblerAdapter(
                finalizedTransaction: PrimaryRuntimeTestFixtures.finalizedTransaction
            ),
            stateObserver: stateObserver,
            reconnectPolicy: Self.fastReconnectPolicy,
            primaryTransportFactory: { await transportFactories.makePrimary() },
            covertTransportFactory: { await transportFactories.makeCovert() }
        )

        await session.start()

        let retrySnapshot = try await Self.waitForObservedSnapshot(
            stateObserver
        ) {
            $0.lastError == .transportUnavailable &&
                $0.lastErrorSummary == "Primary connection failed"
        }
        #expect(retrySnapshot.lastError == .transportUnavailable)

        let connectedSnapshot = try await Self.waitForSessionSnapshot(session) {
            $0.state.isConnected && $0.lastError == nil
        }
        #expect(connectedSnapshot.state.isConnected)
        #expect(await transportFactories.primaryCount() == 2)

        await session.stop()
    }

    @Test("Public client session reconnect policy allows immediate finite retry")
    func validateReconnectPolicyAllowsImmediateFiniteRetry() async throws {
        let stateObserver = RecordedClientStateObserver()
        let transportFactories = SessionTransportFactoryRecorder(
            primaryConnectErrors: [
                NSError(domain: "ClientSessionValidator", code: 15),
                nil
            ]
        )
        let session = OpalFusion.Client.Session(
            configuration: PrimaryRuntimeTestFixtures.configuration,
            genesisHash: PrimaryRuntimeTestFixtures.clientHello.genesisHash,
            joinPools: PrimaryRuntimeTestFixtures.joinPools,
            participantReservationSource: HostParticipantReservationSourceAdapter(
                participantInputs: [PrimaryRuntimeTestFixtures.participantInput]
            ),
            transactionAssembler: HostTransactionAssemblerAdapter(
                finalizedTransaction: PrimaryRuntimeTestFixtures.finalizedTransaction
            ),
            stateObserver: stateObserver,
            reconnectPolicy: .init(
                initialDelay: .zero,
                maximumDelay: .zero,
                multiplier: 1,
                maximumAttempts: 2
            ),
            primaryTransportFactory: { await transportFactories.makePrimary() },
            covertTransportFactory: { await transportFactories.makeCovert() }
        )

        await session.start()

        _ = try await Self.waitForPrimaryTransport(transportFactories, at: 1)

        let connectedSnapshot = try await Self.waitForSessionSnapshot(session) {
            $0.state.isConnected && $0.lastError == nil
        }
        #expect(connectedSnapshot.state.isConnected)
        #expect(await transportFactories.primaryCount() == 2)

        await session.stop()
    }

    @Test("Public client session resets reconnect attempts after a successful reconnect")
    func validateReconnectAttemptResetsAfterSuccessfulReconnect() async throws {
        let stateObserver = RecordedClientStateObserver()
        let transportFactories = SessionTransportFactoryRecorder(
            primaryConnectErrors: [
                NSError(domain: "ClientSessionValidator", code: 14),
                nil,
                nil,
            ]
        )
        let session = OpalFusion.Client.Session(
            configuration: PrimaryRuntimeTestFixtures.configuration,
            genesisHash: PrimaryRuntimeTestFixtures.clientHello.genesisHash,
            joinPools: PrimaryRuntimeTestFixtures.joinPools,
            participantReservationSource: HostParticipantReservationSourceAdapter(
                participantInputs: [PrimaryRuntimeTestFixtures.participantInput]
            ),
            transactionAssembler: HostTransactionAssemblerAdapter(
                finalizedTransaction: PrimaryRuntimeTestFixtures.finalizedTransaction
            ),
            stateObserver: stateObserver,
            reconnectPolicy: .init(
                initialDelay: .milliseconds(10),
                maximumDelay: .milliseconds(40),
                multiplier: 2,
                maximumAttempts: 3
            ),
            primaryTransportFactory: { await transportFactories.makePrimary() },
            covertTransportFactory: { await transportFactories.makeCovert() }
        )

        await session.start()
        _ = try await Self.waitForPrimaryTransport(transportFactories, at: 1)

        let reconnectedTransport = try await Self.waitForPrimaryTransport(
            transportFactories,
            at: 1
        )
        _ = try await Self.waitForObservedSnapshot(stateObserver) {
            $0.state.isConnected && $0.lastError == nil
        }
        try await Self.waitForWrittenPayloadCount(reconnectedTransport, count: 1)
        await reconnectedTransport.finishInbound()

        _ = try await Self.waitForObservedSnapshot(stateObserver) {
            $0.lastErrorSummary == "Primary channel disconnected"
        }

        await session.stop()
    }

    @Test("Public client session reconnect policy clamps overflowing delay growth")
    func validateReconnectPolicyClampsOverflowingDelayGrowth() {
        let policy = OpalFusion.Client.ReconnectPolicy(
            initialDelay: .milliseconds(10),
            maximumDelay: .milliseconds(30),
            multiplier: Double.greatestFiniteMagnitude,
            maximumAttempts: nil
        )

        #expect(policy.delay(forRetryAttempt: 1) == .milliseconds(10))
        #expect(policy.delay(forRetryAttempt: 2) == .milliseconds(30))
        #expect(policy.delay(forRetryAttempt: 3) == .milliseconds(30))
    }

    @Test("Public client session reconnect policy clamps huge configured delays")
    func validateReconnectPolicyClampsHugeConfiguredDelays() {
        let policy = OpalFusion.Client.ReconnectPolicy(
            initialDelay: .seconds(Int64.max),
            maximumDelay: .seconds(Int64.max),
            multiplier: 1,
            maximumAttempts: 1
        )

        #expect(policy.delay(forRetryAttempt: 1) == .milliseconds(Int.max))
    }

    @Test("Public client session reconnect policy disables unbounded zero-delay retry loops")
    func validateReconnectPolicyDisablesUnboundedImmediateRetryLoop() {
        let policy = OpalFusion.Client.ReconnectPolicy(
            initialDelay: .zero,
            maximumDelay: .zero,
            multiplier: 1,
            maximumAttempts: nil
        )

        #expect(policy.delay(forRetryAttempt: 1) == nil)
    }

    @Test("Public client session reconnect policy detects negative sub-millisecond delays")
    func validateReconnectPolicyDetectsNegativeSubmillisecondDelays() {
        #expect(Duration.nanoseconds(-1).opalFusionMillisecondsRoundedUp == -1)
        #expect(Duration.microseconds(-1).opalFusionMillisecondsRoundedUp == -1)
        #expect(Duration.milliseconds(-1).opalFusionMillisecondsRoundedUp == -1)
        #expect(Duration.nanoseconds(1).opalFusionMillisecondsRoundedUp == 1)
    }

    @Test("Public client session reconnect policy rounds huge attosecond delays without trapping")
    func validateReconnectPolicyRoundsHugeAttosecondDelays() {
        let delay = Duration(
            secondsComponent: 0,
            attosecondsComponent: Int64.max
        )
        let policy = OpalFusion.Client.ReconnectPolicy(
            initialDelay: delay,
            maximumDelay: delay,
            multiplier: 1,
            maximumAttempts: 1
        )

        #expect(policy.delay(forRetryAttempt: 1) == .milliseconds(9_224))
    }

    @Test("Public client session retries peer EOF after ClientHello with handshake diagnostics")
    func validateReconnectAfterClientHelloEOFDiagnostics() async throws {
        let stateObserver = RecordedClientStateObserver()
        let transportFactories = SessionTransportFactoryRecorder()
        let session = OpalFusion.Client.Session(
            configuration: PrimaryRuntimeTestFixtures.configuration,
            genesisHash: PrimaryRuntimeTestFixtures.clientHello.genesisHash,
            joinPools: PrimaryRuntimeTestFixtures.joinPools,
            participantReservationSource: HostParticipantReservationSourceAdapter(
                participantInputs: [PrimaryRuntimeTestFixtures.participantInput]
            ),
            transactionAssembler: HostTransactionAssemblerAdapter(
                finalizedTransaction: PrimaryRuntimeTestFixtures.finalizedTransaction
            ),
            stateObserver: stateObserver,
            reconnectPolicy: Self.fastReconnectPolicy,
            primaryTransportFactory: { await transportFactories.makePrimary() },
            covertTransportFactory: { await transportFactories.makeCovert() }
        )

        await session.start()
        let firstTransport = try await Self.waitForPrimaryTransport(
            transportFactories,
            at: 0
        )
        try await Self.waitForWrittenPayloadCount(firstTransport, count: 1)
        await firstTransport.finishInbound()

        let retrySnapshot = try await Self.waitForObservedSnapshot(
            stateObserver
        ) {
            $0.lastErrorSummary == "Primary channel disconnected"
        }

        #expect(retrySnapshot.lastErrorSummary == "Primary channel disconnected")

        _ = try await Self.waitForPrimaryTransport(transportFactories, at: 1)
        #expect(await transportFactories.primaryCount() == 2)

        await session.stop()
    }

    @Test("Public client session retries peer EOF after ServerHello with handshake diagnostics")
    func validateReconnectAfterServerHelloEOFDiagnostics() async throws {
        let stateObserver = RecordedClientStateObserver()
        let transportFactories = SessionTransportFactoryRecorder()
        let session = OpalFusion.Client.Session(
            configuration: PrimaryRuntimeTestFixtures.configuration,
            genesisHash: PrimaryRuntimeTestFixtures.clientHello.genesisHash,
            joinPools: PrimaryRuntimeTestFixtures.joinPools,
            participantReservationSource: HostParticipantReservationSourceAdapter(
                participantInputs: [PrimaryRuntimeTestFixtures.participantInput]
            ),
            transactionAssembler: HostTransactionAssemblerAdapter(
                finalizedTransaction: PrimaryRuntimeTestFixtures.finalizedTransaction
            ),
            stateObserver: stateObserver,
            reconnectPolicy: Self.fastReconnectPolicy,
            primaryTransportFactory: { await transportFactories.makePrimary() },
            covertTransportFactory: { await transportFactories.makeCovert() }
        )

        await session.start()
        let firstTransport = try await Self.waitForPrimaryTransport(
            transportFactories,
            at: 0
        )
        try await Self.waitForWrittenPayloadCount(firstTransport, count: 1)
        await firstTransport.yieldInboundBytes(
            try PrimaryRuntimeTestFixtures.encodeServerFrame(
                .serverHello(PrimaryRuntimeTestFixtures.serverHello)
            )
        )
        try await Self.waitForWrittenPayloadCount(firstTransport, count: 2)
        await firstTransport.finishInbound()

        let retrySnapshot = try await Self.waitForObservedSnapshot(
            stateObserver
        ) {
            $0.lastErrorSummary == "Primary channel disconnected"
        }

        #expect(retrySnapshot.lastErrorSummary == "Primary channel disconnected")

        _ = try await Self.waitForPrimaryTransport(transportFactories, at: 1)
        #expect(await transportFactories.primaryCount() == 2)

        await session.stop()
    }

    @Test("Public client session does not retry transport loss after FusionBegin creates a round")
    func validateReconnectPolicyDoesNotRetryAfterRoundExists() async throws {
        let stateObserver = RecordedClientStateObserver()
        let transportFactories = SessionTransportFactoryRecorder()
        let covertTransport = ScriptedCovertTransport()
        let nowProvider = ScriptedInstantClock(unixSeconds: 995)
        let session = OpalFusion.Client.Session(
            configuration: PrimaryRuntimeTestFixtures.configuration,
            genesisHash: PrimaryRuntimeTestFixtures.clientHello.genesisHash,
            joinPools: PrimaryRuntimeTestFixtures.joinPools,
            participantReservationSource: HostParticipantReservationSourceAdapter(
                participantInputs: [PrimaryRuntimeTestFixtures.participantInput]
            ),
            transactionAssembler: HostTransactionAssemblerAdapter(
                finalizedTransaction: PrimaryRuntimeTestFixtures.finalizedTransaction
            ),
            stateObserver: stateObserver,
            reconnectPolicy: Self.fastReconnectPolicy,
            workflow: PrimaryRuntimeTestFixtures.workflow,
            nowProvider: { await nowProvider.now() },
            primaryTransportFactory: { await transportFactories.makePrimary() },
            covertTransportFactory: { covertTransport }
        )

        await session.start()
        let firstTransport = try await Self.waitForPrimaryTransport(
            transportFactories,
            at: 0
        )
        try await Self.waitForWrittenPayloadCount(firstTransport, count: 1)

        await nowProvider.update(unixSeconds: 996)
        await firstTransport.yieldInboundBytes(
            try PrimaryRuntimeTestFixtures.encodeServerFrame(
                .serverHello(PrimaryRuntimeTestFixtures.serverHello)
            )
        )
        try await Self.waitForWrittenPayloadCount(firstTransport, count: 2)

        await nowProvider.update(unixSeconds: 1_000)
        await firstTransport.yieldInboundBytes(
            try PrimaryRuntimeTestFixtures.encodeServerFrame(
                .fusionBegin(PrimaryRuntimeTestFixtures.fusionBegin)
            )
        )
        try await LiveRuntimeTestHarness.withTimeout(.seconds(1)) {
            while await covertTransport.recordedPreparationPlans().isEmpty {
                try await Task.sleep(for: .milliseconds(10))
            }
        }

        await firstTransport.finishInbound()
        _ = try await Self.waitForSessionSnapshot(session) {
            $0.lastError == .transportUnavailable &&
                $0.state.isConnected == false
        }

        try await Task.sleep(for: .milliseconds(50))
        #expect(await transportFactories.primaryCount() == 1)

        await session.stop()
    }

    @Test("Public client session keeps invalid FusionBegin diagnostics pre-round")
    func validateInvalidFusionBeginDiagnosticsStayPreRound() async throws {
        let transportFactories = SessionTransportFactoryRecorder()
        let nowProvider = ScriptedInstantClock(unixSeconds: 995)
        let invalidFusionBegin = OpalFusion.ProtocolModel.FusionBegin(
            tier: PrimaryRuntimeTestFixtures.fusionBegin.tier,
            covertDomain: PrimaryRuntimeTestFixtures.fusionBegin.covertDomain,
            covertPort: PrimaryRuntimeTestFixtures.fusionBegin.covertPort,
            covertSsl: PrimaryRuntimeTestFixtures.fusionBegin.covertSsl,
            serverTimeUnixSeconds: 1_500
        )
        let session = OpalFusion.Client.Session(
            configuration: PrimaryRuntimeTestFixtures.configuration,
            genesisHash: PrimaryRuntimeTestFixtures.clientHello.genesisHash,
            joinPools: PrimaryRuntimeTestFixtures.joinPools,
            participantReservationSource: HostParticipantReservationSourceAdapter(
                participantInputs: [PrimaryRuntimeTestFixtures.participantInput]
            ),
            transactionAssembler: HostTransactionAssemblerAdapter(
                finalizedTransaction: PrimaryRuntimeTestFixtures.finalizedTransaction
            ),
            reconnectPolicy: Self.fastReconnectPolicy,
            workflow: PrimaryRuntimeTestFixtures.workflow,
            nowProvider: { await nowProvider.now() },
            primaryTransportFactory: { await transportFactories.makePrimary() },
            covertTransportFactory: { ScriptedCovertTransport() }
        )

        await session.start()
        let transport = try await Self.waitForPrimaryTransport(
            transportFactories,
            at: 0
        )
        try await Self.waitForWrittenPayloadCount(transport, count: 1)

        await nowProvider.update(unixSeconds: 996)
        await transport.yieldInboundBytes(
            try PrimaryRuntimeTestFixtures.encodeServerFrame(
                .serverHello(PrimaryRuntimeTestFixtures.serverHello)
            )
        )
        try await Self.waitForWrittenPayloadCount(transport, count: 2)

        await transport.yieldInboundBytes(
            try PrimaryRuntimeTestFixtures.encodeServerFrame(
                .fusionBegin(invalidFusionBegin)
            )
        )

        let snapshot = try await Self.waitForSessionSnapshot(session) {
            $0.lastError == .protocolIncompatible
        }

        #expect(snapshot.state.round == nil)
        #expect(await transportFactories.primaryCount() == 1)

        await session.stop()
    }

    @Test("Public client session keeps invalid ServerHello diagnostics at server hello stage")
    func validateInvalidServerHelloDiagnosticsStayAtServerHelloStage() async throws {
        let transportFactories = SessionTransportFactoryRecorder()
        let invalidServerHello = OpalFusion.ProtocolModel.ServerHello(
            tiers: PrimaryRuntimeTestFixtures.serverHello.tiers,
            numberOfComponents: 0,
            componentFeeRateSatoshisPerKb: PrimaryRuntimeTestFixtures.serverHello
                .componentFeeRateSatoshisPerKb,
            minimumExcessFeeSatoshis: PrimaryRuntimeTestFixtures.serverHello
                .minimumExcessFeeSatoshis,
            maximumExcessFeeSatoshis: PrimaryRuntimeTestFixtures.serverHello
                .maximumExcessFeeSatoshis,
            donationAddress: PrimaryRuntimeTestFixtures.serverHello.donationAddress
        )
        let session = OpalFusion.Client.Session(
            configuration: PrimaryRuntimeTestFixtures.configuration,
            genesisHash: PrimaryRuntimeTestFixtures.clientHello.genesisHash,
            joinPools: PrimaryRuntimeTestFixtures.joinPools,
            participantReservationSource: HostParticipantReservationSourceAdapter(
                participantInputs: [PrimaryRuntimeTestFixtures.participantInput]
            ),
            transactionAssembler: HostTransactionAssemblerAdapter(
                finalizedTransaction: PrimaryRuntimeTestFixtures.finalizedTransaction
            ),
            workflow: PrimaryRuntimeTestFixtures.workflow,
            primaryTransportFactory: { await transportFactories.makePrimary() },
            covertTransportFactory: { ScriptedCovertTransport() }
        )

        await session.start()
        let transport = try await Self.waitForPrimaryTransport(
            transportFactories,
            at: 0
        )
        try await Self.waitForWrittenPayloadCount(transport, count: 1)
        await transport.yieldInboundBytes(
            try PrimaryRuntimeTestFixtures.encodeServerFrame(
                .serverHello(invalidServerHello)
            )
        )

        let snapshot = try await Self.waitForSessionSnapshot(session) {
            $0.lastError == .protocolIncompatible
        }

        #expect(snapshot.state.round == nil)
        #expect(await transportFactories.primaryCount() == 1)

        await session.stop()
    }

    @Test("Public client session exposes repeated TierStatusUpdate coordinator snapshots")
    func validateCoordinatorStatusAdvancesForRepeatedTierStatusUpdate() async throws {
        let stateObserver = RecordedClientStateObserver()
        let transportFactories = SessionTransportFactoryRecorder()
        let nowProvider = ScriptedInstantClock(unixSeconds: 995)
        let session = OpalFusion.Client.Session(
            configuration: PrimaryRuntimeTestFixtures.configuration,
            genesisHash: PrimaryRuntimeTestFixtures.clientHello.genesisHash,
            joinPools: PrimaryRuntimeTestFixtures.joinPools,
            participantReservationSource: HostParticipantReservationSourceAdapter(
                participantInputs: [PrimaryRuntimeTestFixtures.participantInput]
            ),
            transactionAssembler: HostTransactionAssemblerAdapter(
                finalizedTransaction: PrimaryRuntimeTestFixtures.finalizedTransaction
            ),
            stateObserver: stateObserver,
            workflow: PrimaryRuntimeTestFixtures.workflow,
            nowProvider: { await nowProvider.now() },
            primaryTransportFactory: { await transportFactories.makePrimary() },
            covertTransportFactory: { ScriptedCovertTransport() }
        )
        let tierStatusMessage = OpalFusion.ProtocolModel.ServerMessage.tierStatusUpdate(
            PrimaryRuntimeTestFixtures.tierStatusUpdate
        )
        let tierStatusFrame = try PrimaryRuntimeTestFixtures.encodeServerFrame(
            tierStatusMessage
        )
        let tierStatusPayloadByteCount = try PrimaryRuntimeTestFixtures.encodeServerPayload(
            tierStatusMessage
        ).count
        let expectedQueueStatus = OpalFusion.Client.Session.Snapshot.CoordinatorStatus
            .TierQueue(
                tierSatoshis: 10_000,
                players: 3,
                minPlayers: 2,
                maxPlayers: 8,
                timeRemaining: 17
            )

        await session.start()
        let transport = try await Self.waitForPrimaryTransport(
            transportFactories,
            at: 0
        )
        try await Self.waitForWrittenPayloadCount(transport, count: 1)

        await nowProvider.update(unixSeconds: 996)
        await transport.yieldInboundBytes(
            try PrimaryRuntimeTestFixtures.encodeServerFrame(
                .serverHello(PrimaryRuntimeTestFixtures.serverHello)
            )
        )
        try await Self.waitForWrittenPayloadCount(transport, count: 2)

        await transport.yieldInboundBytes(tierStatusFrame)
        let firstStatusSnapshot = try await Self.waitForObservedSnapshot(stateObserver) {
            $0.coordinatorStatus.updateSequence == 2
        }

        await transport.yieldInboundBytes(tierStatusFrame)
        let repeatedStatusSnapshot = try await Self.waitForObservedSnapshot(stateObserver) {
            $0.coordinatorStatus.updateSequence == 3
        }

        #expect(firstStatusSnapshot.coordinatorStatus.latestInboundMessageKind == "TierStatusUpdate")
        #expect(
            firstStatusSnapshot.coordinatorStatus.latestInboundPayloadByteCount
                == tierStatusPayloadByteCount
        )
        #expect(firstStatusSnapshot.coordinatorStatus.queueStatus == expectedQueueStatus)
        #expect(repeatedStatusSnapshot.coordinatorStatus.latestInboundMessageKind == "TierStatusUpdate")
        #expect(
            repeatedStatusSnapshot.coordinatorStatus.latestInboundPayloadByteCount
                == tierStatusPayloadByteCount
        )
        #expect(repeatedStatusSnapshot.coordinatorStatus.queueStatus == expectedQueueStatus)

        await session.stop()
    }

    @Test("Public client session does not retry non-transport terminal failures")
    func validateReconnectPolicyDoesNotRetryNonTransportFailures() async throws {
        let invalidConfigurationObserver = RecordedClientStateObserver()
        let invalidConfigurationFactories = SessionTransportFactoryRecorder()
        let invalidConfigurationSession = OpalFusion.Client.Session(
            configuration: .init(
                coordinatorHost: "",
                coordinatorPort: PrimaryRuntimeTestFixtures.configuration.coordinatorPort,
                covertChannel: PrimaryRuntimeTestFixtures.configuration.covertChannel
            ),
            genesisHash: PrimaryRuntimeTestFixtures.clientHello.genesisHash,
            joinPools: PrimaryRuntimeTestFixtures.joinPools,
            participantReservationSource: HostParticipantReservationSourceAdapter(
                participantInputs: [PrimaryRuntimeTestFixtures.participantInput]
            ),
            transactionAssembler: HostTransactionAssemblerAdapter(
                finalizedTransaction: PrimaryRuntimeTestFixtures.finalizedTransaction
            ),
            stateObserver: invalidConfigurationObserver,
            reconnectPolicy: Self.fastReconnectPolicy,
            primaryTransportFactory: { await invalidConfigurationFactories.makePrimary() }
        )

        await invalidConfigurationSession.start()
        #expect((await invalidConfigurationSession.snapshot()).lastError == .invalidConfiguration)
        try await Task.sleep(for: .milliseconds(50))
        #expect(await invalidConfigurationFactories.primaryCount() == 0)
        await invalidConfigurationSession.stop()

        let protocolFactories = SessionTransportFactoryRecorder()
        let protocolSession = OpalFusion.Client.Session(
            configuration: PrimaryRuntimeTestFixtures.configuration,
            genesisHash: PrimaryRuntimeTestFixtures.clientHello.genesisHash,
            joinPools: PrimaryRuntimeTestFixtures.joinPools,
            participantReservationSource: HostParticipantReservationSourceAdapter(
                participantInputs: [PrimaryRuntimeTestFixtures.participantInput]
            ),
            transactionAssembler: HostTransactionAssemblerAdapter(
                finalizedTransaction: PrimaryRuntimeTestFixtures.finalizedTransaction
            ),
            reconnectPolicy: Self.fastReconnectPolicy,
            primaryTransportFactory: { await protocolFactories.makePrimary() }
        )
        await protocolSession.start()
        let protocolTransport = try await Self.waitForPrimaryTransport(
            protocolFactories,
            at: 0
        )
        await protocolTransport.yieldInboundBytes(
            try PrimaryRuntimeTestFixtures.encodeServerFrame(
                .tierStatusUpdate(PrimaryRuntimeTestFixtures.tierStatusUpdate)
            )
        )
        _ = try await Self.waitForSessionSnapshot(protocolSession) {
            $0.lastError == .protocolIncompatible
        }
        try await Task.sleep(for: .milliseconds(50))
        #expect(await protocolFactories.primaryCount() == 1)
        await protocolSession.stop()

        let coordinatorFactories = SessionTransportFactoryRecorder()
        let coordinatorSession = OpalFusion.Client.Session(
            configuration: PrimaryRuntimeTestFixtures.configuration,
            genesisHash: PrimaryRuntimeTestFixtures.clientHello.genesisHash,
            joinPools: PrimaryRuntimeTestFixtures.joinPools,
            participantReservationSource: HostParticipantReservationSourceAdapter(
                participantInputs: [PrimaryRuntimeTestFixtures.participantInput]
            ),
            transactionAssembler: HostTransactionAssemblerAdapter(
                finalizedTransaction: PrimaryRuntimeTestFixtures.finalizedTransaction
            ),
            reconnectPolicy: Self.fastReconnectPolicy,
            primaryTransportFactory: { await coordinatorFactories.makePrimary() }
        )
        await coordinatorSession.start()
        let coordinatorTransport = try await Self.waitForPrimaryTransport(
            coordinatorFactories,
            at: 0
        )
        await coordinatorTransport.yieldInboundBytes(
            try PrimaryRuntimeTestFixtures.encodeServerFrame(
                .serverFailure(.init(message: "Rejected"))
            )
        )
        _ = try await Self.waitForSessionSnapshot(coordinatorSession) {
            $0.lastError == .coordinatorRejected
        }
        try await Task.sleep(for: .milliseconds(50))
        #expect(await coordinatorFactories.primaryCount() == 1)
        await coordinatorSession.stop()

        let hostFactories = SessionTransportFactoryRecorder()
        let hostNowProvider = ScriptedInstantClock(unixSeconds: 995)
        let hostCovertTransport = ScriptedCovertTransport()
        let hostReservationSource = BlockingParticipantReservationSource(
            reservation: .init(
                inputs: [PrimaryRuntimeTestFixtures.participantInput],
                outputs: [PrimaryRuntimeTestFixtures.participantOutput]
            )
        )
        let hostSession = OpalFusion.Client.Session(
            configuration: PrimaryRuntimeTestFixtures.configuration,
            genesisHash: PrimaryRuntimeTestFixtures.clientHello.genesisHash,
            joinPools: PrimaryRuntimeTestFixtures.joinPools,
            participantReservationSource: hostReservationSource,
            transactionAssembler: HostTransactionAssemblerAdapter(
                finalizedTransaction: PrimaryRuntimeTestFixtures.finalizedTransaction
            ),
            reconnectPolicy: Self.fastReconnectPolicy,
            workflow: PrimaryRuntimeTestFixtures.workflow,
            nowProvider: { await hostNowProvider.now() },
            primaryTransportFactory: { await hostFactories.makePrimary() },
            covertTransportFactory: { hostCovertTransport }
        )
        await hostSession.start()
        let hostTransport = try await Self.waitForPrimaryTransport(
            hostFactories,
            at: 0
        )
        try await Self.advanceToStartRound(
            hostTransport,
            nowProvider: hostNowProvider,
            covertTransport: hostCovertTransport
        )
        try await LiveRuntimeTestHarness.withTimeout(.seconds(1)) {
            while await hostReservationSource.requestedRounds().isEmpty {
                try await Task.sleep(for: .milliseconds(10))
            }
        }
        await hostReservationSource.failReservation(
            NSError(domain: "ClientSessionValidator", code: 11)
        )
        _ = try await Self.waitForSessionSnapshot(hostSession) {
            $0.lastError == .hostRejected
        }
        try await Task.sleep(for: .milliseconds(50))
        #expect(await hostFactories.primaryCount() == 1)
        await hostSession.stop()
    }

    @Test("Public client session stop cancels a pending reconnect")
    func validateStopCancelsPendingReconnect() async throws {
        let stateObserver = RecordedClientStateObserver()
        let transportFactories = SessionTransportFactoryRecorder(
            primaryConnectError: NSError(domain: "ClientSessionValidator", code: 12)
        )
        let session = OpalFusion.Client.Session(
            configuration: PrimaryRuntimeTestFixtures.configuration,
            genesisHash: PrimaryRuntimeTestFixtures.clientHello.genesisHash,
            joinPools: PrimaryRuntimeTestFixtures.joinPools,
            participantReservationSource: HostParticipantReservationSourceAdapter(
                participantInputs: [PrimaryRuntimeTestFixtures.participantInput]
            ),
            transactionAssembler: HostTransactionAssemblerAdapter(
                finalizedTransaction: PrimaryRuntimeTestFixtures.finalizedTransaction
            ),
            stateObserver: stateObserver,
            reconnectPolicy: .init(
                initialDelay: .seconds(2),
                maximumDelay: .seconds(2),
                multiplier: 1,
                maximumAttempts: nil
            ),
            primaryTransportFactory: { await transportFactories.makePrimary() }
        )

        await session.start()
        _ = try await Self.waitForObservedSnapshot(stateObserver) {
            $0.lastError == .transportUnavailable
        }
        await session.stop()
        try await Task.sleep(for: .milliseconds(2_200))

        let stoppedSnapshot = await session.snapshot()
        #expect(stoppedSnapshot.lastError == nil)
        #expect(stoppedSnapshot.lastErrorSummary == nil)
        #expect(stoppedSnapshot.state.isConnected == false)
        #expect(stoppedSnapshot.state.round == nil)
        #expect(await transportFactories.primaryCount() == 1)
    }

    @Test("Public client session stop clears pending reconnect handshake diagnostics")
    func validateStopClearsPendingReconnectHandshakeDiagnostics() async throws {
        let stateObserver = RecordedClientStateObserver()
        let transportFactories = SessionTransportFactoryRecorder()
        let session = OpalFusion.Client.Session(
            configuration: PrimaryRuntimeTestFixtures.configuration,
            genesisHash: PrimaryRuntimeTestFixtures.clientHello.genesisHash,
            joinPools: PrimaryRuntimeTestFixtures.joinPools,
            participantReservationSource: HostParticipantReservationSourceAdapter(
                participantInputs: [PrimaryRuntimeTestFixtures.participantInput]
            ),
            transactionAssembler: HostTransactionAssemblerAdapter(
                finalizedTransaction: PrimaryRuntimeTestFixtures.finalizedTransaction
            ),
            stateObserver: stateObserver,
            reconnectPolicy: .init(
                initialDelay: .seconds(2),
                maximumDelay: .seconds(2),
                multiplier: 1,
                maximumAttempts: nil
            ),
            primaryTransportFactory: { await transportFactories.makePrimary() }
        )

        await session.start()
        let transport = try await Self.waitForPrimaryTransport(
            transportFactories,
            at: 0
        )
        try await Self.waitForWrittenPayloadCount(transport, count: 1)
        await transport.finishInbound()

        _ = try await Self.waitForObservedSnapshot(stateObserver) {
            $0.lastError == .transportUnavailable
        }

        await session.stop()
        try await Task.sleep(for: .milliseconds(2_200))

        let stoppedSnapshot = await session.snapshot()
        #expect(stoppedSnapshot.lastError == nil)
        #expect(await transportFactories.primaryCount() == 1)
    }

    @Test("Public client session stop preserves pending reconnect coordinator status")
    func validateStopPreservesPendingReconnectCoordinatorStatus() async throws {
        let stateObserver = RecordedClientStateObserver()
        let transportFactories = SessionTransportFactoryRecorder()
        let session = OpalFusion.Client.Session(
            configuration: PrimaryRuntimeTestFixtures.configuration,
            genesisHash: PrimaryRuntimeTestFixtures.clientHello.genesisHash,
            joinPools: PrimaryRuntimeTestFixtures.joinPools,
            participantReservationSource: HostParticipantReservationSourceAdapter(
                participantInputs: [PrimaryRuntimeTestFixtures.participantInput]
            ),
            transactionAssembler: HostTransactionAssemblerAdapter(
                finalizedTransaction: PrimaryRuntimeTestFixtures.finalizedTransaction
            ),
            stateObserver: stateObserver,
            reconnectPolicy: .init(
                initialDelay: .seconds(2),
                maximumDelay: .seconds(2),
                multiplier: 1,
                maximumAttempts: nil
            ),
            primaryTransportFactory: { await transportFactories.makePrimary() }
        )

        await session.start()
        let transport = try await Self.waitForPrimaryTransport(
            transportFactories,
            at: 0
        )
        try await Self.waitForWrittenPayloadCount(transport, count: 1)
        await transport.yieldInboundBytes(
            try PrimaryRuntimeTestFixtures.encodeServerFrame(
                .serverHello(PrimaryRuntimeTestFixtures.serverHello)
            )
        )
        try await Self.waitForWrittenPayloadCount(transport, count: 2)
        await transport.yieldInboundBytes(
            try PrimaryRuntimeTestFixtures.encodeServerFrame(
                .tierStatusUpdate(PrimaryRuntimeTestFixtures.tierStatusUpdate)
            )
        )
        await transport.finishInbound()

        let retrySnapshot = try await Self.waitForObservedSnapshot(stateObserver) {
            $0.lastError == .transportUnavailable &&
                $0.coordinatorStatus.latestInboundMessageKind == "TierStatusUpdate"
        }

        await session.stop()
        try await Task.sleep(for: .milliseconds(2_200))

        let stoppedSnapshot = await session.snapshot()
        #expect(stoppedSnapshot.coordinatorStatus == retrySnapshot.coordinatorStatus)
        #expect(await transportFactories.primaryCount() == 1)
    }

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
            nowProvider: { await nowProvider.now() },
            clockTickInterval: .milliseconds(100),
            covertTransportFactory: { covertTransport }
        )

        await session.start()
        #expect(
            try await coordinator.nextClientMessage()
                == .clientHello(PrimaryRuntimeTestFixtures.clientHello)
        )

        await nowProvider.update(unixSeconds: 996)
        try await coordinator.send(.serverHello(PrimaryRuntimeTestFixtures.serverHello))
        #expect(
            try await coordinator.nextClientMessage()
                == .joinPools(PrimaryRuntimeTestFixtures.joinPools)
        )

        await nowProvider.update(unixSeconds: 1_000)
        try await coordinator.send(.fusionBegin(PrimaryRuntimeTestFixtures.fusionBegin))
        try await LiveRuntimeTestHarness.withTimeout(.seconds(1)) {
            while await covertTransport.recordedPreparationPlans().isEmpty {
                try await Task.sleep(for: .milliseconds(10))
            }
        }

        await nowProvider.update(unixSeconds: 1_030)
        try await coordinator.send(.startRound(PrimaryRuntimeTestFixtures.startRound))
        #expect(
            try await coordinator.nextClientMessage()
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
            while await covertTransport.recordedRequests().count < 1 {
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
            while await covertTransport.recordedRequests().count < 2 {
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

        let observedEvents = await eventObserver.snapshot()
        #expect(observedEvents.contains { $0.event.summary == "Round completed successfully" })

        let observedSnapshots = try await LiveRuntimeTestHarness.withTimeout(.seconds(1)) {
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
            nowProvider: { await nowProvider.now() },
            clockTickInterval: .milliseconds(100),
            covertTransportFactory: { covertTransport }
        )

        await session.start()
        _ = try await coordinator.nextClientMessage()

        await nowProvider.update(unixSeconds: 996)
        try await coordinator.send(.serverHello(scenario.serverHello))
        _ = try await coordinator.nextClientMessage()

        await nowProvider.update(unixSeconds: 1_000)
        try await coordinator.send(.fusionBegin(scenario.fusionBegin))
        try await LiveRuntimeTestHarness.withTimeout(.seconds(1)) {
            while await covertTransport.recordedPreparationPlans().isEmpty {
                try await Task.sleep(for: .milliseconds(10))
            }
        }

        await nowProvider.update(unixSeconds: 1_030)
        try await coordinator.send(.startRound(scenario.startRound))
        let playerCommitMessage = try await coordinator.nextClientMessage()
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
            while await transactionAssembler.recordedProposals().isEmpty {
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
            while await covertTransport.recordedRequests().count < playerCommit.initialCommitments.count + 1 {
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
            await participantReservationSource.requestedRounds()
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
            participantReservationSource: participantReservationSource,
            transactionAssembler: transactionAssembler,
            eventObserver: eventObserver,
            stateObserver: stateObserver,
            workflow: ClientSessionValidationHarness.makeRoundAwareScriptedWorkflow(),
            nowProvider: { await nowProvider.now() },
            clockTickInterval: .milliseconds(100),
            covertTransportFactory: { recordingCovertTransport }
        )

        await session.start()
        #expect(
            try await coordinator.nextClientMessage()
                == .clientHello(PrimaryRuntimeTestFixtures.clientHello)
        )

        await nowProvider.update(unixSeconds: 996)
        try await coordinator.send(.serverHello(PrimaryRuntimeTestFixtures.serverHello))
        #expect(
            try await coordinator.nextClientMessage()
                == .joinPools(PrimaryRuntimeTestFixtures.joinPools)
        )

        await nowProvider.update(unixSeconds: 1_000)
        try await coordinator.send(.fusionBegin(PrimaryRuntimeTestFixtures.fusionBegin))
        try await LiveRuntimeTestHarness.withTimeout(.seconds(1)) {
            while await recordingCovertTransport.recordedPreparationPlans().isEmpty {
                try await Task.sleep(for: .milliseconds(10))
            }
        }

        await nowProvider.update(unixSeconds: 1_030)
        try await coordinator.send(.startRound(firstStartRound))
        _ = try await coordinator.nextClientMessage()

        await nowProvider.update(unixSeconds: 1_032)
        try await coordinator.send(
            .blindSignatureResponses(PrimaryRuntimeTestFixtures.blindSignatureResponses)
        )
        await nowProvider.update(unixSeconds: 1_034)
        try await coordinator.send(.allCommitments(PrimaryRuntimeTestFixtures.allCommitments))

        await scriptedCovertTransport.enqueueResponse(
            try PrimaryRuntimeTestFixtures.encodeCovertResponsePayload(
                PrimaryRuntimeTestFixtures.acknowledgement
            )
        )
        await nowProvider.update(unixSeconds: 1_035)
        try await LiveRuntimeTestHarness.withTimeout(.seconds(1)) {
            while await recordingCovertTransport.recordedRequests().count < 1 {
                try await Task.sleep(for: .milliseconds(10))
            }
        }

        await nowProvider.update(unixSeconds: 1_040)
        try await coordinator.send(.shareCovertComponents(PrimaryRuntimeTestFixtures.sharedComponents))

        await scriptedCovertTransport.enqueueResponse(
            try PrimaryRuntimeTestFixtures.encodeCovertResponsePayload(
                PrimaryRuntimeTestFixtures.acknowledgement
            )
        )
        await nowProvider.update(unixSeconds: 1_050)
        try await LiveRuntimeTestHarness.withTimeout(.seconds(1)) {
            while await recordingCovertTransport.recordedRequests().count < 2 {
                try await Task.sleep(for: .milliseconds(10))
            }
        }

        await nowProvider.update(unixSeconds: 1_055)
        try await coordinator.send(.fusionResult(PrimaryRuntimeTestFixtures.failureResult))
        #expect(
            try await coordinator.nextClientMessage()
                == .myProofsList(PrimaryRuntimeTestFixtures.myProofsList)
        )

        await nowProvider.update(unixSeconds: 1_056)
        try await coordinator.send(.theirProofsList(PrimaryRuntimeTestFixtures.theirProofsList))
        #expect(
            try await coordinator.nextClientMessage()
                == .blames(PrimaryRuntimeTestFixtures.blames)
        )

        await nowProvider.update(unixSeconds: 1_060)
        try await coordinator.send(.restartRound(.init()))

        try await LiveRuntimeTestHarness.withTimeout(.seconds(1)) {
            while true {
                let snapshot = await session.snapshot()
                if snapshot.state.isConnected && snapshot.state.round == nil {
                    return
                }
                try await Task.sleep(for: .milliseconds(10))
            }
        }

        await nowProvider.update(unixSeconds: 1_060)
        try await coordinator.send(.fusionBegin(secondFusionBegin))
        try await LiveRuntimeTestHarness.withTimeout(.seconds(1)) {
            while await recordingCovertTransport.recordedPreparationPlans().count < 2 {
                try await Task.sleep(for: .milliseconds(10))
            }
        }

        await nowProvider.update(unixSeconds: 1_090)
        try await coordinator.send(.startRound(secondStartRound))
        _ = try await coordinator.nextClientMessage()

        await nowProvider.update(unixSeconds: 1_092)
        try await coordinator.send(
            .blindSignatureResponses(PrimaryRuntimeTestFixtures.blindSignatureResponses)
        )
        await nowProvider.update(unixSeconds: 1_094)
        try await coordinator.send(.allCommitments(PrimaryRuntimeTestFixtures.allCommitments))

        await scriptedCovertTransport.enqueueResponse(
            try PrimaryRuntimeTestFixtures.encodeCovertResponsePayload(
                PrimaryRuntimeTestFixtures.acknowledgement
            )
        )
        await nowProvider.update(unixSeconds: 1_095)
        try await LiveRuntimeTestHarness.withTimeout(.seconds(1)) {
            while await recordingCovertTransport.recordedRequests().count < 3 {
                try await Task.sleep(for: .milliseconds(10))
            }
        }

        await nowProvider.update(unixSeconds: 1_100)
        try await coordinator.send(.shareCovertComponents(PrimaryRuntimeTestFixtures.sharedComponents))

        await scriptedCovertTransport.enqueueResponse(
            try PrimaryRuntimeTestFixtures.encodeCovertResponsePayload(
                PrimaryRuntimeTestFixtures.acknowledgement
            )
        )
        await nowProvider.update(unixSeconds: 1_110)
        try await LiveRuntimeTestHarness.withTimeout(.seconds(1)) {
            while await recordingCovertTransport.recordedRequests().count < 4 {
                try await Task.sleep(for: .milliseconds(10))
            }
        }

        await nowProvider.update(unixSeconds: 1_115)
        try await coordinator.send(.fusionResult(PrimaryRuntimeTestFixtures.successResult))

        let snapshot = try await LiveRuntimeTestHarness.withTimeout(.seconds(1)) {
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

        let firstRoundIdentifier = SessionTranscriptHarness.makeRoundIdentifier(
            from: firstStartRound.roundPublicKey
        )
        let secondRoundIdentifier = SessionTranscriptHarness.makeRoundIdentifier(
            from: secondStartRound.roundPublicKey
        )
        let transcript = SessionTranscript(
            clientMessageKinds: await coordinator.recordedClientMessages().map(
                SessionTranscriptHarness.clientKind
            ),
            serverMessageKinds: await coordinator.recordedServerMessages().map(
                SessionTranscriptHarness.serverKind
            ),
            covertMessageKinds: await recordingCovertTransport.recordedRequestMessages().map(
                SessionTranscriptHarness.covertKind
            ),
            roundEvents: await eventObserver.timedSnapshot(),
            stateSnapshots: await stateObserver.timedSnapshot(),
            reservationRequests: await participantReservationSource.timedRequestRecords(),
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
            SessionTranscriptHarness.hasSubsequence(
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
            outpointTransactionHashBytes: scenario.reservation.inputs[0].outpointTransactionHashBytes,
            outpointIndex: scenario.reservation.inputs[0].outpointIndex,
            amountSatoshis: scenario.reservation.inputs[0].amountSatoshis,
            lockingScriptBytes: [0x51],
            publicKey: scenario.reservation.inputs[0].publicKey
        )
        let participantReservationSource = DelayedParticipantReservationSource(
            participantInputs: [unsupportedInput],
            participantOutputs: scenario.reservation.outputs,
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
            nowProvider: { await nowProvider.now() },
            clockTickInterval: .milliseconds(100),
            covertTransportFactory: { covertTransport }
        )

        await session.start()
        _ = try await coordinator.nextClientMessage()

        await nowProvider.update(unixSeconds: 996)
        try await coordinator.send(.serverHello(scenario.serverHello))
        _ = try await coordinator.nextClientMessage()

        await nowProvider.update(unixSeconds: 1_000)
        try await coordinator.send(.fusionBegin(scenario.fusionBegin))
        try await LiveRuntimeTestHarness.withTimeout(.seconds(1)) {
            while await covertTransport.recordedPreparationPlans().isEmpty {
                try await Task.sleep(for: .milliseconds(10))
            }
        }

        await nowProvider.update(unixSeconds: 1_030)
        try await coordinator.send(.startRound(scenario.startRound))

        let snapshot = try await LiveRuntimeTestHarness.withTimeout(.seconds(1)) {
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
            outpointTransactionHashBytes: scenario.reservation.inputs[0].outpointTransactionHashBytes,
            outpointIndex: scenario.reservation.inputs[0].outpointIndex,
            amountSatoshis: scenario.reservation.inputs[0].amountSatoshis,
            lockingScriptBytes: [0x51],
            publicKey: scenario.reservation.inputs[0].publicKey
        )
        let participantReservationSource = DelayedParticipantReservationSource(
            participantInputs: [unsupportedInput],
            participantOutputs: scenario.reservation.outputs,
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
            nowProvider: { await nowProvider.now() },
            clockTickInterval: .milliseconds(100),
            covertTransportFactory: { covertTransport },
            snapshotDeliveryHook: { snapshot in
                if ClientSessionValidationHarness.isUnsupportedReservationTerminalSnapshot(snapshot) {
                    await snapshotDeliveryGate.block(snapshot)
                }
            }
        )

        await session.start()
        _ = try await coordinator.nextClientMessage()

        await nowProvider.update(unixSeconds: 996)
        try await coordinator.send(.serverHello(scenario.serverHello))
        _ = try await coordinator.nextClientMessage()

        await nowProvider.update(unixSeconds: 1_000)
        try await coordinator.send(.fusionBegin(scenario.fusionBegin))
        try await LiveRuntimeTestHarness.withTimeout(.seconds(1)) {
            while await covertTransport.recordedPreparationPlans().isEmpty {
                try await Task.sleep(for: .milliseconds(10))
            }
        }

        await nowProvider.update(unixSeconds: 1_030)
        try await coordinator.send(.startRound(scenario.startRound))

        let blockedSnapshot = try await LiveRuntimeTestHarness.withTimeout(.seconds(1)) {
            try await snapshotDeliveryGate.waitForBlockedSnapshot()
        }
        #expect(ClientSessionValidationHarness.isUnsupportedReservationTerminalSnapshot(blockedSnapshot))

        let polledSnapshot = await session.snapshot()
        #expect(polledSnapshot.lastError == .notImplemented)
        #expect(polledSnapshot.state.round?.completionStatus == .hostRejected)
        #expect(
            (await stateObserver.snapshot()).contains(
                where: ClientSessionValidationHarness
                    .isUnsupportedReservationTerminalSnapshot
            ) == false
        )

        await snapshotDeliveryGate.release()

        let observedSnapshots = try await LiveRuntimeTestHarness.withTimeout(.seconds(1)) {
            while true {
                let observedSnapshots = await stateObserver.snapshot()
                if observedSnapshots.filter(
                    ClientSessionValidationHarness
                        .isUnsupportedReservationTerminalSnapshot
                ).count == 1 {
                    return observedSnapshots
                }
                try await Task.sleep(for: .milliseconds(10))
            }
        }

        #expect(
            observedSnapshots.filter(
                ClientSessionValidationHarness
                    .isUnsupportedReservationTerminalSnapshot
            ).count == 1
        )

        await session.stop()
        await coordinator.stop()
    }

    @Test("Public client session drops stale snapshots after stop advances the driver generation")
    func validateStopDropsBlockedStaleSnapshotDelivery() async throws {
        let scenario = try ProductionWorkflowTestFixtures.makeScenario()
        let coordinator = try await LoopbackPrimaryCoordinator.start()
        let covertTransport = ScriptedCovertTransport()
        let stateObserver = RecordedClientStateObserver()
        let eventObserver = RecordedRoundEventObserver()
        let snapshotDeliveryGate = SessionSnapshotDeliveryGate()
        let unsupportedInput = OpalFusion.Host.ParticipantInput(
            outpointTransactionHashBytes: scenario.reservation.inputs[0].outpointTransactionHashBytes,
            outpointIndex: scenario.reservation.inputs[0].outpointIndex,
            amountSatoshis: scenario.reservation.inputs[0].amountSatoshis,
            lockingScriptBytes: [0x51],
            publicKey: scenario.reservation.inputs[0].publicKey
        )
        let participantReservationSource = DelayedParticipantReservationSource(
            participantInputs: [unsupportedInput],
            participantOutputs: scenario.reservation.outputs,
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
            nowProvider: { await nowProvider.now() },
            clockTickInterval: .milliseconds(100),
            covertTransportFactory: { covertTransport },
            snapshotDeliveryHook: { snapshot in
                if ClientSessionValidationHarness.isUnsupportedReservationTerminalSnapshot(snapshot) {
                    await snapshotDeliveryGate.block(snapshot)
                }
            }
        )

        await session.start()
        _ = try await coordinator.nextClientMessage()

        await nowProvider.update(unixSeconds: 996)
        try await coordinator.send(.serverHello(scenario.serverHello))
        _ = try await coordinator.nextClientMessage()

        await nowProvider.update(unixSeconds: 1_000)
        try await coordinator.send(.fusionBegin(scenario.fusionBegin))
        try await LiveRuntimeTestHarness.withTimeout(.seconds(1)) {
            while await covertTransport.recordedPreparationPlans().isEmpty {
                try await Task.sleep(for: .milliseconds(10))
            }
        }

        await nowProvider.update(unixSeconds: 1_030)
        try await coordinator.send(.startRound(scenario.startRound))

        let blockedSnapshot = try await LiveRuntimeTestHarness.withTimeout(.seconds(1)) {
            try await snapshotDeliveryGate.waitForBlockedSnapshot()
        }
        #expect(ClientSessionValidationHarness.isUnsupportedReservationTerminalSnapshot(blockedSnapshot))

        await session.stop()
        await snapshotDeliveryGate.release()
        try await Task.sleep(for: .milliseconds(50))

        let observedSnapshots = await stateObserver.snapshot()
        #expect(
            observedSnapshots.contains(
                where: ClientSessionValidationHarness
                    .isUnsupportedReservationTerminalSnapshot
            ) == false
        )
        let stoppedSnapshot = await session.snapshot()
        #expect(stoppedSnapshot.lastError == nil)
        #expect(stoppedSnapshot.state.isConnected == false)

        await coordinator.stop()
    }

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
            participantReservationSource: participantReservationSource,
            transactionAssembler: transactionAssembler,
            eventObserver: eventObserver,
            stateObserver: stateObserver,
            nowProvider: { await nowProvider.now() },
            clockTickInterval: .milliseconds(100),
            covertTransportFactory: { covertTransport }
        )

        await session.start()
        _ = try await coordinator.nextClientMessage()

        await nowProvider.update(unixSeconds: 996)
        try await coordinator.send(.serverHello(scenario.serverHello))
        _ = try await coordinator.nextClientMessage()

        await nowProvider.update(unixSeconds: 1_000)
        try await coordinator.send(.fusionBegin(scenario.fusionBegin))
        try await LiveRuntimeTestHarness.withTimeout(.seconds(1)) {
            while await covertTransport.recordedPreparationPlans().isEmpty {
                try await Task.sleep(for: .milliseconds(10))
            }
        }

        await nowProvider.update(unixSeconds: 1_030)
        try await coordinator.send(.startRound(scenario.startRound))
        let playerCommitMessage = try await coordinator.nextClientMessage()
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
            while await transactionAssembler.recordedProposals().isEmpty {
                try await Task.sleep(for: .milliseconds(10))
            }
        }

        let snapshot = try await LiveRuntimeTestHarness.withTimeout(.seconds(1)) {
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

private extension ClientSessionValidator {
    static let fastReconnectPolicy = OpalFusion.Client.ReconnectPolicy(
        initialDelay: .milliseconds(10),
        maximumDelay: .milliseconds(10),
        multiplier: 1,
        maximumAttempts: 3
    )

    static func waitForObservedSnapshot(
        _ stateObserver: RecordedClientStateObserver,
        matching predicate: @escaping @Sendable (
            OpalFusion.Client.Session.Snapshot
        ) -> Bool
    ) async throws -> OpalFusion.Client.Session.Snapshot {
        try await LiveRuntimeTestHarness.withTimeout(.seconds(1)) {
            while true {
                if let snapshot = await stateObserver.snapshot().last(where: predicate) {
                    return snapshot
                }

                try await Task.sleep(for: .milliseconds(10))
            }
        }
    }

    static func waitForSessionSnapshot(
        _ session: OpalFusion.Client.Session,
        matching predicate: @escaping @Sendable (
            OpalFusion.Client.Session.Snapshot
        ) -> Bool
    ) async throws -> OpalFusion.Client.Session.Snapshot {
        try await LiveRuntimeTestHarness.withTimeout(.seconds(1)) {
            while true {
                let snapshot = await session.snapshot()
                if predicate(snapshot) {
                    return snapshot
                }

                try await Task.sleep(for: .milliseconds(10))
            }
        }
    }

    static func waitForPrimaryTransport(
        _ transportFactories: SessionTransportFactoryRecorder,
        at index: Int
    ) async throws -> ScriptedPrimaryTransport {
        try await LiveRuntimeTestHarness.withTimeout(.seconds(1)) {
            while true {
                if let transport = await transportFactories.primaryTransport(at: index) {
                    return transport
                }

                try await Task.sleep(for: .milliseconds(10))
            }
        }
    }

    static func waitForWrittenPayloadCount(
        _ transport: ScriptedPrimaryTransport,
        count: Int
    ) async throws {
        try await LiveRuntimeTestHarness.withTimeout(.seconds(1)) {
            while await transport.recordedWrittenPayloads().count < count {
                try await Task.sleep(for: .milliseconds(10))
            }
        }
    }

    static func advanceToStartRound(
        _ transport: ScriptedPrimaryTransport,
        nowProvider: ScriptedInstantClock,
        covertTransport: ScriptedCovertTransport
    ) async throws {
        try await waitForWrittenPayloadCount(transport, count: 1)

        await nowProvider.update(unixSeconds: 996)
        await transport.yieldInboundBytes(
            try PrimaryRuntimeTestFixtures.encodeServerFrame(
                .serverHello(PrimaryRuntimeTestFixtures.serverHello)
            )
        )
        try await waitForWrittenPayloadCount(transport, count: 2)

        await nowProvider.update(unixSeconds: 1_000)
        await transport.yieldInboundBytes(
            try PrimaryRuntimeTestFixtures.encodeServerFrame(
                .fusionBegin(PrimaryRuntimeTestFixtures.fusionBegin)
            )
        )
        try await LiveRuntimeTestHarness.withTimeout(.seconds(1)) {
            while await covertTransport.recordedPreparationPlans().isEmpty {
                try await Task.sleep(for: .milliseconds(10))
            }
        }

        await nowProvider.update(unixSeconds: 1_030)
        await transport.yieldInboundBytes(
            try PrimaryRuntimeTestFixtures.encodeServerFrame(
                .startRound(PrimaryRuntimeTestFixtures.startRound)
            )
        )
    }
}

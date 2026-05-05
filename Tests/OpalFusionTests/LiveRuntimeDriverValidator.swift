// LiveRuntimeDriverValidator.swift

@testable import OpalFusion
import Foundation
import Network
import Testing

struct LiveRuntimeDriverValidator {
    @Test("Runtime configuration rejects host names with surrounding whitespace")
    func validateHostNamesWithSurroundingWhitespace() {
        let baseConfiguration = PrimaryRuntimeTestFixtures.configuration

        let paddedCoordinatorConfiguration = OpalFusion.Client.Configuration(
            coordinatorHost: " \(baseConfiguration.coordinatorHost) ",
            coordinatorPort: baseConfiguration.coordinatorPort,
            coordinatorRequiresTLS: baseConfiguration.coordinatorRequiresTLS,
            covertChannel: baseConfiguration.covertChannel
        )
        #expect(
            OpalFusion.Runtime.validateConfiguration(paddedCoordinatorConfiguration) ==
                "Coordinator host must not include leading or trailing whitespace"
        )

        let paddedTorConfiguration = OpalFusion.Client.Configuration(
            coordinatorHost: baseConfiguration.coordinatorHost,
            coordinatorPort: baseConfiguration.coordinatorPort,
            coordinatorRequiresTLS: baseConfiguration.coordinatorRequiresTLS,
            covertChannel: baseConfiguration.covertChannel,
            torSocks5: .init(
                host: " 127.0.0.1 ",
                port: 9050
            )
        )
        #expect(
            OpalFusion.Runtime.validateConfiguration(paddedTorConfiguration) ==
                "Tor SOCKS5 host must not include leading or trailing whitespace"
        )
    }

    @Test("Runtime configuration rejects host names with internal whitespace")
    func validateHostNamesWithInternalWhitespace() {
        let baseConfiguration = PrimaryRuntimeTestFixtures.configuration

        let coordinatorConfiguration = OpalFusion.Client.Configuration(
            coordinatorHost: "fusion example.org",
            coordinatorPort: baseConfiguration.coordinatorPort,
            coordinatorRequiresTLS: baseConfiguration.coordinatorRequiresTLS,
            covertChannel: baseConfiguration.covertChannel
        )
        #expect(
            OpalFusion.Runtime.validateConfiguration(coordinatorConfiguration) ==
                "Coordinator host must not include whitespace"
        )

        let torConfiguration = OpalFusion.Client.Configuration(
            coordinatorHost: baseConfiguration.coordinatorHost,
            coordinatorPort: baseConfiguration.coordinatorPort,
            coordinatorRequiresTLS: baseConfiguration.coordinatorRequiresTLS,
            covertChannel: baseConfiguration.covertChannel,
            torSocks5: .init(
                host: "127.0.0. 1",
                port: 9050
            )
        )
        #expect(
            OpalFusion.Runtime.validateConfiguration(torConfiguration) ==
                "Tor SOCKS5 host must not include whitespace"
        )
    }

    @Test("Runtime configuration rejects unsupported local Tor hostname resolution")
    func validateTorSocks5LocalHostnameResolution() {
        let baseConfiguration = PrimaryRuntimeTestFixtures.configuration
        let torConfiguration = OpalFusion.Client.Configuration(
            coordinatorHost: baseConfiguration.coordinatorHost,
            coordinatorPort: baseConfiguration.coordinatorPort,
            coordinatorRequiresTLS: baseConfiguration.coordinatorRequiresTLS,
            covertChannel: baseConfiguration.covertChannel,
            torSocks5: .init(
                host: "127.0.0.1",
                port: 9_050,
                resolvesCoordinatorHostNameRemotely: false
            )
        )

        #expect(
            OpalFusion.Runtime.validateConfiguration(torConfiguration) ==
                "Tor SOCKS5 remote hostname resolution must be enabled"
        )
    }

    @Test("Runtime configuration rejects covert entry paths with surrounding whitespace")
    func validateCovertEntryPathWithSurroundingWhitespace() {
        let baseConfiguration = PrimaryRuntimeTestFixtures.configuration
        let paddedPathConfiguration = OpalFusion.Client.Configuration(
            coordinatorHost: baseConfiguration.coordinatorHost,
            coordinatorPort: baseConfiguration.coordinatorPort,
            coordinatorRequiresTLS: baseConfiguration.coordinatorRequiresTLS,
            covertChannel: .init(
                entryPath: "\(baseConfiguration.covertChannel.entryPath) ",
                maxPayloadBytes: baseConfiguration.covertChannel.maxPayloadBytes,
                requestTimeoutMilliseconds: baseConfiguration.covertChannel.requestTimeoutMilliseconds
            )
        )

        #expect(
            OpalFusion.Runtime.validateConfiguration(paddedPathConfiguration) ==
                "Covert entry path must not include leading or trailing whitespace"
        )
    }

    @Test("Runtime configuration rejects covert entry paths with internal whitespace")
    func validateCovertEntryPathWithInternalWhitespace() {
        let baseConfiguration = PrimaryRuntimeTestFixtures.configuration
        let whitespacePathConfiguration = OpalFusion.Client.Configuration(
            coordinatorHost: baseConfiguration.coordinatorHost,
            coordinatorPort: baseConfiguration.coordinatorPort,
            coordinatorRequiresTLS: baseConfiguration.coordinatorRequiresTLS,
            covertChannel: .init(
                entryPath: "/fusion path",
                maxPayloadBytes: baseConfiguration.covertChannel.maxPayloadBytes,
                requestTimeoutMilliseconds: baseConfiguration.covertChannel.requestTimeoutMilliseconds
            )
        )

        #expect(
            OpalFusion.Runtime.validateConfiguration(whitespacePathConfiguration) ==
                "Covert entry path must not include whitespace"
        )
    }

    @Test("Runtime configuration rejects covert request timeouts outside Duration range")
    func validateCovertRequestTimeoutRange() {
        let baseConfiguration = PrimaryRuntimeTestFixtures.configuration
        let oversizedTimeoutConfiguration = OpalFusion.Client.Configuration(
            coordinatorHost: baseConfiguration.coordinatorHost,
            coordinatorPort: baseConfiguration.coordinatorPort,
            coordinatorRequiresTLS: baseConfiguration.coordinatorRequiresTLS,
            covertChannel: .init(
                entryPath: baseConfiguration.covertChannel.entryPath,
                maxPayloadBytes: baseConfiguration.covertChannel.maxPayloadBytes,
                requestTimeoutMilliseconds: UInt64(Int64.max) + 1
            )
        )

        #expect(
            OpalFusion.Runtime.validateConfiguration(oversizedTimeoutConfiguration) ==
                "Covert request timeout must fit the supported duration range"
        )
    }

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

    @Test("Live runtime driver rejects invalid genesis hashes before transport connect")
    func validateGenesisHashStartupValidation() async throws {
        let primaryTransport = ScriptedPrimaryTransport()
        let driver = OpalFusion.Runtime.LiveRuntimeDriver(
            configuration: PrimaryRuntimeTestFixtures.configuration,
            genesisHash: [0x00],
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

        await driver.start()

        let snapshot = await driver.snapshot()
        #expect(snapshot.lastError == .invalidConfiguration)
        #expect(snapshot.lastErrorSummary == "Genesis hash must be 32 bytes")
        #expect(snapshot.clientState.isConnected == false)
        #expect(await primaryTransport.recordedConnectCallCount() == 0)
    }

    @Test("Live runtime driver rejects invalid join-pool requests before transport connect")
    func validateJoinPoolStartupValidation() async throws {
        let primaryTransport = ScriptedPrimaryTransport()
        let driver = OpalFusion.Runtime.LiveRuntimeDriver(
            configuration: PrimaryRuntimeTestFixtures.configuration,
            genesisHash: PrimaryRuntimeTestFixtures.clientHello.genesisHash,
            joinPools: .init(tiers: [], tags: []),
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

        await driver.start()

        let snapshot = await driver.snapshot()
        #expect(snapshot.lastError == .invalidConfiguration)
        #expect(snapshot.lastErrorSummary == "Join pool tiers must not be empty")
        #expect(snapshot.clientState.isConnected == false)
        #expect(await primaryTransport.recordedConnectCallCount() == 0)

        #expect(
            OpalFusion.Runtime.validateStartupConfiguration(
                PrimaryRuntimeTestFixtures.configuration,
                genesisHash: PrimaryRuntimeTestFixtures.clientHello.genesisHash,
                joinPools: .init(tiers: [0], tags: [])
            ) == "Join pool tiers must be greater than zero"
        )
        #expect(
            OpalFusion.Runtime.validateStartupConfiguration(
                PrimaryRuntimeTestFixtures.configuration,
                genesisHash: PrimaryRuntimeTestFixtures.clientHello.genesisHash,
                joinPools: .init(tiers: [10_000, 10_000], tags: [])
            ) == "Join pool tiers must not contain duplicates"
        )
        #expect(
            OpalFusion.Runtime.validateStartupConfiguration(
                PrimaryRuntimeTestFixtures.configuration,
                genesisHash: PrimaryRuntimeTestFixtures.clientHello.genesisHash,
                joinPools: .init(
                    tiers: [10_000],
                    tags: [.init(identifier: [], limit: 1)]
                )
            ) == "Join pool tags must include an identifier"
        )
        #expect(
            OpalFusion.Runtime.validateStartupConfiguration(
                PrimaryRuntimeTestFixtures.configuration,
                genesisHash: PrimaryRuntimeTestFixtures.clientHello.genesisHash,
                joinPools: .init(
                    tiers: [10_000],
                    tags: [.init(identifier: [0x01], limit: 0)]
                )
            ) == "Join pool tag limits must be greater than zero"
        )
    }

    @Test("Live runtime driver rejects duplicate join-pool tag identifiers before transport connect")
    func validateDuplicateJoinPoolTagStartupValidation() async throws {
        let primaryTransport = ScriptedPrimaryTransport()
        let duplicateTag = OpalFusion.ProtocolModel.PoolTag(
            identifier: [0x01, 0x02],
            limit: 1
        )
        let driver = OpalFusion.Runtime.LiveRuntimeDriver(
            configuration: PrimaryRuntimeTestFixtures.configuration,
            genesisHash: PrimaryRuntimeTestFixtures.clientHello.genesisHash,
            joinPools: .init(
                tiers: [10_000],
                tags: [
                    duplicateTag,
                    .init(identifier: duplicateTag.identifier, limit: 2)
                ]
            ),
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

        await driver.start()

        let snapshot = await driver.snapshot()
        #expect(snapshot.lastError == .invalidConfiguration)
        #expect(snapshot.lastErrorSummary == "Join pool tags must not contain duplicate identifiers")
        #expect(snapshot.clientState.isConnected == false)
        #expect(await primaryTransport.recordedConnectCallCount() == 0)
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
        #expect(snapshot.lastErrorSummary == "Primary connection failed")
        #expect(snapshot.clientState.isConnected == false)

        let events = await eventSink.snapshot()
        guard let event = events.last else {
            Issue.record("Expected a transport failure event")
            return
        }
        #expect(event.roundIdentifier == nil)
        #expect(event.event.kind == .failure)
        #expect(event.event.phase == .connecting)
        #expect(event.event.summary == "Primary connection failed")
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
        #expect(await primaryTransport.hasPendingConnect)

        await primaryTransport.releaseConnect()
        await startTask.value

        let connectedSnapshot = await driver.snapshot()
        #expect(connectedSnapshot.clientState.isConnected)
        #expect(connectedSnapshot.lastError == nil)
        #expect(connectedSnapshot.lastErrorSummary == nil)
        #expect(await primaryTransport.recordedWrittenPayloads().isEmpty == false)
        #expect(await primaryTransport.recordedCloseCallCount() == 0)
        #expect(await primaryTransport.hasPendingConnect == false)

        await driver.stop()
    }

    @Test("Live runtime driver treats explicit stop as a non-error terminal state")
    func validateExplicitStopIsNonErrorTerminalState() async throws {
        let primaryTransport = ScriptedPrimaryTransport()
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

        await driver.start()
        let runningSnapshot = await driver.snapshot()
        #expect(runningSnapshot.clientState.isConnected)
        #expect(runningSnapshot.lastError == nil)
        #expect(runningSnapshot.lastErrorSummary == nil)

        await driver.stop()
        await driver.stop()

        let stoppedSnapshot = await driver.snapshot()
        #expect(stoppedSnapshot.clientState.isConnected == false)
        #expect(stoppedSnapshot.clientState.round == nil)
        #expect(stoppedSnapshot.lastError == nil)
        #expect(stoppedSnapshot.lastErrorSummary == nil)
        #expect(await primaryTransport.recordedCloseCallCount() == 1)
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
        #expect(await primaryTransport.hasPendingConnect)

        await primaryTransport.failConnect(connectError)
        await startTask.value

        let failedSnapshot = await driver.snapshot()
        #expect(failedSnapshot.clientState.isConnected == false)
        #expect(failedSnapshot.lastError == .transportUnavailable)
        #expect(failedSnapshot.lastErrorSummary == "Primary connection failed")
        #expect(await primaryTransport.recordedCloseCallCount() == 1)
        #expect(await primaryTransport.hasPendingConnect == false)

        let events = await eventSink.snapshot()
        guard let event = events.last else {
            Issue.record("Expected a delayed connect failure event")
            return
        }
        #expect(event.roundIdentifier == nil)
        #expect(event.event.kind == .failure)
        #expect(event.event.phase == .connecting)
        #expect(event.event.summary == "Primary connection failed")
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
        #expect(snapshot.lastErrorSummary == "Primary write failed")

        let events = await eventSink.snapshot()
        #expect(events.count == 1)
        #expect(events[0].roundIdentifier == nil)
        #expect(events[0].event.kind == .failure)
        #expect(events[0].event.summary == "Primary write failed")
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
                await observedRequiresTLS.update(configuration.coordinatorRequiresTLS)
                return OpalFusion.Runtime.LivePrimaryTransport(
                    host: configuration.coordinatorHost,
                    port: configuration.coordinatorPort,
                    requiresTLS: configuration.coordinatorRequiresTLS,
                    tlsTrustAnchorCertificateDERs: try! await LoopbackPrimaryTLSTestFixture
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

        let snapshot = try await LiveRuntimeTestSupport.withTimeout(.seconds(1)) {
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
        #expect(await observedRequiresTLS.value() == true)

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

        let snapshot = try await LiveRuntimeTestSupport.withTimeout(.seconds(1)) {
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
        let rejectionSummary = "Coordinator rejected the current flow"
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
            .serverFailure(.init(message: "Coordinator rejected JoinPools"))
        )
        await coordinator.closeConnection()

        let snapshot = try await LiveRuntimeTestSupport.withTimeout(.seconds(1)) {
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
            nowProvider: { await nowProvider.now() },
            clockTickInterval: .milliseconds(100),
            covertTransport: covertTransport
        )

        await driver.start()
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
        try await LiveRuntimeTestSupport.withTimeout(.seconds(1)) {
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
        try await LiveRuntimeTestSupport.withTimeout(.seconds(1)) {
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
        try await LiveRuntimeTestSupport.withTimeout(.seconds(1)) {
            while await covertTransport.recordedRequests().count < 2 {
                try await Task.sleep(for: .milliseconds(10))
            }
        }

        await nowProvider.update(unixSeconds: 1_055)
        try await coordinator.send(.fusionResult(PrimaryRuntimeTestFixtures.successResult))

        let snapshot = try await LiveRuntimeTestSupport.withTimeout(.seconds(1)) {
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
            participantReservationSource: participantReservationSource,
            transactionAssembler: transactionAssembler,
            hostEventSink: { roundIdentifier, event in
                await eventSink.record(
                    roundIdentifier: roundIdentifier,
                    event: event
                )
            },
            nowProvider: { await nowProvider.now() },
            clockTickInterval: .milliseconds(100),
            covertTransport: covertTransport
        )

        await driver.start()
        #expect(
            try await coordinator.nextClientMessage()
                == .clientHello(PrimaryRuntimeTestFixtures.clientHello)
        )

        await nowProvider.update(unixSeconds: 996)
        try await coordinator.send(.serverHello(scenario.serverHello))
        #expect(
            try await coordinator.nextClientMessage()
                == .joinPools(PrimaryRuntimeTestFixtures.joinPools)
        )

        await nowProvider.update(unixSeconds: 1_000)
        try await coordinator.send(.fusionBegin(scenario.fusionBegin))
        try await LiveRuntimeTestSupport.withTimeout(.seconds(1)) {
            while await covertTransport.recordedPreparationPlans().isEmpty {
                try await Task.sleep(for: .milliseconds(10))
            }
        }

        await nowProvider.update(unixSeconds: 1_030)
        try await coordinator.send(.startRound(scenario.startRound))
        let playerCommitMessage = try await coordinator.nextClientMessage()
        guard case let .playerCommit(playerCommit) = playerCommitMessage else {
            Issue.record("Expected a production PlayerCommit after StartRound")
            await driver.stop()
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
        let componentRequests = try await LiveRuntimeTestSupport.withTimeout(.seconds(1)) {
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

        try await LiveRuntimeTestSupport.withTimeout(.seconds(1)) {
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
        let allRequests = try await LiveRuntimeTestSupport.withTimeout(.seconds(1)) {
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

        let snapshot = try await LiveRuntimeTestSupport.withTimeout(.seconds(1)) {
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
        let nowProvider = ScriptedInstantClock(unixSeconds: 995)
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
            nowProvider: { await nowProvider.now() },
            clockTickInterval: .milliseconds(100),
            covertTransport: covertTransport
        )

        await driver.start()
        _ = try await coordinator.nextClientMessage()

        await nowProvider.update(unixSeconds: 996)
        try await coordinator.send(.serverHello(PrimaryRuntimeTestFixtures.serverHello))
        _ = try await coordinator.nextClientMessage()

        await nowProvider.update(unixSeconds: 1_000)
        try await coordinator.send(.fusionBegin(PrimaryRuntimeTestFixtures.fusionBegin))
        try await LiveRuntimeTestSupport.withTimeout(.seconds(1)) {
            while await covertTransport.recordedPreparationPlans().isEmpty {
                try await Task.sleep(for: .milliseconds(10))
            }
        }

        await nowProvider.update(unixSeconds: 1_030)
        try await coordinator.send(.startRound(PrimaryRuntimeTestFixtures.startRound))
        _ = try await coordinator.nextClientMessage()

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
        try await LiveRuntimeTestSupport.withTimeout(.seconds(1)) {
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
        try await LiveRuntimeTestSupport.withTimeout(.seconds(1)) {
            while await covertTransport.recordedRequests().count < 2 {
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

        let resetCountBeforeRestart = await covertTransport.recordedResetCount()

        await nowProvider.update(unixSeconds: 1_060)
        try await coordinator.send(.restartRound(.init()))

        let snapshot = try await LiveRuntimeTestSupport.withTimeout(.seconds(1)) {
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
        let nowProvider = ScriptedInstantClock(unixSeconds: 995)
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
            nowProvider: { await nowProvider.now() },
            clockTickInterval: .milliseconds(100),
            primaryTransport: primaryTransport,
            covertTransport: covertTransport
        )

        await driver.start()
        try await LiveRuntimeTestSupport.withTimeout(.seconds(1)) {
            while await primaryTransport.recordedWrittenPayloads().isEmpty {
                try await Task.sleep(for: .milliseconds(10))
            }
        }

        await nowProvider.update(unixSeconds: 996)
        await primaryTransport.yieldInboundBytes(
            try PrimaryRuntimeTestFixtures.encodeServerFrame(
                .serverHello(PrimaryRuntimeTestFixtures.serverHello)
            )
        )
        try await LiveRuntimeTestSupport.withTimeout(.seconds(1)) {
            while await primaryTransport.recordedWrittenPayloads().count < 2 {
                try await Task.sleep(for: .milliseconds(10))
            }
        }

        await nowProvider.update(unixSeconds: 1_000)
        await primaryTransport.yieldInboundBytes(
            try PrimaryRuntimeTestFixtures.encodeServerFrame(
                .fusionBegin(PrimaryRuntimeTestFixtures.fusionBegin)
            )
        )
        try await LiveRuntimeTestSupport.withTimeout(.seconds(1)) {
            while await covertTransport.recordedPreparationPlans().isEmpty {
                try await Task.sleep(for: .milliseconds(10))
            }
        }

        await nowProvider.update(unixSeconds: 1_030)
        await primaryTransport.yieldInboundBytes(
            try PrimaryRuntimeTestFixtures.encodeServerFrame(
                .startRound(PrimaryRuntimeTestFixtures.startRound)
            )
        )
        try await LiveRuntimeTestSupport.withTimeout(.seconds(1)) {
            while await primaryTransport.recordedWrittenPayloads().count < 3 {
                try await Task.sleep(for: .milliseconds(10))
            }
        }

        await nowProvider.update(unixSeconds: 1_032)
        await primaryTransport.yieldInboundBytes(
            try PrimaryRuntimeTestFixtures.encodeServerFrame(
                .blindSignatureResponses(PrimaryRuntimeTestFixtures.blindSignatureResponses)
            )
        )

        await nowProvider.update(unixSeconds: 1_034)
        await primaryTransport.yieldInboundBytes(
            try PrimaryRuntimeTestFixtures.encodeServerFrame(
                .allCommitments(PrimaryRuntimeTestFixtures.allCommitments)
            )
        )
        await nowProvider.update(unixSeconds: 1_035)
        try await LiveRuntimeTestSupport.withTimeout(.seconds(1)) {
            while await covertTransport.recordedRequests().count < 1 {
                try await Task.sleep(for: .milliseconds(10))
            }
        }

        let snapshotBeforeStop = await driver.snapshot()
        #expect(snapshotBeforeStop.clientState.round?.phase == .awaitingCommitments)
        #expect(snapshotBeforeStop.lastError == nil)

        await driver.stop()

        let stoppedSnapshot = try await LiveRuntimeTestSupport.withTimeout(.seconds(1)) {
            while true {
                let snapshot = await driver.snapshot()
                if snapshot.lastError == nil &&
                    snapshot.lastErrorSummary == nil &&
                    snapshot.clientState.isConnected == false {
                    return snapshot
                }
                try await Task.sleep(for: .milliseconds(10))
            }
        }
        #expect(stoppedSnapshot.lastError == nil)
        #expect(stoppedSnapshot.lastErrorSummary == nil)
        #expect(stoppedSnapshot.clientState.isConnected == false)
        #expect(stoppedSnapshot.clientState.round == nil)
        #expect(await covertTransport.recordedResetCount() > 0)

        let eventsAfterStop = await eventSink.snapshot()
        #expect(eventsAfterStop.contains { $0.event.summary == "Primary channel disconnected" } == false)

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
        let nowProvider = ScriptedInstantClock(unixSeconds: 995)
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
            nowProvider: { await nowProvider.now() },
            clockTickInterval: .milliseconds(100),
            primaryTransport: primaryTransport,
            covertTransport: covertTransport
        )

        await driver.start()
        try await LiveRuntimeTestSupport.withTimeout(.seconds(1)) {
            while await primaryTransport.recordedWrittenPayloads().isEmpty {
                try await Task.sleep(for: .milliseconds(10))
            }
        }

        await nowProvider.update(unixSeconds: 996)
        await primaryTransport.yieldInboundBytes(
            try PrimaryRuntimeTestFixtures.encodeServerFrame(
                .serverHello(PrimaryRuntimeTestFixtures.serverHello)
            )
        )
        try await LiveRuntimeTestSupport.withTimeout(.seconds(1)) {
            while await primaryTransport.recordedWrittenPayloads().count < 2 {
                try await Task.sleep(for: .milliseconds(10))
            }
        }

        await nowProvider.update(unixSeconds: 1_000)
        await primaryTransport.yieldInboundBytes(
            try PrimaryRuntimeTestFixtures.encodeServerFrame(
                .fusionBegin(PrimaryRuntimeTestFixtures.fusionBegin)
            )
        )
        try await LiveRuntimeTestSupport.withTimeout(.seconds(1)) {
            while await covertTransport.recordedPreparationPlans().isEmpty {
                try await Task.sleep(for: .milliseconds(10))
            }
        }

        await nowProvider.update(unixSeconds: 1_030)
        await primaryTransport.yieldInboundBytes(
            try PrimaryRuntimeTestFixtures.encodeServerFrame(
                .startRound(PrimaryRuntimeTestFixtures.startRound)
            )
        )
        try await Task.sleep(for: .milliseconds(50))

        #expect(await primaryTransport.recordedWrittenPayloads().count == 2)

        await driver.stop()
        let stoppedSnapshot = await driver.snapshot()
        #expect(stoppedSnapshot.lastError == nil)
        #expect(stoppedSnapshot.lastErrorSummary == nil)
        #expect(stoppedSnapshot.clientState.isConnected == false)
        #expect(stoppedSnapshot.clientState.round == nil)

        await participantReservationSource.releaseReservation()
        try await Task.sleep(for: .milliseconds(100))

        let finalSnapshot = await driver.snapshot()
        #expect(finalSnapshot == stoppedSnapshot)
        #expect(await primaryTransport.recordedWrittenPayloads().count == 2)

        let events = await eventSink.snapshot()
        #expect(events.contains { $0.event.summary == "Primary channel disconnected" } == false)
        #expect(events.contains { $0.event.summary == "Submitting player commitments and blind requests" } == false)
    }

    @Test("Live runtime driver ignores stale transaction finalization after stop")
    func validateStaleTransactionFinalizationIsIgnoredAfterStop() async throws {
        let primaryTransport = ScriptedPrimaryTransport()
        let covertTransport = ScriptedCovertTransport()
        let eventSink = RecordedHostEventSink()
        let nowProvider = ScriptedInstantClock(unixSeconds: 995)
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
            nowProvider: { await nowProvider.now() },
            clockTickInterval: .milliseconds(100),
            primaryTransport: primaryTransport,
            covertTransport: covertTransport
        )

        await driver.start()
        try await LiveRuntimeTestSupport.withTimeout(.seconds(1)) {
            while await primaryTransport.recordedWrittenPayloads().isEmpty {
                try await Task.sleep(for: .milliseconds(10))
            }
        }

        await nowProvider.update(unixSeconds: 996)
        await primaryTransport.yieldInboundBytes(
            try PrimaryRuntimeTestFixtures.encodeServerFrame(
                .serverHello(PrimaryRuntimeTestFixtures.serverHello)
            )
        )
        try await LiveRuntimeTestSupport.withTimeout(.seconds(1)) {
            while await primaryTransport.recordedWrittenPayloads().count < 2 {
                try await Task.sleep(for: .milliseconds(10))
            }
        }

        await nowProvider.update(unixSeconds: 1_000)
        await primaryTransport.yieldInboundBytes(
            try PrimaryRuntimeTestFixtures.encodeServerFrame(
                .fusionBegin(PrimaryRuntimeTestFixtures.fusionBegin)
            )
        )
        try await LiveRuntimeTestSupport.withTimeout(.seconds(1)) {
            while await covertTransport.recordedPreparationPlans().isEmpty {
                try await Task.sleep(for: .milliseconds(10))
            }
        }

        await nowProvider.update(unixSeconds: 1_030)
        await primaryTransport.yieldInboundBytes(
            try PrimaryRuntimeTestFixtures.encodeServerFrame(
                .startRound(PrimaryRuntimeTestFixtures.startRound)
            )
        )
        try await LiveRuntimeTestSupport.withTimeout(.seconds(1)) {
            while await primaryTransport.recordedWrittenPayloads().count < 3 {
                try await Task.sleep(for: .milliseconds(10))
            }
        }

        await nowProvider.update(unixSeconds: 1_032)
        await primaryTransport.yieldInboundBytes(
            try PrimaryRuntimeTestFixtures.encodeServerFrame(
                .blindSignatureResponses(PrimaryRuntimeTestFixtures.blindSignatureResponses)
            )
        )

        await nowProvider.update(unixSeconds: 1_034)
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
        await nowProvider.update(unixSeconds: 1_035)
        try await Task.sleep(for: .milliseconds(150))
        #expect(await covertTransport.recordedRequests().count == 1)

        await nowProvider.update(unixSeconds: 1_040)
        await primaryTransport.yieldInboundBytes(
            try PrimaryRuntimeTestFixtures.encodeServerFrame(
                .shareCovertComponents(PrimaryRuntimeTestFixtures.sharedComponents)
            )
        )
        try await Task.sleep(for: .milliseconds(50))

        #expect(await covertTransport.recordedRequests().count == 1)

        await driver.stop()
        let stoppedSnapshot = await driver.snapshot()
        #expect(stoppedSnapshot.lastError == nil)
        #expect(stoppedSnapshot.lastErrorSummary == nil)
        #expect(stoppedSnapshot.clientState.isConnected == false)
        #expect(stoppedSnapshot.clientState.round == nil)

        await transactionAssembler.releaseTransaction()
        try await Task.sleep(for: .milliseconds(100))

        let finalSnapshot = await driver.snapshot()
        #expect(finalSnapshot == stoppedSnapshot)
        #expect(await covertTransport.recordedRequests().count == 1)

        let events = await eventSink.snapshot()
        #expect(events.contains { $0.event.summary == "Primary channel disconnected" } == false)
        #expect(events.contains { $0.event.summary == "Transaction finalized; waiting for signature window" } == false)
        #expect(events.contains { $0.event.summary == "Submitting covert transaction signatures" } == false)
    }
}

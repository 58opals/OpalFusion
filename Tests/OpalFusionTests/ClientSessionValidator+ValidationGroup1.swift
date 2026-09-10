// ClientSessionValidator+ValidationGroup1.swift

@testable import OpalFusion
import Foundation
import Testing

extension ClientSessionValidator {
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
            hostParticipantReservationSource: HostParticipantReservationSourceAdapter(
                participantInputs: [PrimaryRuntimeTestFixtures.participantInput]
            ),
            hostTransactionAssembler: HostTransactionAssemblerAdapter(
                finalizedTransaction: PrimaryRuntimeTestFixtures.finalizedTransaction
            ),
            stateObserver: stateObserver
        )

        await session.start()

        let snapshot = await session.currentSnapshot
        #expect(snapshot.lastError == .invalidConfiguration)
        #expect(snapshot.lastErrorSummary == "Coordinator host must not be empty")
        #expect(snapshot.state.isConnected == false)
        #expect(snapshot.state.round == nil)

        let observedSnapshots = await stateObserver.recordedSnapshots
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
            hostParticipantReservationSource: HostParticipantReservationSourceAdapter(
                participantInputs: [PrimaryRuntimeTestFixtures.participantInput]
            ),
            hostTransactionAssembler: HostTransactionAssemblerAdapter(
                finalizedTransaction: PrimaryRuntimeTestFixtures.finalizedTransaction
            ),
            stateObserver: stateObserver,
            primaryTransportFactory: { await transportFactories.makePrimary() },
            covertTransportFactory: { await transportFactories.makeCovert() }
        )

        await session.start()

        let snapshot = await session.currentSnapshot
        #expect(snapshot.lastError == .transportUnavailable)
        #expect(snapshot.lastErrorSummary == "Primary connection failed")
        #expect(snapshot.state.isConnected == false)
        #expect(await transportFactories.primaryTransportCount == 1)

        let observedSnapshots = await stateObserver.recordedSnapshots
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
            hostParticipantReservationSource: HostParticipantReservationSourceAdapter(
                participantInputs: [PrimaryRuntimeTestFixtures.participantInput]
            ),
            hostTransactionAssembler: HostTransactionAssemblerAdapter(
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

        let observedSnapshots = await stateObserver.recordedSnapshots
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
            hostParticipantReservationSource: HostParticipantReservationSourceAdapter(
                participantInputs: [PrimaryRuntimeTestFixtures.participantInput]
            ),
            hostTransactionAssembler: HostTransactionAssemblerAdapter(
                finalizedTransaction: PrimaryRuntimeTestFixtures.finalizedTransaction
            ),
            stateObserver: stateObserver,
            primaryTransportFactory: { primaryTransport }
        )

        await session.start()

        let snapshot = await session.currentSnapshot
        #expect(snapshot.lastError == .transportUnavailable)
        #expect(snapshot.lastErrorSummary == "Primary connection failed")
        #expect(snapshot.state.isConnected == false)

        let observedSnapshots = await stateObserver.recordedSnapshots
        #expect(observedSnapshots.contains(snapshot))
        #expect(observedSnapshots.contains {
            $0.lastError == .transportUnavailable &&
                $0.lastErrorSummary == "Primary connection failed"
        })

        await session.stop()
        await coordinator.stop()
    }
}

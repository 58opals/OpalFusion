// ClientSessionValidator+ValidationGroup2.swift

@testable import OpalFusion
import Foundation
import Testing

extension ClientSessionValidator {
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
        #expect(
            try await coordinator.readNextClientMessage()
                == .clientHello(PrimaryRuntimeTestFixtures.clientHello)
        )

        try await coordinator.send(.serverHello(PrimaryRuntimeTestFixtures.serverHello))
        #expect(
            try await coordinator.readNextClientMessage()
                == .joinPools(PrimaryRuntimeTestFixtures.joinPools)
        )

        let snapshot = try await LiveRuntimeTestHarness.withTimeout(.seconds(1)) {
            while true {
                let snapshot = await session.currentSnapshot
                if snapshot.state.isConnected {
                    return snapshot
                }
                try await Task.sleep(for: .milliseconds(10))
            }
        }
        #expect(snapshot.lastError == nil)
        #expect(snapshot.lastErrorSummary == nil)

        let observedSnapshots = await stateObserver.recordedSnapshots
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
        await session.start()

        let runningSnapshot = try await LiveRuntimeTestHarness.withTimeout(.seconds(1)) {
            while true {
                let snapshot = await session.currentSnapshot
                if snapshot.state.isConnected {
                    return snapshot
                }
                try await Task.sleep(for: .milliseconds(10))
            }
        }
        #expect(runningSnapshot.lastError == nil)
        #expect(runningSnapshot.lastErrorSummary == nil)
        #expect(await transportFactories.primaryTransportCount == 1)

        await session.stop()
        await session.stop()

        let stoppedSnapshot = try await LiveRuntimeTestHarness.withTimeout(.seconds(1)) {
            while true {
                let snapshot = await session.currentSnapshot
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

        let observedSnapshotsAfterStop = await stateObserver.recordedSnapshots
        #expect(observedSnapshotsAfterStop.last == stoppedSnapshot)

        await session.start()
        let restartedSnapshot = try await LiveRuntimeTestHarness.withTimeout(.seconds(1)) {
            while true {
                let snapshot = await session.currentSnapshot
                if snapshot.state.isConnected {
                    return snapshot
                }
                try await Task.sleep(for: .milliseconds(10))
            }
        }

        #expect(restartedSnapshot.lastError == nil)
        #expect(restartedSnapshot.lastErrorSummary == nil)
        #expect(await transportFactories.primaryTransportCount == 2)

        let observedSnapshots = await stateObserver.recordedSnapshots
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
}

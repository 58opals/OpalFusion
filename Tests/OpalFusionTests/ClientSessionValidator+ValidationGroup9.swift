// ClientSessionValidator+ValidationGroup9.swift

@testable import OpalFusion
import Foundation
import Testing

extension ClientSessionValidator {
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
            hostParticipantReservationSource: HostParticipantReservationSourceAdapter(
                participantInputs: [PrimaryRuntimeTestFixtures.participantInput]
            ),
            hostTransactionAssembler: HostTransactionAssemblerAdapter(
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

        let stoppedSnapshot = await session.currentSnapshot
        #expect(stoppedSnapshot.lastError == nil)
        #expect(stoppedSnapshot.lastErrorSummary == nil)
        #expect(stoppedSnapshot.state.isConnected == false)
        #expect(stoppedSnapshot.state.round == nil)
        #expect(await transportFactories.primaryTransportCount == 1)
    }

    @Test("Public client session stop clears pending reconnect handshake diagnostics")
    func validateStopClearsPendingReconnectHandshakeDiagnostics() async throws {
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

        let stoppedSnapshot = await session.currentSnapshot
        #expect(stoppedSnapshot.lastError == nil)
        #expect(await transportFactories.primaryTransportCount == 1)
    }

    @Test("Public client session stop preserves pending reconnect coordinator status")
    func validateStopPreservesPendingReconnectCoordinatorStatus() async throws {
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

        let stoppedSnapshot = await session.currentSnapshot
        #expect(stoppedSnapshot.coordinatorStatus == retrySnapshot.coordinatorStatus)
        #expect(await transportFactories.primaryTransportCount == 1)
    }
}

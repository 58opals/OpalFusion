// ClientSessionValidator+ValidationGroup7.swift

@testable import OpalFusion
import Foundation
import Testing

extension ClientSessionValidator {
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
            nowProvider: { await nowProvider.current },
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
}

// ClientSessionValidator+ValidationGroup8.swift

@testable import OpalFusion
import Foundation
import Testing

extension ClientSessionValidator {
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
            hostParticipantReservationSource: HostParticipantReservationSourceAdapter(
                participantInputs: [PrimaryRuntimeTestFixtures.participantInput]
            ),
            hostTransactionAssembler: HostTransactionAssemblerAdapter(
                finalizedTransaction: PrimaryRuntimeTestFixtures.finalizedTransaction
            ),
            stateObserver: invalidConfigurationObserver,
            reconnectPolicy: Self.fastReconnectPolicy,
            primaryTransportFactory: { await invalidConfigurationFactories.makePrimary() }
        )

        await invalidConfigurationSession.start()
        #expect((await invalidConfigurationSession.currentSnapshot).lastError == .invalidConfiguration)
        try await Task.sleep(for: .milliseconds(50))
        #expect(await invalidConfigurationFactories.primaryTransportCount == 0)
        await invalidConfigurationSession.stop()

        let protocolFactories = SessionTransportFactoryRecorder()
        let protocolSession = OpalFusion.Client.Session(
            configuration: PrimaryRuntimeTestFixtures.configuration,
            genesisHash: PrimaryRuntimeTestFixtures.clientHello.genesisHash,
            joinPools: PrimaryRuntimeTestFixtures.joinPools,
            hostParticipantReservationSource: HostParticipantReservationSourceAdapter(
                participantInputs: [PrimaryRuntimeTestFixtures.participantInput]
            ),
            hostTransactionAssembler: HostTransactionAssemblerAdapter(
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
        #expect(await protocolFactories.primaryTransportCount == 1)
        await protocolSession.stop()

        let coordinatorFactories = SessionTransportFactoryRecorder()
        let coordinatorSession = OpalFusion.Client.Session(
            configuration: PrimaryRuntimeTestFixtures.configuration,
            genesisHash: PrimaryRuntimeTestFixtures.clientHello.genesisHash,
            joinPools: PrimaryRuntimeTestFixtures.joinPools,
            hostParticipantReservationSource: HostParticipantReservationSourceAdapter(
                participantInputs: [PrimaryRuntimeTestFixtures.participantInput]
            ),
            hostTransactionAssembler: HostTransactionAssemblerAdapter(
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
        #expect(await coordinatorFactories.primaryTransportCount == 1)
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
            hostParticipantReservationSource: hostReservationSource,
            hostTransactionAssembler: HostTransactionAssemblerAdapter(
                finalizedTransaction: PrimaryRuntimeTestFixtures.finalizedTransaction
            ),
            reconnectPolicy: Self.fastReconnectPolicy,
            workflow: PrimaryRuntimeTestFixtures.workflow,
            nowProvider: { await hostNowProvider.current },
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
            while (await hostReservationSource.requestedRounds).isEmpty {
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
        #expect(await hostFactories.primaryTransportCount == 1)
        await hostSession.stop()
    }
}

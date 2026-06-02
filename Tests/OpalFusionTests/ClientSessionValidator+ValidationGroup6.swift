// ClientSessionValidator+ValidationGroup6.swift

@testable import OpalFusion
import Foundation
import Testing

extension ClientSessionValidator {
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
            nowProvider: { await nowProvider.current },
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
        #expect(await transportFactories.primaryTransportCount == 1)

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
        #expect(await transportFactories.primaryTransportCount == 1)

        await session.stop()
    }
}

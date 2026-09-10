// ClientSessionValidator+ValidationGroup5.swift

@testable import OpalFusion
import Foundation
import Testing

extension ClientSessionValidator {
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

        #expect(policy.calculateDelay(forRetryAttempt: 1) == .milliseconds(9_224))
    }

    @Test("Public client session retries peer EOF after ClientHello with handshake diagnostics")
    func validateReconnectAfterClientHelloEOFDiagnostics() async throws {
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
        #expect(await transportFactories.primaryTransportCount == 2)

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
            hostParticipantReservationSource: HostParticipantReservationSourceAdapter(
                participantInputs: [PrimaryRuntimeTestFixtures.participantInput]
            ),
            hostTransactionAssembler: HostTransactionAssemblerAdapter(
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
        #expect(await transportFactories.primaryTransportCount == 2)

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
            hostParticipantReservationSource: HostParticipantReservationSourceAdapter(
                participantInputs: [PrimaryRuntimeTestFixtures.participantInput]
            ),
            hostTransactionAssembler: HostTransactionAssemblerAdapter(
                finalizedTransaction: PrimaryRuntimeTestFixtures.finalizedTransaction
            ),
            stateObserver: stateObserver,
            reconnectPolicy: Self.fastReconnectPolicy,
            workflow: PrimaryRuntimeTestFixtures.workflow,
            nowProvider: { await nowProvider.current },
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
            while (await covertTransport.recordedPreparationPlans).isEmpty {
                try await Task.sleep(for: .milliseconds(10))
            }
        }

        await firstTransport.finishInbound()
        _ = try await Self.waitForSessionSnapshot(session) {
            $0.lastError == .transportUnavailable &&
                $0.state.isConnected == false
        }

        try await Task.sleep(for: .milliseconds(50))
        #expect(await transportFactories.primaryTransportCount == 1)

        await session.stop()
    }
}

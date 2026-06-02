// ClientSessionValidator+ValidationGroup4.swift

@testable import OpalFusion
import Foundation
import Testing

extension ClientSessionValidator {
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
        #expect(await transportFactories.primaryTransportCount == 2)

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
        #expect(await transportFactories.primaryTransportCount == 2)

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

        #expect(policy.calculateDelay(forRetryAttempt: 1) == .milliseconds(10))
        #expect(policy.calculateDelay(forRetryAttempt: 2) == .milliseconds(30))
        #expect(policy.calculateDelay(forRetryAttempt: 3) == .milliseconds(30))
    }

    @Test("Public client session reconnect policy clamps huge configured delays")
    func validateReconnectPolicyClampsHugeConfiguredDelays() {
        let policy = OpalFusion.Client.ReconnectPolicy(
            initialDelay: .seconds(Int64.max),
            maximumDelay: .seconds(Int64.max),
            multiplier: 1,
            maximumAttempts: 1
        )

        #expect(policy.calculateDelay(forRetryAttempt: 1) == .milliseconds(Int.max))
    }

    @Test("Public client session reconnect policy disables unbounded zero-delay retry loops")
    func validateReconnectPolicyDisablesUnboundedImmediateRetryLoop() {
        let policy = OpalFusion.Client.ReconnectPolicy(
            initialDelay: .zero,
            maximumDelay: .zero,
            multiplier: 1,
            maximumAttempts: nil
        )

        #expect(policy.calculateDelay(forRetryAttempt: 1) == nil)
    }

    @Test("Public client session reconnect policy detects negative sub-millisecond delays")
    func validateReconnectPolicyDetectsNegativeSubmillisecondDelays() {
        #expect(Duration.nanoseconds(-1).opalFusionMillisecondsRoundedUp == -1)
        #expect(Duration.microseconds(-1).opalFusionMillisecondsRoundedUp == -1)
        #expect(Duration.milliseconds(-1).opalFusionMillisecondsRoundedUp == -1)
        #expect(Duration.nanoseconds(1).opalFusionMillisecondsRoundedUp == 1)
    }
}

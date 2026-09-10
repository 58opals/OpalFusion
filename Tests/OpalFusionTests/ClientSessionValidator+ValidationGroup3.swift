// ClientSessionValidator+ValidationGroup3.swift

@testable import OpalFusion
import Foundation
import Testing

extension ClientSessionValidator {
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

        let failedSnapshot = await session.currentSnapshot
        #expect(failedSnapshot.lastError == .transportUnavailable)
        #expect(failedSnapshot.lastErrorSummary == "Primary connection failed")

        await session.stop()
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

        let failedSnapshot = await session.currentSnapshot
        #expect(failedSnapshot.lastError == .transportUnavailable)
        #expect(failedSnapshot.lastErrorSummary == "Primary connection failed")
        #expect(failedSnapshot.state.isConnected == false)

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

        guard let firstTransport = await transportFactories.primaryTransport(at: 0) else {
            Issue.record("Expected first primary transport")
            return
        }
        await firstTransport.finishInbound(
            throwing: NSError(domain: "ClientSessionValidator", code: 9)
        )

        let failedSnapshot = try await LiveRuntimeTestHarness.withTimeout(.seconds(1)) {
            while true {
                let snapshot = await session.currentSnapshot
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
                let snapshot = await session.currentSnapshot
                if snapshot.state.isConnected && snapshot.lastError == nil {
                    return snapshot
                }
                try await Task.sleep(for: .milliseconds(10))
            }
        }

        #expect(restartedSnapshot.lastErrorSummary == nil)
        #expect(await transportFactories.primaryTransportCount == 2)

        await session.stop()
    }
}

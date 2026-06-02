// LiveRuntimeDriverValidator+ValidationGroup11.swift

@testable import OpalFusion
import Foundation
import Network
import Testing

extension LiveRuntimeDriverValidator {
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
            nowProvider: { await nowProvider.current },
            clockTickInterval: .milliseconds(100),
            covertTransport: covertTransport
        )

        await driver.start()
        _ = try await coordinator.readNextClientMessage()

        await nowProvider.update(unixSeconds: 996)
        try await coordinator.send(.serverHello(PrimaryRuntimeTestFixtures.serverHello))
        _ = try await coordinator.readNextClientMessage()

        await nowProvider.update(unixSeconds: 1_000)
        try await coordinator.send(.fusionBegin(PrimaryRuntimeTestFixtures.fusionBegin))
        try await LiveRuntimeTestHarness.withTimeout(.seconds(1)) {
            while (await covertTransport.recordedPreparationPlans).isEmpty {
                try await Task.sleep(for: .milliseconds(10))
            }
        }

        await nowProvider.update(unixSeconds: 1_030)
        try await coordinator.send(.startRound(PrimaryRuntimeTestFixtures.startRound))
        _ = try await coordinator.readNextClientMessage()

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
        try await LiveRuntimeTestHarness.withTimeout(.seconds(1)) {
            while (await covertTransport.recordedRequests).count < 1 {
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
        try await LiveRuntimeTestHarness.withTimeout(.seconds(1)) {
            while (await covertTransport.recordedRequests).count < 2 {
                try await Task.sleep(for: .milliseconds(10))
            }
        }

        await nowProvider.update(unixSeconds: 1_055)
        try await coordinator.send(.fusionResult(PrimaryRuntimeTestFixtures.failureResult))
        #expect(
            try await coordinator.readNextClientMessage()
                == .myProofsList(PrimaryRuntimeTestFixtures.myProofsList)
        )

        await nowProvider.update(unixSeconds: 1_056)
        try await coordinator.send(.theirProofsList(PrimaryRuntimeTestFixtures.theirProofsList))
        #expect(
            try await coordinator.readNextClientMessage()
                == .blames(PrimaryRuntimeTestFixtures.blames)
        )

        let resetCountBeforeRestart = await covertTransport.recordedResetCount

        await nowProvider.update(unixSeconds: 1_060)
        try await coordinator.send(.restartRound(.init()))

        let snapshot = try await LiveRuntimeTestHarness.withTimeout(.seconds(1)) {
            while true {
                let snapshot = await driver.currentSnapshot
                if snapshot.clientState.isConnected && snapshot.clientState.round == nil {
                    return snapshot
                }
                try await Task.sleep(for: .milliseconds(10))
            }
        }

        #expect(snapshot.clientState.isConnected)
        #expect(snapshot.clientState.round == nil)
        #expect(await covertTransport.recordedResetCount > resetCountBeforeRestart)

        await driver.stop()
        await coordinator.stop()
    }

    @Test("Live runtime driver resets covert transport at close-start without closing primary")
    func validateCloseStartResetPreservesPrimaryTransport() async throws {
        let primaryTransport = ScriptedPrimaryTransport()
        let covertTransport = ScriptedCovertTransport()
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
            baseline: PrimaryRuntimeTestFixtures.closeStartReachableBaseline,
            nowProvider: { await nowProvider.current },
            clockTickInterval: .milliseconds(100),
            primaryTransport: primaryTransport,
            covertTransport: covertTransport
        )

        await driver.start()
        try await driveScriptedRuntimeToPendingTransactionFinalization(
            primaryTransport: primaryTransport,
            covertTransport: covertTransport,
            nowProvider: nowProvider,
            transactionAssembler: transactionAssembler
        )
        await transactionAssembler.releaseTransaction()

        await covertTransport.enqueueResponse(
            try PrimaryRuntimeTestFixtures.encodeCovertResponsePayload(
                PrimaryRuntimeTestFixtures.acknowledgement
            )
        )
        await nowProvider.update(unixSeconds: 1_050)
        try await LiveRuntimeTestHarness.withTimeout(.seconds(1)) {
            while (await covertTransport.recordedRequests).count < 2 {
                try await Task.sleep(for: .milliseconds(10))
            }
        }

        let resetCountBeforeCloseStart = await covertTransport.recordedResetCount
        await nowProvider.update(unixSeconds: 1_075)
        let snapshot = try await LiveRuntimeTestHarness.withTimeout(.seconds(1)) {
            while true {
                if await covertTransport.recordedResetCount > resetCountBeforeCloseStart {
                    return await driver.currentSnapshot
                }
                try await Task.sleep(for: .milliseconds(10))
            }
        }

        #expect(snapshot.clientState.isConnected)
        #expect(snapshot.clientState.round?.phase == .assemblingTransaction)
        #expect(await primaryTransport.recordedCloseCallCount == 0)

        await driver.stop()
    }
}

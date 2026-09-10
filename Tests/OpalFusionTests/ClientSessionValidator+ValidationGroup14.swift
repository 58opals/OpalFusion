// ClientSessionValidator+ValidationGroup14.swift

@testable import OpalFusion
import Foundation
import Testing

extension ClientSessionValidator {
    @Test("Public client session snapshot polling does not suppress observer delivery")
    func validateSnapshotPollingDoesNotSuppressObserverDelivery() async throws {
        let scenario = try ProductionWorkflowTestFixtures.makeScenario()
        let coordinator = try await LoopbackPrimaryCoordinator.start()
        let covertTransport = ScriptedCovertTransport()
        let stateObserver = RecordedClientStateObserver()
        let eventObserver = RecordedRoundEventObserver()
        let snapshotDeliveryGate = SessionSnapshotDeliveryGate()
        let unsupportedInput = OpalFusion.Host.ParticipantInput(
            outpointTransactionHashBytes: scenario.reservation.inputs[0].outpointTransactionHashBytes,
            outpointIndex: scenario.reservation.inputs[0].outpointIndex,
            amountSatoshis: scenario.reservation.inputs[0].amountSatoshis,
            lockingScriptBytes: [0x51],
            publicKey: scenario.reservation.inputs[0].publicKey
        )
        let participantReservationSource = DelayedParticipantReservationSource(
            participantInputs: [unsupportedInput],
            participantOutputs: scenario.reservation.outputs,
            delay: .milliseconds(10)
        )
        let transactionAssembler = DelayedTransactionAssembler(
            finalizedTransaction: PrimaryRuntimeTestFixtures.finalizedTransaction,
            delay: .milliseconds(10)
        )
        let nowProvider = ScriptedInstantClock(unixSeconds: 995)
        let session = OpalFusion.Client.Session(
            configuration: .init(
                coordinatorHost: "127.0.0.1",
                coordinatorPort: await coordinator.port,
                covertChannel: PrimaryRuntimeTestFixtures.configuration.covertChannel
            ),
            genesisHash: PrimaryRuntimeTestFixtures.clientHello.genesisHash,
            joinPools: PrimaryRuntimeTestFixtures.joinPools,
            hostParticipantReservationSource: participantReservationSource,
            hostTransactionAssembler: transactionAssembler,
            eventObserver: eventObserver,
            stateObserver: stateObserver,
            nowProvider: { await nowProvider.current },
            clockTickInterval: .milliseconds(100),
            covertTransportFactory: { covertTransport },
            snapshotDeliveryHook: { snapshot in
                if ClientSessionValidationHarness.isUnsupportedReservationTerminalSnapshot(snapshot) {
                    await snapshotDeliveryGate.block(snapshot)
                }
            }
        )

        await session.start()
        _ = try await coordinator.readNextClientMessage()

        await nowProvider.update(unixSeconds: 996)
        try await coordinator.send(.serverHello(scenario.serverHello))
        _ = try await coordinator.readNextClientMessage()

        await nowProvider.update(unixSeconds: 1_000)
        try await coordinator.send(.fusionBegin(scenario.fusionBegin))
        try await LiveRuntimeTestHarness.withTimeout(.seconds(1)) {
            while (await covertTransport.recordedPreparationPlans).isEmpty {
                try await Task.sleep(for: .milliseconds(10))
            }
        }

        await nowProvider.update(unixSeconds: 1_030)
        try await coordinator.send(.startRound(scenario.startRound))

        let blockedSnapshot = try await LiveRuntimeTestHarness.withTimeout(.seconds(1)) {
            try await snapshotDeliveryGate.waitForBlockedSnapshot()
        }
        #expect(ClientSessionValidationHarness.isUnsupportedReservationTerminalSnapshot(blockedSnapshot))

        let polledSnapshot = await session.currentSnapshot
        #expect(polledSnapshot.lastError == .notImplemented)
        #expect(polledSnapshot.state.round?.completionStatus == .hostRejected)
        #expect(
            (await stateObserver.recordedSnapshots).contains(
                where: ClientSessionValidationHarness
                    .isUnsupportedReservationTerminalSnapshot
            ) == false
        )

        await snapshotDeliveryGate.release()

        let observedSnapshots = try await LiveRuntimeTestHarness.withTimeout(.seconds(1)) {
            while true {
                let observedSnapshots = await stateObserver.recordedSnapshots
                if observedSnapshots.filter(
                    ClientSessionValidationHarness
                        .isUnsupportedReservationTerminalSnapshot
                ).count == 1 {
                    return observedSnapshots
                }
                try await Task.sleep(for: .milliseconds(10))
            }
        }

        #expect(
            observedSnapshots.filter(
                ClientSessionValidationHarness
                    .isUnsupportedReservationTerminalSnapshot
            ).count == 1
        )

        await session.stop()
        await coordinator.stop()
    }
}

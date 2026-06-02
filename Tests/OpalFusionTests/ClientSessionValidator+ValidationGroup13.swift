// ClientSessionValidator+ValidationGroup13.swift

@testable import OpalFusion
import Foundation
import Testing

extension ClientSessionValidator {
    @Test("Public client session surfaces unsupported participant reservations early")
    func validateUnsupportedReservationProjection() async throws {
        let scenario = try ProductionWorkflowTestFixtures.makeScenario()
        let coordinator = try await LoopbackPrimaryCoordinator.start()
        let covertTransport = ScriptedCovertTransport()
        let stateObserver = RecordedClientStateObserver()
        let eventObserver = RecordedRoundEventObserver()
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
            participantReservationSource: participantReservationSource,
            transactionAssembler: transactionAssembler,
            eventObserver: eventObserver,
            stateObserver: stateObserver,
            nowProvider: { await nowProvider.current },
            clockTickInterval: .milliseconds(100),
            covertTransportFactory: { covertTransport }
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

        let snapshot = try await LiveRuntimeTestHarness.withTimeout(.seconds(1)) {
            while true {
                let snapshot = await session.currentSnapshot
                if snapshot.lastError == .notImplemented {
                    return snapshot
                }
                try await Task.sleep(for: .milliseconds(10))
            }
        }

        #expect(snapshot.state.round?.phase == .completed)
        #expect(snapshot.state.round?.completionStatus == .hostRejected)
        #expect((await transactionAssembler.requestedRounds).isEmpty)

        let observedEvents = await eventObserver.recordedSnapshots
        #expect(
            observedEvents.contains {
                $0.event.summary == OpalFusion.Execution.ProtocolPrimitives.supportedParticipantInputSummary
            }
        )

        let observedSnapshots = await stateObserver.recordedSnapshots
        #expect(
            observedSnapshots.contains {
                $0.lastError == .notImplemented &&
                    $0.state.round?.completionStatus == .hostRejected
            }
        )

        await session.stop()
        let stoppedSnapshot = await session.currentSnapshot
        #expect(stoppedSnapshot.lastError == .notImplemented)
        #expect(stoppedSnapshot.state.isConnected == false)
        #expect(stoppedSnapshot.state.round == snapshot.state.round)

        await coordinator.stop()
    }
}

// ClientSessionValidator+ValidationGroup12.swift

@testable import OpalFusion
import Foundation
import Testing

extension ClientSessionValidator {
    @Test("Public client session reaches eventual success after a blame restart in one session")
    func validateEventualSessionSuccessAfterRestart() async throws {
        let coordinator = try await LoopbackPrimaryCoordinator.start()
        let scriptedCovertTransport = ScriptedCovertTransport()
        let recordingCovertTransport = RecordingCovertTransport(base: scriptedCovertTransport)
        let stateObserver = RecordedClientStateObserver()
        let eventObserver = RecordedRoundEventObserver()
        let participantReservationSource = DelayedParticipantReservationSource(
            participantInputs: [PrimaryRuntimeTestFixtures.participantInput],
            participantOutputs: [PrimaryRuntimeTestFixtures.participantOutput],
            delay: .milliseconds(10)
        )
        let transactionAssembler = DelayedTransactionAssembler(
            finalizedTransaction: PrimaryRuntimeTestFixtures.finalizedTransaction,
            delay: .milliseconds(10)
        )
        let nowProvider = ScriptedInstantClock(unixSeconds: 995)
        let firstStartRound = PrimaryRuntimeTestFixtures.startRound
        let secondStartRound = OpalFusion.ProtocolModel.StartRound(
            roundPublicKey: [0xCC, 0xDD],
            blindNoncePoints: PrimaryRuntimeTestFixtures.startRound.blindNoncePoints,
            serverTimeUnixSeconds: 1_090
        )
        let secondFusionBegin = OpalFusion.ProtocolModel.FusionBegin(
            tier: PrimaryRuntimeTestFixtures.fusionBegin.tier,
            covertDomain: PrimaryRuntimeTestFixtures.fusionBegin.covertDomain,
            covertPort: PrimaryRuntimeTestFixtures.fusionBegin.covertPort,
            covertSsl: PrimaryRuntimeTestFixtures.fusionBegin.covertSsl,
            serverTimeUnixSeconds: 1_060
        )
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
            workflow: ClientSessionValidationHarness.makeRoundAwareScriptedWorkflow(),
            nowProvider: { await nowProvider.current },
            clockTickInterval: .milliseconds(100),
            covertTransportFactory: { recordingCovertTransport }
        )

        await session.start()
        try await driveBlameRestartFirstRound(
            coordinator: coordinator,
            scriptedCovertTransport: scriptedCovertTransport,
            recordingCovertTransport: recordingCovertTransport,
            nowProvider: nowProvider,
            firstStartRound: firstStartRound,
            session: session
        )
        let snapshot = try await driveSuccessfulRoundAfterRestart(
            coordinator: coordinator,
            scriptedCovertTransport: scriptedCovertTransport,
            recordingCovertTransport: recordingCovertTransport,
            nowProvider: nowProvider,
            secondFusionBegin: secondFusionBegin,
            secondStartRound: secondStartRound,
            session: session
        )

        #expect(snapshot.lastError == nil)
        #expect(snapshot.state.isConnected)
        #expect(snapshot.state.round?.phase == .completed)
        #expect(snapshot.state.round?.completionStatus == .success)

        await assertRestartSessionTranscript(
            coordinator: coordinator,
            recordingCovertTransport: recordingCovertTransport,
            eventObserver: eventObserver,
            stateObserver: stateObserver,
            participantReservationSource: participantReservationSource,
            transactionAssembler: transactionAssembler,
            firstStartRound: firstStartRound,
            secondStartRound: secondStartRound,
            session: session
        )

        await session.stop()
        await coordinator.stop()
    }
}

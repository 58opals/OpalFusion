// ClientSessionValidator+RestartRoundDriving.swift

@testable import OpalFusion
import Testing

extension ClientSessionValidator {
    func driveBlameRestartFirstRound(
        coordinator: LoopbackPrimaryCoordinator,
        scriptedCovertTransport: ScriptedCovertTransport,
        recordingCovertTransport: RecordingCovertTransport,
        nowProvider: ScriptedInstantClock,
        firstStartRound: OpalFusion.ProtocolModel.StartRound,
        session: OpalFusion.Client.Session
    ) async throws {
        #expect(
            try await coordinator.readNextClientMessage()
                == .clientHello(PrimaryRuntimeTestFixtures.clientHello)
        )

        await nowProvider.update(unixSeconds: 996)
        try await coordinator.send(.serverHello(PrimaryRuntimeTestFixtures.serverHello))
        #expect(
            try await coordinator.readNextClientMessage()
                == .joinPools(PrimaryRuntimeTestFixtures.joinPools)
        )

        await nowProvider.update(unixSeconds: 1_000)
        try await coordinator.send(.fusionBegin(PrimaryRuntimeTestFixtures.fusionBegin))
        try await waitForCovertPreparationCount(
            1,
            recordingCovertTransport: recordingCovertTransport
        )

        await nowProvider.update(unixSeconds: 1_030)
        try await coordinator.send(.startRound(firstStartRound))
        #expect(
            try await coordinator.readNextClientMessage()
                == .playerCommit(PrimaryRuntimeTestFixtures.playerCommit)
        )

        await nowProvider.update(unixSeconds: 1_032)
        try await coordinator.send(
            .blindSignatureResponses(PrimaryRuntimeTestFixtures.blindSignatureResponses)
        )
        await nowProvider.update(unixSeconds: 1_034)
        try await coordinator.send(.allCommitments(PrimaryRuntimeTestFixtures.allCommitments))

        try await enqueueAcknowledgement(
            scriptedCovertTransport: scriptedCovertTransport
        )
        await nowProvider.update(unixSeconds: 1_035)
        try await waitForCovertRequestCount(
            1,
            recordingCovertTransport: recordingCovertTransport
        )

        await nowProvider.update(unixSeconds: 1_040)
        try await coordinator.send(.shareCovertComponents(PrimaryRuntimeTestFixtures.sharedComponents))

        try await enqueueAcknowledgement(
            scriptedCovertTransport: scriptedCovertTransport
        )
        await nowProvider.update(unixSeconds: 1_050)
        try await waitForCovertRequestCount(
            2,
            recordingCovertTransport: recordingCovertTransport
        )

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

        await nowProvider.update(unixSeconds: 1_060)
        try await coordinator.send(.restartRound(.init()))
        try await waitForRestartedConnectedSnapshot(session: session)
    }

    func driveSuccessfulRoundAfterRestart(
        coordinator: LoopbackPrimaryCoordinator,
        scriptedCovertTransport: ScriptedCovertTransport,
        recordingCovertTransport: RecordingCovertTransport,
        nowProvider: ScriptedInstantClock,
        secondFusionBegin: OpalFusion.ProtocolModel.FusionBegin,
        secondStartRound: OpalFusion.ProtocolModel.StartRound,
        session: OpalFusion.Client.Session
    ) async throws -> OpalFusion.Client.Session.Snapshot {
        await nowProvider.update(unixSeconds: 1_060)
        try await coordinator.send(.fusionBegin(secondFusionBegin))
        try await waitForCovertPreparationCount(
            2,
            recordingCovertTransport: recordingCovertTransport
        )

        await nowProvider.update(unixSeconds: 1_090)
        try await coordinator.send(.startRound(secondStartRound))
        #expect(
            try await coordinator.readNextClientMessage()
                == .playerCommit(PrimaryRuntimeTestFixtures.playerCommit)
        )

        await nowProvider.update(unixSeconds: 1_092)
        try await coordinator.send(
            .blindSignatureResponses(PrimaryRuntimeTestFixtures.blindSignatureResponses)
        )
        await nowProvider.update(unixSeconds: 1_094)
        try await coordinator.send(.allCommitments(PrimaryRuntimeTestFixtures.allCommitments))

        try await enqueueAcknowledgement(
            scriptedCovertTransport: scriptedCovertTransport
        )
        await nowProvider.update(unixSeconds: 1_095)
        try await waitForCovertRequestCount(
            3,
            recordingCovertTransport: recordingCovertTransport
        )

        await nowProvider.update(unixSeconds: 1_100)
        try await coordinator.send(.shareCovertComponents(PrimaryRuntimeTestFixtures.sharedComponents))

        try await enqueueAcknowledgement(
            scriptedCovertTransport: scriptedCovertTransport
        )
        await nowProvider.update(unixSeconds: 1_110)
        try await waitForCovertRequestCount(
            4,
            recordingCovertTransport: recordingCovertTransport
        )

        await nowProvider.update(unixSeconds: 1_115)
        try await coordinator.send(.fusionResult(PrimaryRuntimeTestFixtures.successResult))
        return try await waitForSuccessfulSnapshot(session: session)
    }
}

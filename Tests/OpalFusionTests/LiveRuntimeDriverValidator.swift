// LiveRuntimeDriverValidator.swift

@testable import OpalFusion
import Foundation
import Testing

struct LiveRuntimeDriverValidator {
    @Test("Live runtime driver rejects invalid startup configuration before transport connect")
    func validateInvalidConfiguration() async throws {
        let primaryTransport = ScriptedPrimaryTransport()
        let covertTransport = ScriptedCovertTransport()
        let eventSink = RecordedHostEventSink()
        let participantInputProvider = DelayedParticipantInputProvider(
            participantInputs: [PrimaryRuntimeTestFixtures.participantInput]
        )
        let transactionAssembler = DelayedTransactionAssembler(
            finalizedTransaction: PrimaryRuntimeTestFixtures.finalizedTransaction
        )

        let driver = OpalFusion.Runtime.LiveRuntimeDriver(
            configuration: .init(
                coordinatorHost: "",
                coordinatorPort: PrimaryRuntimeTestFixtures.configuration.coordinatorPort,
                covertChannel: PrimaryRuntimeTestFixtures.configuration.covertChannel
            ),
            genesisHash: PrimaryRuntimeTestFixtures.clientHello.genesisHash,
            joinPools: PrimaryRuntimeTestFixtures.joinPools,
            workflow: PrimaryRuntimeTestFixtures.workflow,
            participantInputProvider: participantInputProvider,
            transactionAssembler: transactionAssembler,
            hostEventSink: { roundIdentifier, event in
                await eventSink.record(
                    roundIdentifier: roundIdentifier,
                    event: event
                )
            },
            primaryTransport: primaryTransport,
            covertTransport: covertTransport
        )

        await driver.start()

        let snapshot = await driver.snapshot()
        #expect(snapshot.lastError == .invalidConfiguration)
        #expect(snapshot.lastErrorSummary == "Coordinator host must not be empty")
        #expect(snapshot.clientState.isConnected == false)
        #expect(await primaryTransport.recordedConnectCallCount() == 0)

        let events = await eventSink.snapshot()
        #expect(
            events == [
                .init(
                    roundIdentifier: nil,
                    event: .init(
                        kind: .failure,
                        phase: .connecting,
                        summary: "Coordinator host must not be empty"
                    )
                )
            ]
        )
    }

    @Test("Live runtime driver maps primary connect failure to transport unavailable")
    func validatePrimaryConnectFailureProjection() async throws {
        let primaryTransport = ScriptedPrimaryTransport(
            connectError: NSError(domain: "LiveRuntimeDriverValidator", code: 1)
        )
        let eventSink = RecordedHostEventSink()
        let driver = OpalFusion.Runtime.LiveRuntimeDriver(
            configuration: PrimaryRuntimeTestFixtures.configuration,
            genesisHash: PrimaryRuntimeTestFixtures.clientHello.genesisHash,
            joinPools: PrimaryRuntimeTestFixtures.joinPools,
            workflow: PrimaryRuntimeTestFixtures.workflow,
            participantInputProvider: DelayedParticipantInputProvider(
                participantInputs: [PrimaryRuntimeTestFixtures.participantInput]
            ),
            transactionAssembler: DelayedTransactionAssembler(
                finalizedTransaction: PrimaryRuntimeTestFixtures.finalizedTransaction
            ),
            hostEventSink: { roundIdentifier, event in
                await eventSink.record(
                    roundIdentifier: roundIdentifier,
                    event: event
                )
            },
            primaryTransport: primaryTransport,
            covertTransport: ScriptedCovertTransport()
        )

        await driver.start()

        let snapshot = await driver.snapshot()
        #expect(snapshot.lastError == .transportUnavailable)
        #expect(snapshot.lastErrorSummary?.hasPrefix("Primary connect failed:") == true)
        #expect(snapshot.clientState.isConnected == false)

        let events = await eventSink.snapshot()
        guard let event = events.last else {
            Issue.record("Expected a transport failure event")
            return
        }
        #expect(event.roundIdentifier == nil)
        #expect(event.event.kind == .failure)
        #expect(event.event.phase == .connecting)
        #expect(event.event.summary.hasPrefix("Primary connect failed:"))
    }

    @Test("Live runtime driver completes a scripted round over a loopback coordinator")
    func validateHappyPathLoopbackRuntime() async throws {
        let coordinator = try await LoopbackPrimaryCoordinator.start()

        let covertTransport = ScriptedCovertTransport()
        let eventSink = RecordedHostEventSink()
        let participantInputProvider = DelayedParticipantInputProvider(
            participantInputs: [PrimaryRuntimeTestFixtures.participantInput],
            delay: .milliseconds(10)
        )
        let transactionAssembler = DelayedTransactionAssembler(
            finalizedTransaction: PrimaryRuntimeTestFixtures.finalizedTransaction,
            delay: .milliseconds(10)
        )
        let nowProvider = ScriptedNowProvider(unixSeconds: 995)
        let configuration = OpalFusion.Client.Configuration(
            coordinatorHost: "127.0.0.1",
            coordinatorPort: await coordinator.port,
            covertChannel: PrimaryRuntimeTestFixtures.configuration.covertChannel
        )
        let driver = OpalFusion.Runtime.LiveRuntimeDriver(
            configuration: configuration,
            genesisHash: PrimaryRuntimeTestFixtures.clientHello.genesisHash,
            joinPools: PrimaryRuntimeTestFixtures.joinPools,
            workflow: PrimaryRuntimeTestFixtures.workflow,
            participantInputProvider: participantInputProvider,
            transactionAssembler: transactionAssembler,
            hostEventSink: { roundIdentifier, event in
                await eventSink.record(
                    roundIdentifier: roundIdentifier,
                    event: event
                )
            },
            nowProvider: { nowProvider.now() },
            clockTickInterval: .milliseconds(10),
            covertTransport: covertTransport
        )

        await driver.start()
        #expect(
            try await coordinator.nextClientMessage()
                == .clientHello(PrimaryRuntimeTestFixtures.clientHello)
        )

        nowProvider.set(unixSeconds: 996)
        try await coordinator.send(.serverHello(PrimaryRuntimeTestFixtures.serverHello))
        #expect(
            try await coordinator.nextClientMessage()
                == .joinPools(PrimaryRuntimeTestFixtures.joinPools)
        )

        nowProvider.set(unixSeconds: 1_000)
        try await coordinator.send(.fusionBegin(PrimaryRuntimeTestFixtures.fusionBegin))
        try await withTimeout(.seconds(1)) {
            while await covertTransport.recordedPreparationPlans().isEmpty {
                try await Task.sleep(for: .milliseconds(10))
            }
        }

        nowProvider.set(unixSeconds: 1_030)
        try await coordinator.send(.startRound(PrimaryRuntimeTestFixtures.startRound))
        #expect(
            try await coordinator.nextClientMessage()
                == .playerCommit(PrimaryRuntimeTestFixtures.playerCommit)
        )

        nowProvider.set(unixSeconds: 1_032)
        try await coordinator.send(
            .blindSignatureResponses(PrimaryRuntimeTestFixtures.blindSignatureResponses)
        )

        nowProvider.set(unixSeconds: 1_034)
        try await coordinator.send(.allCommitments(PrimaryRuntimeTestFixtures.allCommitments))

        await covertTransport.enqueueResponse(
            try PrimaryRuntimeTestFixtures.encodeCovertResponsePayload(
                PrimaryRuntimeTestFixtures.acknowledgement
            )
        )
        nowProvider.set(unixSeconds: 1_035)
        try await withTimeout(.seconds(1)) {
            while await covertTransport.recordedRequests().count < 1 {
                try await Task.sleep(for: .milliseconds(10))
            }
        }

        nowProvider.set(unixSeconds: 1_040)
        try await coordinator.send(.shareCovertComponents(PrimaryRuntimeTestFixtures.sharedComponents))

        await covertTransport.enqueueResponse(
            try PrimaryRuntimeTestFixtures.encodeCovertResponsePayload(
                PrimaryRuntimeTestFixtures.acknowledgement
            )
        )
        nowProvider.set(unixSeconds: 1_050)
        try await withTimeout(.seconds(1)) {
            while await covertTransport.recordedRequests().count < 2 {
                try await Task.sleep(for: .milliseconds(10))
            }
        }

        nowProvider.set(unixSeconds: 1_055)
        try await coordinator.send(.fusionResult(PrimaryRuntimeTestFixtures.successResult))

        let snapshot = try await withTimeout(.seconds(1)) {
            while true {
                let snapshot = await driver.snapshot()
                if snapshot.clientState.round?.completionStatus == .success {
                    return snapshot
                }
                try await Task.sleep(for: .milliseconds(10))
            }
        }

        #expect(snapshot.lastError == nil)
        #expect(snapshot.clientState.isConnected)
        #expect(snapshot.clientState.round?.phase == .completed)
        #expect(snapshot.clientState.round?.completionStatus == .success)
        #expect(await participantInputProvider.requestedRounds() == [PrimaryRuntimeTestFixtures.roundIdentifier])
        #expect(await transactionAssembler.requestedRounds() == [PrimaryRuntimeTestFixtures.roundIdentifier])

        let events = await eventSink.snapshot()
        #expect(events.contains { $0.event.summary == "Round completed successfully" })

        await driver.stop()
        await coordinator.stop()
    }

    @Test("Live runtime driver completes a production-workflow round over a loopback coordinator")
    func validateProductionWorkflowLoopbackRuntime() async throws {
        var scenario = try ProductionWorkflowTestFixtures.makeScenario()
        let coordinator = try await LoopbackPrimaryCoordinator.start()

        let covertTransport = ScriptedCovertTransport()
        let eventSink = RecordedHostEventSink()
        let participantInputProvider = DelayedParticipantInputProvider(
            participantInputs: scenario.reservation.inputs,
            participantOutputs: scenario.reservation.outputs,
            delay: .milliseconds(10)
        )
        let transactionAssembler = SigningTransactionAssembler(
            participantInput: scenario.reservation.inputs[0],
            participantInputPrivateKey: scenario.participantInputPrivateKey,
            delay: .milliseconds(10)
        )
        let nowProvider = ScriptedNowProvider(unixSeconds: 995)
        let configuration = OpalFusion.Client.Configuration(
            coordinatorHost: "127.0.0.1",
            coordinatorPort: await coordinator.port,
            covertChannel: PrimaryRuntimeTestFixtures.configuration.covertChannel
        )
        let driver = OpalFusion.Runtime.LiveRuntimeDriver(
            configuration: configuration,
            genesisHash: PrimaryRuntimeTestFixtures.clientHello.genesisHash,
            joinPools: PrimaryRuntimeTestFixtures.joinPools,
            participantInputProvider: participantInputProvider,
            transactionAssembler: transactionAssembler,
            hostEventSink: { roundIdentifier, event in
                await eventSink.record(
                    roundIdentifier: roundIdentifier,
                    event: event
                )
            },
            nowProvider: { nowProvider.now() },
            clockTickInterval: .milliseconds(10),
            covertTransport: covertTransport
        )

        await driver.start()
        #expect(
            try await coordinator.nextClientMessage()
                == .clientHello(PrimaryRuntimeTestFixtures.clientHello)
        )

        nowProvider.set(unixSeconds: 996)
        try await coordinator.send(.serverHello(scenario.serverHello))
        #expect(
            try await coordinator.nextClientMessage()
                == .joinPools(PrimaryRuntimeTestFixtures.joinPools)
        )

        nowProvider.set(unixSeconds: 1_000)
        try await coordinator.send(.fusionBegin(scenario.fusionBegin))
        try await withTimeout(.seconds(1)) {
            while await covertTransport.recordedPreparationPlans().isEmpty {
                try await Task.sleep(for: .milliseconds(10))
            }
        }

        nowProvider.set(unixSeconds: 1_030)
        try await coordinator.send(.startRound(scenario.startRound))
        let playerCommitMessage = try await coordinator.nextClientMessage()
        guard case let .playerCommit(playerCommit) = playerCommitMessage else {
            Issue.record("Expected a production PlayerCommit after StartRound")
            await driver.stop()
            await coordinator.stop()
            return
        }

        let blindResponses = try scenario.buildBlindSignatureResponses(for: playerCommit)
        nowProvider.set(unixSeconds: 1_032)
        try await coordinator.send(.blindSignatureResponses(blindResponses))

        nowProvider.set(unixSeconds: 1_034)
        try await coordinator.send(
            .allCommitments(.init(initialCommitments: playerCommit.initialCommitments))
        )

        for _ in 0..<playerCommit.initialCommitments.count {
            await covertTransport.enqueueResponse(
                try PrimaryRuntimeTestFixtures.encodeCovertResponsePayload(
                    PrimaryRuntimeTestFixtures.acknowledgement
                )
            )
        }
        nowProvider.set(unixSeconds: 1_035)
        let componentRequests = try await withTimeout(.seconds(1)) {
            while true {
                let requests = await covertTransport.recordedRequests()
                if requests.count == playerCommit.initialCommitments.count {
                    return requests
                }
                try await Task.sleep(for: .milliseconds(10))
            }
        }
        let sharedSerializedComponents = try componentRequests.map { request in
            guard case let .component(componentMessage) = try PrimaryRuntimeTestFixtures
                .extractCovertMessage(from: request) else {
                throw LiveRuntimeTestSupportError.inboundStreamClosed
            }
            return componentMessage.serializedComponent
        }

        nowProvider.set(unixSeconds: 1_040)
        try await coordinator.send(
            .shareCovertComponents(
                .init(
                    serializedComponents: sharedSerializedComponents,
                    skipSignatures: false,
                    sessionHash: nil
                )
            )
        )

        try await withTimeout(.seconds(1)) {
            while await transactionAssembler.recordedProposals().isEmpty {
                try await Task.sleep(for: .milliseconds(10))
            }
        }

        await covertTransport.enqueueResponse(
            try PrimaryRuntimeTestFixtures.encodeCovertResponsePayload(
                PrimaryRuntimeTestFixtures.acknowledgement
            )
        )
        nowProvider.set(unixSeconds: 1_050)
        let allRequests = try await withTimeout(.seconds(1)) {
            while true {
                let requests = await covertTransport.recordedRequests()
                if requests.count == playerCommit.initialCommitments.count + 1 {
                    return requests
                }
                try await Task.sleep(for: .milliseconds(10))
            }
        }

        guard let signatureRequest = allRequests.last else {
            Issue.record("Expected a covert transaction-signature request")
            await driver.stop()
            await coordinator.stop()
            return
        }
        let signatureMessage = try PrimaryRuntimeTestFixtures.extractCovertMessage(
            from: signatureRequest
        )
        guard case let .transactionSignature(signaturePayload) = signatureMessage else {
            Issue.record("Expected the final covert request to carry a transaction signature")
            await driver.stop()
            await coordinator.stop()
            return
        }
        let recordedSignatures = await transactionAssembler.recordedSignatures()
        #expect(recordedSignatures == [signaturePayload.transactionSignature])
        #expect(signaturePayload.roundPublicKey == scenario.startRound.roundPublicKey)
        #expect(signaturePayload.inputIndex == 0)

        nowProvider.set(unixSeconds: 1_055)
        try await coordinator.send(
            .fusionResult(
                .init(
                    isSuccess: true,
                    transactionSignatures: [],
                    badComponentIndices: []
                )
            )
        )

        let snapshot = try await withTimeout(.seconds(1)) {
            while true {
                let snapshot = await driver.snapshot()
                if snapshot.clientState.round?.completionStatus == .success {
                    return snapshot
                }
                try await Task.sleep(for: .milliseconds(10))
            }
        }

        #expect(snapshot.lastError == nil)
        #expect(snapshot.clientState.isConnected)
        #expect(snapshot.clientState.round?.phase == .completed)
        #expect(snapshot.clientState.round?.completionStatus == .success)
        #expect(
            await participantInputProvider.requestedRounds()
                == [scenario.round.identifier!]
        )
        #expect(
            await transactionAssembler.requestedRounds()
                == [scenario.round.identifier!]
        )

        let events = await eventSink.snapshot()
        #expect(events.contains { $0.event.summary == "Round completed successfully" })

        await driver.stop()
        await coordinator.stop()
    }

    @Test("Signing transaction assembler signs the matching input instead of assuming input zero")
    func validateSigningAssemblerMatchesOutpoint() async throws {
        let scenario = try ProductionWorkflowTestFixtures.makeScenario()
        let assembler = SigningTransactionAssembler(
            participantInput: scenario.reservation.inputs[0],
            participantInputPrivateKey: scenario.participantInputPrivateKey
        )

        let unsignedTransaction = OpalFusion.Execution.BCHTransaction(
            version: 1,
            inputs: [
                .init(
                    previousTransactionHashLittleEndian: [UInt8](repeating: 0xEE, count: 32),
                    previousOutputIndex: 0,
                    unlockingScript: [],
                    sequence: .max
                ),
                .init(
                    previousTransactionHashLittleEndian: Array(
                        scenario.reservation.inputs[0].outpointTransactionHash.reversed()
                    ),
                    previousOutputIndex: scenario.reservation.inputs[0].outpointIndex,
                    unlockingScript: [],
                    sequence: .max
                ),
            ],
            outputs: [
                .init(
                    amountSatoshis: scenario.reservation.outputs[0].amountSatoshis,
                    lockingScript: scenario.reservation.outputs[0].lockingScript
                )
            ],
            lockTime: 0
        )
        let proposal = OpalFusion.Host.TransactionFinalizationProposal(
            serializedUnsignedTransaction: try unsignedTransaction.serialized()
        )

        let finalizedTransaction = try await assembler.finalizeTransaction(
            for: scenario.round.identifier!,
            proposal: proposal
        )
        let parsedTransaction = try OpalFusion.Execution.BCHTransaction.parse(
            finalizedTransaction.serializedTransaction
        )

        #expect(parsedTransaction.inputs[0].unlockingScript.isEmpty)
        #expect(parsedTransaction.inputs[1].unlockingScript.isEmpty == false)
        #expect(parsedTransaction.inputs[1].unlockingScript[0] == 0x41)
    }

    @Test("Live runtime driver clears covert state on restart while keeping primary continuity")
    func validateRestartPath() async throws {
        let coordinator = try await LoopbackPrimaryCoordinator.start()

        let covertTransport = ScriptedCovertTransport()
        let nowProvider = ScriptedNowProvider(unixSeconds: 995)
        let driver = OpalFusion.Runtime.LiveRuntimeDriver(
            configuration: .init(
                coordinatorHost: "127.0.0.1",
                coordinatorPort: await coordinator.port,
                covertChannel: PrimaryRuntimeTestFixtures.configuration.covertChannel
            ),
            genesisHash: PrimaryRuntimeTestFixtures.clientHello.genesisHash,
            joinPools: PrimaryRuntimeTestFixtures.joinPools,
            workflow: PrimaryRuntimeTestFixtures.workflow,
            participantInputProvider: DelayedParticipantInputProvider(
                participantInputs: [PrimaryRuntimeTestFixtures.participantInput]
            ),
            transactionAssembler: DelayedTransactionAssembler(
                finalizedTransaction: PrimaryRuntimeTestFixtures.finalizedTransaction
            ),
            nowProvider: { nowProvider.now() },
            clockTickInterval: .milliseconds(10),
            covertTransport: covertTransport
        )

        await driver.start()
        _ = try await coordinator.nextClientMessage()

        nowProvider.set(unixSeconds: 996)
        try await coordinator.send(.serverHello(PrimaryRuntimeTestFixtures.serverHello))
        _ = try await coordinator.nextClientMessage()

        nowProvider.set(unixSeconds: 1_000)
        try await coordinator.send(.fusionBegin(PrimaryRuntimeTestFixtures.fusionBegin))
        try await withTimeout(.seconds(1)) {
            while await covertTransport.recordedPreparationPlans().isEmpty {
                try await Task.sleep(for: .milliseconds(10))
            }
        }

        nowProvider.set(unixSeconds: 1_030)
        try await coordinator.send(.startRound(PrimaryRuntimeTestFixtures.startRound))
        _ = try await coordinator.nextClientMessage()

        nowProvider.set(unixSeconds: 1_032)
        try await coordinator.send(
            .blindSignatureResponses(PrimaryRuntimeTestFixtures.blindSignatureResponses)
        )
        nowProvider.set(unixSeconds: 1_034)
        try await coordinator.send(.allCommitments(PrimaryRuntimeTestFixtures.allCommitments))

        await covertTransport.enqueueResponse(
            try PrimaryRuntimeTestFixtures.encodeCovertResponsePayload(
                PrimaryRuntimeTestFixtures.acknowledgement
            )
        )
        nowProvider.set(unixSeconds: 1_035)
        try await withTimeout(.seconds(1)) {
            while await covertTransport.recordedRequests().count < 1 {
                try await Task.sleep(for: .milliseconds(10))
            }
        }

        nowProvider.set(unixSeconds: 1_040)
        try await coordinator.send(.shareCovertComponents(PrimaryRuntimeTestFixtures.sharedComponents))

        await covertTransport.enqueueResponse(
            try PrimaryRuntimeTestFixtures.encodeCovertResponsePayload(
                PrimaryRuntimeTestFixtures.acknowledgement
            )
        )
        nowProvider.set(unixSeconds: 1_050)
        try await withTimeout(.seconds(1)) {
            while await covertTransport.recordedRequests().count < 2 {
                try await Task.sleep(for: .milliseconds(10))
            }
        }

        nowProvider.set(unixSeconds: 1_055)
        try await coordinator.send(.fusionResult(PrimaryRuntimeTestFixtures.failureResult))
        #expect(
            try await coordinator.nextClientMessage()
                == .myProofsList(PrimaryRuntimeTestFixtures.myProofsList)
        )

        nowProvider.set(unixSeconds: 1_056)
        try await coordinator.send(.theirProofsList(PrimaryRuntimeTestFixtures.theirProofsList))
        #expect(
            try await coordinator.nextClientMessage()
                == .blames(PrimaryRuntimeTestFixtures.blames)
        )

        let resetCountBeforeRestart = await covertTransport.recordedResetCount()

        nowProvider.set(unixSeconds: 1_060)
        try await coordinator.send(.restartRound(.init()))

        let snapshot = try await withTimeout(.seconds(1)) {
            while true {
                let snapshot = await driver.snapshot()
                if snapshot.clientState.isConnected && snapshot.clientState.round == nil {
                    return snapshot
                }
                try await Task.sleep(for: .milliseconds(10))
            }
        }

        #expect(snapshot.clientState.isConnected)
        #expect(snapshot.clientState.round == nil)
        #expect(await covertTransport.recordedResetCount() > resetCountBeforeRestart)

        await driver.stop()
        await coordinator.stop()
    }
}

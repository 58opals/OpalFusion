// LiveRuntimeDriverValidator+ValidationGroup14.swift

@testable import CashFusionEngine
@testable import OpalFusionCore
import Foundation
import Network
import Testing

extension LiveRuntimeDriverValidator {
    @Test("Live runtime driver ignores stale transaction finalization after stop")
    func validateStaleTransactionFinalizationIsIgnoredAfterStop() async throws {
        let primaryTransport = ScriptedPrimaryTransport()
        let covertTransport = ScriptedCovertTransport()
        let eventSink = RecordedHostEventSink()
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
            hostEventSink: { roundIdentifier, event in
                await eventSink.record(
                    roundIdentifier: roundIdentifier,
                    event: event
                )
            },
            nowProvider: { await nowProvider.current },
            clockTickInterval: .milliseconds(100),
            primaryTransport: primaryTransport,
            covertTransport: covertTransport
        )

        do {
            await driver.start()
            try await LiveRuntimeTestHarness.withTimeout(.seconds(1)) {
                while (await primaryTransport.recordedWrittenPayloads).isEmpty {
                    try await Task.sleep(for: .milliseconds(10))
                }
            }

            await nowProvider.update(unixSeconds: 996)
            await primaryTransport.yieldInboundBytes(
                try PrimaryRuntimeTestFixtures.encodeServerFrame(
                    .serverHello(PrimaryRuntimeTestFixtures.serverHello)
                )
            )
            try await LiveRuntimeTestHarness.withTimeout(.seconds(1)) {
                while (await primaryTransport.recordedWrittenPayloads).count < 2 {
                    try await Task.sleep(for: .milliseconds(10))
                }
            }

            await nowProvider.update(unixSeconds: 1_000)
            await primaryTransport.yieldInboundBytes(
                try PrimaryRuntimeTestFixtures.encodeServerFrame(
                    .fusionBegin(PrimaryRuntimeTestFixtures.fusionBegin)
                )
            )
            try await LiveRuntimeTestHarness.withTimeout(.seconds(1)) {
                while (await covertTransport.recordedPreparationPlans).isEmpty {
                    try await Task.sleep(for: .milliseconds(10))
                }
            }

            await nowProvider.update(unixSeconds: 1_030)
            await primaryTransport.yieldInboundBytes(
                try PrimaryRuntimeTestFixtures.encodeServerFrame(
                    .startRound(PrimaryRuntimeTestFixtures.startRound)
                )
            )
            try await LiveRuntimeTestHarness.withTimeout(.seconds(1)) {
                while (await primaryTransport.recordedWrittenPayloads).count < 3 {
                    try await Task.sleep(for: .milliseconds(10))
                }
            }

            await nowProvider.update(unixSeconds: 1_032)
            await primaryTransport.yieldInboundBytes(
                try PrimaryRuntimeTestFixtures.encodeServerFrame(
                    .blindSignatureResponses(PrimaryRuntimeTestFixtures.blindSignatureResponses)
                )
            )

            await nowProvider.update(unixSeconds: 1_034)
            await primaryTransport.yieldInboundBytes(
                try PrimaryRuntimeTestFixtures.encodeServerFrame(
                    .allCommitments(PrimaryRuntimeTestFixtures.allCommitments)
                )
            )

            await covertTransport.enqueueResponse(
                try PrimaryRuntimeTestFixtures.encodeCovertResponsePayload(
                    PrimaryRuntimeTestFixtures.acknowledgement
                )
            )
            await nowProvider.update(unixSeconds: 1_035)
            try await LiveRuntimeTestHarness.withTimeout(.seconds(1)) {
                while (await covertTransport.recordedRequests).isEmpty {
                    try await Task.sleep(for: .milliseconds(10))
                }
            }
            #expect((await covertTransport.recordedRequests).count == 1)

            await nowProvider.update(unixSeconds: 1_040)
            await primaryTransport.yieldInboundBytes(
                try PrimaryRuntimeTestFixtures.encodeServerFrame(
                    .shareCovertComponents(PrimaryRuntimeTestFixtures.sharedComponents)
                )
            )
            try await LiveRuntimeTestHarness.withTimeout(.seconds(1)) {
                while (await transactionAssembler.recordedProposals).isEmpty {
                    try await Task.sleep(for: .milliseconds(10))
                }
            }
            #expect(await transactionAssembler.requestedRounds == [PrimaryRuntimeTestFixtures.roundIdentifier])
            try #require((await transactionAssembler.recordedProposals).count == 1)
            let finalizationTask = try #require(await driver.transactionFinalizationTask)

            #expect((await covertTransport.recordedRequests).count == 1)

            await driver.stop()
            let stoppedSnapshot = await driver.currentSnapshot
            #expect(stoppedSnapshot.lastError == nil)
            #expect(stoppedSnapshot.lastErrorSummary == nil)
            #expect(stoppedSnapshot.clientState.isConnected == false)
            #expect(stoppedSnapshot.clientState.round == nil)

            await transactionAssembler.releaseTransaction()
            await finalizationTask.value

            let finalSnapshot = await driver.currentSnapshot
            #expect(finalSnapshot == stoppedSnapshot)
            #expect((await covertTransport.recordedRequests).count == 1)

            let events = await eventSink.recordedSnapshots
            #expect(events.contains { $0.event.summary == "Primary channel disconnected" } == false)
            #expect(events.contains { $0.event.summary == "Transaction finalized; waiting for signature window" } == false)
            #expect(events.contains { $0.event.summary == "Submitting covert transaction signatures" } == false)

            await driver.stop()
        } catch {
            let heldTask = await driver.transactionFinalizationTask
            await driver.stop()
            await transactionAssembler.releaseTransaction()
            await heldTask?.value
            throw error
        }
    }
}

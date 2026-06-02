// LiveRuntimeDriverValidator+ValidationGroup10.swift

@testable import OpalFusion
import Foundation
import Network
import Testing

extension LiveRuntimeDriverValidator {
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
                        scenario.reservation.inputs[0].outpointTransactionHashBytes.reversed()
                    ),
                    previousOutputIndex: scenario.reservation.inputs[0].outpointIndex,
                    unlockingScript: [],
                    sequence: .max
                ),
            ],
            outputs: [
                .init(
                    amountSatoshis: scenario.reservation.outputs[0].amountSatoshis,
                    lockingScript: scenario.reservation.outputs[0].lockingScriptBytes
                )
            ],
            lockTime: 0
        )
        let proposal = OpalFusion.Host.TransactionFinalizationProposal(
            unsignedTransactionBytes: try unsignedTransaction.serialize()
        )

        let finalizedTransaction = try await assembler.finalizeTransaction(
            for: scenario.round.identifier!,
            proposal: proposal
        )
        let parsedTransaction = try OpalFusion.Execution.BCHTransaction.parse(
            finalizedTransaction.transactionBytes
        )

        #expect(parsedTransaction.inputs[0].unlockingScript.isEmpty)
        #expect(parsedTransaction.inputs[1].unlockingScript.isEmpty == false)
        #expect(parsedTransaction.inputs[1].unlockingScript[0] == 0x41)
    }

    @Test("Live runtime driver surfaces typed host policy finalization failures")
    func validateTypedHostPolicyFinalizationFailure() async throws {
        let primaryTransport = ScriptedPrimaryTransport()
        let covertTransport = ScriptedCovertTransport()
        let eventSink = RecordedHostEventSink()
        let nowProvider = ScriptedInstantClock(unixSeconds: 995)
        let transactionAssembler = BlockingTransactionAssembler(
            finalizedTransaction: PrimaryRuntimeTestFixtures.finalizedTransaction
        )
        let driver = makeFinalizationFailureDriver(
            primaryTransport: primaryTransport,
            covertTransport: covertTransport,
            transactionAssembler: transactionAssembler,
            eventSink: eventSink,
            nowProvider: nowProvider
        )

        await driver.start()
        try await driveScriptedRuntimeToPendingTransactionFinalization(
            primaryTransport: primaryTransport,
            covertTransport: covertTransport,
            nowProvider: nowProvider,
            transactionAssembler: transactionAssembler
        )

        let summary = "Host policy rejected coordinator input order"
        await transactionAssembler.failTransaction(
            OpalFusion.Host.TransactionFinalizationFailure.hostPolicyRejected(
                summary: summary
            )
        )

        let snapshot = try await LiveRuntimeTestHarness.withTimeout(.seconds(1)) {
            while true {
                let snapshot = await driver.currentSnapshot
                if snapshot.lastError == .hostRejected,
                   snapshot.lastErrorSummary == summary {
                    return snapshot
                }
                try await Task.sleep(for: .milliseconds(10))
            }
        }

        #expect(snapshot.clientState.round?.completionStatus == .hostRejected)
        #expect(snapshot.clientState.isConnected == false)

        let events = await eventSink.recordedSnapshots
        let lastEvent = try #require(events.last)
        #expect(lastEvent.event.summary == summary)
        #expect(lastEvent.event.isTerminal == true)
    }

    @Test("Live runtime driver sanitizes unknown transaction assembler failures")
    func validateUnknownTransactionAssemblerFailureIsSanitized() async throws {
        let primaryTransport = ScriptedPrimaryTransport()
        let covertTransport = ScriptedCovertTransport()
        let eventSink = RecordedHostEventSink()
        let nowProvider = ScriptedInstantClock(unixSeconds: 995)
        let transactionAssembler = BlockingTransactionAssembler(
            finalizedTransaction: PrimaryRuntimeTestFixtures.finalizedTransaction
        )
        let driver = makeFinalizationFailureDriver(
            primaryTransport: primaryTransport,
            covertTransport: covertTransport,
            transactionAssembler: transactionAssembler,
            eventSink: eventSink,
            nowProvider: nowProvider
        )

        await driver.start()
        try await driveScriptedRuntimeToPendingTransactionFinalization(
            primaryTransport: primaryTransport,
            covertTransport: covertTransport,
            nowProvider: nowProvider,
            transactionAssembler: transactionAssembler
        )

        await transactionAssembler.failTransaction(
            LiveRuntimeTestHarnessError.signingInputNotFound
        )

        let expectedSummary = "Host transaction finalization failed"
        let snapshot = try await LiveRuntimeTestHarness.withTimeout(.seconds(1)) {
            while true {
                let snapshot = await driver.currentSnapshot
                if snapshot.lastError == .notImplemented,
                   snapshot.lastErrorSummary == expectedSummary {
                    return snapshot
                }
                try await Task.sleep(for: .milliseconds(10))
            }
        }

        #expect(snapshot.clientState.round?.completionStatus == .hostRejected)
        #expect(snapshot.clientState.isConnected == false)

        let events = await eventSink.recordedSnapshots
        let lastEvent = try #require(events.last)
        #expect(lastEvent.event.summary == expectedSummary)
        #expect(lastEvent.event.isTerminal == true)
    }
}

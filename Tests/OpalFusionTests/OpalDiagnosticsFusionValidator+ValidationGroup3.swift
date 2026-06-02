// OpalDiagnosticsFusionValidator+ValidationGroup3.swift

@testable import OpalFusion
import Foundation
import Network
import OpalCrypto
import OpalDiagnostics
import Testing

extension OpalDiagnosticsFusionValidator {
    @Test("Driver-level primary transport failures are not duplicated by session state")
    func driverLevelPrimaryTransportFailuresAreNotDuplicatedBySessionState() throws {
        try withDiagnosticsCapture {
            var session = PrimaryRuntimeTestFixtures.makeSession()
            let error = OpalFusion.Runtime.LiveTransportError.primaryConnectionNotReady

            OpalDiagnostics.logger(category: .fusionTransport).record(
                event: .transportError,
                level: .opalFusionDefault(for: .transportError),
                fields: [
                    .operation("primary_read"),
                    .errorCode(OpalDiagnostics.ErrorCode.primaryConnectionNotReady),
                    .errorType(error),
                    .errorMessage(String(describing: error))
                ]
            )
            _ = session.apply(
                input: .diagnosedPrimaryTransportFailed(summary: "Primary read failed"),
                now: PrimaryRuntimeTestFixtures.instant(1_003)
            )

            let records = OpalDiagnostics.recentRecords(
                matching: .init(event: OpalDiagnostics.Event.transportError)
            )
            #expect(records.count == 1)
            let record = try #require(records.first)
            #expect(findField("operation", in: record)?.value == "primary_read")
            #expect(findField("error_code", in: record)?.value == "primary_connection_not_ready")
        }
    }

    @Test("Primary read failures inside a round keep the round trace ID")
    func validatePrimaryReadFailuresInsideRoundKeepTraceID() async throws {
        try await withDiagnosticsCapture {
            let primaryTransport = ScriptedPrimaryTransport()
            let covertTransport = ScriptedCovertTransport()
            let nowProvider = ScriptedInstantClock(unixSeconds: 995)
            let driver = makeDiagnosticsRuntimeDriver(
                primaryTransport: primaryTransport,
                covertTransport: covertTransport,
                nowProvider: nowProvider
            )

            await driver.start()
            try await waitForWrittenPayloadCount(primaryTransport, count: 1)
            await nowProvider.update(unixSeconds: 996)
            await primaryTransport.yieldInboundBytes(
                try PrimaryRuntimeTestFixtures.encodeServerFrame(
                    .serverHello(PrimaryRuntimeTestFixtures.serverHello)
                )
            )
            try await waitForWrittenPayloadCount(primaryTransport, count: 2)
            await nowProvider.update(unixSeconds: 1_000)
            await primaryTransport.yieldInboundBytes(
                try PrimaryRuntimeTestFixtures.encodeServerFrame(
                    .fusionBegin(PrimaryRuntimeTestFixtures.fusionBegin)
                )
            )
            _ = try await waitForDiagnosticRecord(
                named: OpalDiagnostics.Event.covertPrepareSucceeded
            )
            await nowProvider.update(unixSeconds: 1_030)
            await primaryTransport.yieldInboundBytes(
                try PrimaryRuntimeTestFixtures.encodeServerFrame(
                    .startRound(PrimaryRuntimeTestFixtures.startRound)
                )
            )

            let roundRecord = try await waitForDiagnosticRecord(
                named: OpalDiagnostics.Event.roundEntered
            )
            #expect(roundRecord.traceID == Self.primaryRoundTraceID)

            OpalDiagnostics.clearRecentRecords()
            await primaryTransport.finishInbound(
                throwing: LiveRuntimeTestHarnessError.inboundStreamClosed
            )

            let record = try await waitForDiagnosticRecord(
                named: OpalDiagnostics.Event.transportError,
                matching: { $0.traceID == Self.primaryRoundTraceID }
            )
            #expect(record.traceID == Self.primaryRoundTraceID)
            #expect(findField("operation", in: record)?.value == "primary_read")

            await driver.stop()
        }
    }

    @Test("Covert preparation failures inside a round keep the round trace ID")
    func validateCovertPreparationFailuresInsideRoundKeepTraceID() async throws {
        try await withDiagnosticsCapture {
            let primaryTransport = ScriptedPrimaryTransport()
            let covertTransport = BlockingCovertTransport(blocksPrepare: true)
            let nowProvider = ScriptedInstantClock(unixSeconds: 995)
            let driver = makeDiagnosticsRuntimeDriver(
                primaryTransport: primaryTransport,
                covertTransport: covertTransport,
                nowProvider: nowProvider
            )

            await driver.start()
            try await waitForWrittenPayloadCount(primaryTransport, count: 1)
            await nowProvider.update(unixSeconds: 996)
            await primaryTransport.yieldInboundBytes(
                try PrimaryRuntimeTestFixtures.encodeServerFrame(
                    .serverHello(PrimaryRuntimeTestFixtures.serverHello)
                )
            )
            try await waitForWrittenPayloadCount(primaryTransport, count: 2)
            await nowProvider.update(unixSeconds: 1_000)
            await primaryTransport.yieldInboundBytes(
                try PrimaryRuntimeTestFixtures.encodeServerFrame(
                    .fusionBegin(PrimaryRuntimeTestFixtures.fusionBegin)
                )
            )
            try await waitForCovertPreparationPlan(covertTransport)
            await nowProvider.update(unixSeconds: 1_030)
            await primaryTransport.yieldInboundBytes(
                try PrimaryRuntimeTestFixtures.encodeServerFrame(
                    .startRound(PrimaryRuntimeTestFixtures.startRound)
                )
            )
            let roundRecord = try await waitForDiagnosticRecord(
                named: OpalDiagnostics.Event.roundEntered
            )
            #expect(roundRecord.traceID == Self.primaryRoundTraceID)

            OpalDiagnostics.clearRecentRecords()
            await covertTransport.failPreparation(LiveRuntimeTestHarnessError.inboundStreamClosed)

            let record = try await waitForDiagnosticRecord(
                named: OpalDiagnostics.Event.covertPrepareFailed,
                matching: { $0.traceID == Self.primaryRoundTraceID }
            )
            #expect(record.traceID == Self.primaryRoundTraceID)
            #expect(findField("operation", in: record)?.value == "covert_prepare")

            await driver.stop()
        }
    }
}

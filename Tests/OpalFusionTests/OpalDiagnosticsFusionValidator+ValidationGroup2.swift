// OpalDiagnosticsFusionValidator+ValidationGroup2.swift

@testable import OpalFusion
import Foundation
import Network
import OpalCrypto
import OpalDiagnostics
import Testing

extension OpalDiagnosticsFusionValidator {
    @Test("Covert request timeouts use the resolved round trace ID")
    func validateCovertRequestTimeoutsUseResolvedRoundTraceID() throws {
        try withDiagnosticsCapture {
            var session = makeDispatchedCovertSession(
                roundIdentifier: PrimaryRuntimeTestFixtures.roundIdentifier
            )

            OpalDiagnostics.clearRecentRecords()
            let effects = session.apply(
                input: .clockAdvanced,
                now: PrimaryRuntimeTestFixtures.instant(10_000)
            )

            #expect(effects == [.emitTransportFailure(summary: "Covert request timed out")])
            let record = try #require(findDiagnosticRecord(named: OpalDiagnostics.Event.covertRequestFailed))
            #expect(record.traceID == Self.primaryRoundTraceID)
            #expect(findField("operation", in: record)?.value == "covert_transport")
            #expect(findField("error_code", in: record)?.value == "transport_unavailable")
        }
    }

    @Test("Round events use the round identifier as trace ID")
    func validateRoundEventsUseRoundIdentifierTraceID() throws {
        try withDiagnosticsCapture {
            var session = PrimaryRuntimeTestFixtures.makeSession()
            try PrimaryRuntimeTestFixtures.driveThroughWarmup(session: &session)

            OpalDiagnostics.clearRecentRecords()
            _ = session.apply(
                input: .receivedPrimaryBytes(
                    try PrimaryRuntimeTestFixtures.encodeServerFrame(
                        .startRound(PrimaryRuntimeTestFixtures.startRound)
                    )
                ),
                now: PrimaryRuntimeTestFixtures.instant(1_030)
            )

            let record = try #require(findDiagnosticRecord(named: OpalDiagnostics.Event.roundEntered))
            #expect(record.traceID == Self.primaryRoundTraceID)
            #expect(findField("phase", in: record)?.value == OpalFusion.Round.Phase.registeringInputs.rawValue)
            #expect(findField("message_kind", in: record)?.value == "StartRound")
        }
    }

    @Test("Transaction finalization rejections record round trace and redacted failure")
    func validateTransactionFinalizationRejectionsRecordDiagnostics() throws {
        try withDiagnosticsCapture {
            var session = PrimaryRuntimeTestFixtures.makeSession()
            try PrimaryRuntimeTestFixtures.driveThroughStartRound(session: &session)

            OpalDiagnostics.clearRecentRecords()
            _ = session.apply(
                input: .transactionFinalizationRejected(
                    .hostPolicyRejected(summary: "wallet raw transaction material")
                ),
                now: PrimaryRuntimeTestFixtures.instant(1_040)
            )

            let record = try #require(findDiagnosticRecord(named: OpalDiagnostics.Event.transactionFinalizationFailed))
            #expect(record.category == OpalDiagnostics.Category.fusionTransaction)
            #expect(record.traceID == Self.primaryRoundTraceID)
            #expect(findField("error_code", in: record)?.value == "host_policy_rejected")
            #expect(findField("error_message", in: record)?.value == "<redacted>")
            #expect(record.fields.contains { $0.value.contains("wallet raw transaction material") } == false)
            #expect(
                OpalDiagnostics.recentRecords(
                    matching: .init(event: OpalDiagnostics.Event.roundFailed)
                ).count == 1
            )
        }
    }

    @Test("Round completion emits one completed diagnostics record")
    func validateRoundCompletionEmitsOneCompletedDiagnosticsRecord() throws {
        try withDiagnosticsCapture {
            var session = PrimaryRuntimeTestFixtures.makeSession()
            try PrimaryRuntimeTestFixtures.driveToAwaitingResult(session: &session)

            OpalDiagnostics.clearRecentRecords()
            _ = session.apply(
                input: .receivedPrimaryBytes(
                    try PrimaryRuntimeTestFixtures.encodeServerFrame(
                        .fusionResult(PrimaryRuntimeTestFixtures.successResult)
                    )
                ),
                now: PrimaryRuntimeTestFixtures.instant(1_055)
            )

            let records = OpalDiagnostics.recentRecords(
                matching: .init(event: OpalDiagnostics.Event.roundCompleted)
            )
            #expect(records.count == 1)
            let record = try #require(records.first)
            #expect(record.traceID == Self.primaryRoundTraceID)
            #expect(findField("settlement_state", in: record)?.value == OpalFusion.Round.CompletionStatus.success.rawValue)
        }
    }

    @Test("Pre-round primary disconnect failure records a safe error code")
    func validatePreRoundPrimaryDisconnectFailureRecordsSafeErrorCode() throws {
        try withDiagnosticsCapture {
            var session = PrimaryRuntimeTestFixtures.makeSession()
            _ = session.apply(input: .connected, now: PrimaryRuntimeTestFixtures.instant(995))

            OpalDiagnostics.clearRecentRecords()
            _ = session.apply(input: .disconnected, now: PrimaryRuntimeTestFixtures.instant(996))

            let record = try #require(findDiagnosticRecord(named: OpalDiagnostics.Event.roundFailed))
            #expect(findField("operation", in: record)?.value == "host_event")
            #expect(findField("error_code", in: record)?.value == "transport_unavailable")
            #expect(findField("error_message", in: record)?.value == "<redacted>")
        }
    }

    @Test("Primary connect failure records one lifecycle failure event")
    func validatePrimaryConnectFailureRecordsOneLifecycleFailureEvent() async throws {
        try await withDiagnosticsCapture {
            let driver = OpalFusion.Runtime.LiveRuntimeDriver(
                configuration: PrimaryRuntimeTestFixtures.configuration,
                genesisHash: PrimaryRuntimeTestFixtures.clientHello.genesisHash,
                joinPools: PrimaryRuntimeTestFixtures.joinPools,
                participantReservationSource: HostParticipantReservationSourceAdapter(
                    participantInputs: [PrimaryRuntimeTestFixtures.participantInput]
                ),
                transactionAssembler: HostTransactionAssemblerAdapter(
                    finalizedTransaction: PrimaryRuntimeTestFixtures.finalizedTransaction
                ),
                primaryTransport: ScriptedPrimaryTransport(
                    connectError: NSError(domain: "OpalDiagnosticsFusionValidator", code: 1)
                )
            )

            await driver.start()

            let records = OpalDiagnostics.recentRecords(
                matching: .init(event: OpalDiagnostics.Event.primaryConnectFailed)
            )
            #expect(records.count == 1)
            let record = try #require(records.first)
            #expect(findField("operation", in: record)?.value == "primary_connect")
            #expect(findField("error_code", in: record)?.value == "unknown")
            #expect(findField("error_message", in: record)?.value == "<redacted>")
        }
    }

    @Test("Driver-level covert request failures are not duplicated by session state")
    func driverLevelCovertRequestFailuresAreNotDuplicatedBySessionState() throws {
        try withDiagnosticsCapture {
            var session = makeDispatchedCovertSession()

            OpalDiagnostics.clearRecentRecords()
            let error = OpalFusion.Runtime.LiveTransportError.unexpectedHTTPStatus(503)
            OpalDiagnostics.logger(category: .fusionCovert).record(
                event: .covertRequestFailed,
                level: .opalFusionDefault(for: .covertRequestFailed),
                traceID: .opalFusionRound(PrimaryRuntimeTestFixtures.covertEndpointContext.roundIdentifier),
                fields: [
                    .operation("covert_request"),
                    .errorCode(OpalDiagnostics.ErrorCode.unexpectedHTTPStatus),
                    .errorType(error),
                    .errorMessage(String(describing: error))
                ]
            )
            _ = session.apply(
                input: .covertRequestFailed(summary: "Covert request failed"),
                now: PrimaryRuntimeTestFixtures.instant(1_003)
            )

            let records = OpalDiagnostics.recentRecords(
                matching: .init(event: OpalDiagnostics.Event.covertRequestFailed)
            )
            #expect(records.count == 1)
            let record = try #require(records.first)
            #expect(findField("operation", in: record)?.value == "covert_request")
            #expect(findField("error_code", in: record)?.value == "unexpected_http_status")
        }
    }
}

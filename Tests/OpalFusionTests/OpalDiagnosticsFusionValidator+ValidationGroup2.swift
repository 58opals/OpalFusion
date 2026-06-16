// OpalDiagnosticsFusionValidator+ValidationGroup2.swift

@testable import OpalFusion
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
            #expect(findField("host_response_class", in: record)?.value == "transaction_finalization_rejected")
            #expect(findField("validation_branch", in: record)?.value == "transaction_finalization")
            #expect(findField("reason_code", in: record)?.value == "host_policy_rejected")
            #expect(findField("error_message", in: record)?.value == "<redacted>")
            #expect(record.fields.contains { $0.value.contains("wallet raw transaction material") } == false)
            let roundRecord = try #require(findDiagnosticRecord(named: OpalDiagnostics.Event.roundFailed))
            #expect(findField("operation", in: roundRecord)?.value == "round_failure")
            #expect(findField("settlement_state", in: roundRecord)?.value == OpalFusion.Round.CompletionStatus.hostRejected.rawValue)
            #expect(findField("host_response_class", in: roundRecord)?.value == "transaction_finalization_rejected")
            #expect(findField("validation_branch", in: roundRecord)?.value == "transaction_finalization")
            #expect(findField("reason_code", in: roundRecord)?.value == "host_policy_rejected")
            #expect(findField("error_code", in: roundRecord)?.value == "host_policy_rejected")
            #expect(findField("error_message", in: roundRecord)?.value == "<redacted>")
            #expect(roundRecord.fields.contains { $0.value.contains("wallet raw transaction material") } == false)
        }
    }

    @Test("Participant reservation rejections record structured host-safe diagnostics")
    func validateParticipantReservationRejectionsRecordStructuredDiagnostics() throws {
        try withDiagnosticsCapture {
            var session = PrimaryRuntimeTestFixtures.makeSession()
            try PrimaryRuntimeTestFixtures.driveThroughStartRound(session: &session)

            OpalDiagnostics.clearRecentRecords()
            _ = session.apply(
                input: .participantReservationRejected(
                    .hostPolicyRejected(
                        reason: .noEligibleInputs,
                        summary: "wallet address and outpoint material"
                    )
                ),
                now: PrimaryRuntimeTestFixtures.instant(1_031)
            )

            let record = try #require(findDiagnosticRecord(named: OpalDiagnostics.Event.roundFailed))
            #expect(record.category == OpalDiagnostics.Category.fusionRound)
            #expect(record.traceID == Self.primaryRoundTraceID)
            #expect(findField("operation", in: record)?.value == "round_failure")
            #expect(findField("phase", in: record)?.value == OpalFusion.Round.Phase.completed.rawValue)
            #expect(findField("round_state", in: record)?.value == "terminal")
            #expect(findField("settlement_state", in: record)?.value == OpalFusion.Round.CompletionStatus.hostRejected.rawValue)
            #expect(findField("message_kind", in: record)?.value == "StartRound")
            #expect(findField("host_response_class", in: record)?.value == "participant_reservation_rejected")
            #expect(findField("validation_branch", in: record)?.value == "participant_reservation")
            #expect(findField("reason_code", in: record)?.value == "no_eligible_inputs")
            #expect(findField("error_code", in: record)?.value == "participant_reservation_host_policy_rejected")
            #expect(findField("error_message", in: record)?.value == "<redacted>")
            #expect(record.fields.contains { $0.value.contains("wallet address") } == false)
        }
    }

    @Test("Coordinator server failures record sanitized protocol identifiers")
    func validateCoordinatorServerFailuresRecordSanitizedProtocolIdentifiers() throws {
        try withDiagnosticsCapture {
            var session = PrimaryRuntimeTestFixtures.makeSession()
            _ = session.apply(input: .connected, now: PrimaryRuntimeTestFixtures.instant(995))

            OpalDiagnostics.clearRecentRecords()
            _ = session.apply(
                input: .receivedPrimaryBytes(
                    try PrimaryRuntimeTestFixtures.encodeServerFrame(
                        .serverFailure(.init(message: "Coordinator rejected JoinPools for wallet address secret"))
                    )
                ),
                now: PrimaryRuntimeTestFixtures.instant(996)
            )

            let receivedRecord = try #require(findDiagnosticRecord(named: OpalDiagnostics.Event.primaryMessageReceived))
            #expect(findField("message_kind", in: receivedRecord)?.value == "ServerFailure")
            #expect(findField("protocol_error_identifier", in: receivedRecord)?.value == "server_failure_join_rejected")
            #expect(findField("error_message", in: receivedRecord)?.value == "<redacted>")
            #expect(receivedRecord.fields.contains { $0.value.contains("wallet address") } == false)

            let failedRecord = try #require(findDiagnosticRecord(named: OpalDiagnostics.Event.roundFailed))
            #expect(findField("message_kind", in: failedRecord)?.value == "ServerFailure")
            #expect(findField("protocol_error_identifier", in: failedRecord)?.value == "server_failure_join_rejected")
            #expect(findField("error_code", in: failedRecord)?.value == "coordinator_rejected")
            #expect(failedRecord.fields.contains { $0.value.contains("wallet address") } == false)
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

}

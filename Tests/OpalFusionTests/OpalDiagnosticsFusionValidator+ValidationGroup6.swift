// OpalDiagnosticsFusionValidator+ValidationGroup6.swift

@testable import OpalFusion
import Foundation
import OpalDiagnostics
import Testing

extension OpalDiagnosticsFusionValidator {
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

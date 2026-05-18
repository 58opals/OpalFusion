// OpalDiagnosticsFusionValidator.swift

@testable import OpalFusion
import Foundation
import Network
import OpalCrypto
import OpalDiagnostics
import SwiftProtobuf
import Testing

@Suite(.serialized)
struct OpalDiagnosticsFusionValidator {
    @Test("OpalDiagnostics catalog exposes stable typed values")
    func validateOpalDiagnosticsCatalogExposesStableTypedValues() {
        let category: OpalDiagnostics.Category = OpalDiagnostics.Category.fusionPrimary
        let event: OpalDiagnostics.Event = OpalDiagnostics.Event.primaryMessageDecodeFailed
        let level: OpalDiagnostics.Level = .error

        #expect(category == OpalDiagnostics.Category.fusionPrimary)
        #expect(event == OpalDiagnostics.Event.primaryMessageDecodeFailed)
        #expect(level == .error)
        #expect(OpalDiagnostics.Event.blameProofValidationFailed.rawValue == "opalfusion.blame.proof_validation.failed")
    }

    @Test("Fusion category filter includes subcategories and excludes unrelated packages")
    func validateFusionCategoryFilterIncludesSubcategories() {
        withDiagnosticsCapture {
            OpalDiagnostics.logger(category: .fusionPrimary).record(
                event: .primaryMessageDecodeFailed,
                level: .opalFusionDefault(for: .primaryMessageDecodeFailed),
                fields: [
                    .operation("primary_decode")
                ]
            )
            OpalDiagnostics.logger(category: .crypto).record(
                event: "opalcrypto.filtered",
                level: .debug
            )

            #expect(OpalDiagnostics.recentRecords.map(\.event) == [
                OpalDiagnostics.Event.primaryMessageDecodeFailed
            ])
            #expect(OpalDiagnostics.recentRecords.map(\.category) == [
                OpalDiagnostics.Category.fusionPrimary
            ])
        }
    }

    @Test("Primary decode failures record public counts and redacted errors")
    func validatePrimaryDecodeFailuresRecordRedactedDiagnostics() throws {
        try withDiagnosticsCapture {
            var session = PrimaryRuntimeTestFixtures.makeSession()
            _ = session.apply(input: .connected, now: PrimaryRuntimeTestFixtures.instant(995))
            let malformedFrame = try OpalFusion.Wire.PrimaryFrameEncoder(
                configuration: PrimaryRuntimeTestFixtures.baseline.framing
            )
            .encode(payload: [0x08])

            OpalDiagnostics.clearRecentRecords()
            _ = session.apply(
                input: .receivedPrimaryBytes(malformedFrame),
                now: PrimaryRuntimeTestFixtures.instant(996)
            )

            let record = try #require(findDiagnosticRecord(named: OpalDiagnostics.Event.primaryMessageDecodeFailed))
            #expect(record.category == OpalDiagnostics.Category.fusionPrimary)
            #expect(findField("operation", in: record)?.value == "primary_inbound_decode")
            #expect(findField("frame_byte_count", in: record)?.value == "\(malformedFrame.count)")
            #expect(findField("error_message", in: record)?.value == "<redacted>")
            #expect(record.fields.contains { $0.value.contains("FF") } == false)
        }
    }

    @Test("Invalid configuration diagnostics preserve the safe configuration error code")
    func validateInvalidConfigurationDiagnosticsPreserveErrorCode() throws {
        try withDiagnosticsCapture {
            var session = PrimaryRuntimeTestFixtures.makeSession()

            _ = session.apply(
                input: .invalidConfiguration(summary: "server secret material rejected"),
                now: PrimaryRuntimeTestFixtures.instant(994)
            )

            let record = try #require(findDiagnosticRecord(named: OpalDiagnostics.Event.transportError))
            #expect(findField("operation", in: record)?.value == "primary_runtime")
            #expect(findField("error_code", in: record)?.value == "invalid_configuration")
            #expect(findField("error_message", in: record)?.value == "<redacted>")
            #expect(record.fields.contains { $0.value.contains("server secret material") } == false)
        }
    }

    @Test("Primary network setup states use primary connection events")
    func validatePrimaryNetworkSetupStatesUsePrimaryConnectionEvents() {
        #expect(
            OpalFusion.Runtime.NetworkPrimaryConnection.makeDiagnosticsEvent(for: .setup) ==
                OpalDiagnostics.Event.primaryConnectionPreparing
        )
        #expect(
            OpalFusion.Runtime.NetworkPrimaryConnection.makeDiagnosticsEvent(for: .preparing) ==
                OpalDiagnostics.Event.primaryConnectionPreparing
        )
    }

    @Test("Covert response decode failures record redacted diagnostics")
    func validateCovertResponseDecodeFailuresRecordRedactedDiagnostics() throws {
        try withDiagnosticsCapture {
            var session = PrimaryRuntimeTestFixtures.makeCovertSession()
            _ = session.apply(
                input: .prepare(endpointContext: PrimaryRuntimeTestFixtures.covertEndpointContext),
                now: PrimaryRuntimeTestFixtures.instant(1_000)
            )
            _ = session.apply(
                input: .covertPrepared,
                now: PrimaryRuntimeTestFixtures.instant(1_001)
            )
            _ = session.apply(
                input: .enqueue(message: PrimaryRuntimeTestFixtures.pingMessage),
                now: PrimaryRuntimeTestFixtures.instant(1_002)
            )

            OpalDiagnostics.clearRecentRecords()
            let effects = session.apply(
                input: .covertResponseBytesReceived([0xFF]),
                now: PrimaryRuntimeTestFixtures.instant(1_003)
            )

            #expect(effects == [.emitProtocolFailure(summary: "Covert response decode failed")])
            let record = try #require(findDiagnosticRecord(named: OpalDiagnostics.Event.covertResponseDecodeFailed))
            #expect(record.category == OpalDiagnostics.Category.fusionCovert)
            #expect(findField("operation", in: record)?.value == "covert_response_decode")
            #expect(findField("payload_byte_count", in: record)?.value == "1")
            #expect(findField("error_message", in: record)?.value == "<redacted>")
        }
    }

    @Test("Covert preparation timeouts record prepare failure diagnostics")
    func covertPreparationTimeoutsRecordPrepareFailureDiagnostics() throws {
        try withDiagnosticsCapture {
            var session = PrimaryRuntimeTestFixtures.makeCovertSession()
            _ = session.apply(
                input: .prepare(endpointContext: PrimaryRuntimeTestFixtures.covertEndpointContext),
                now: PrimaryRuntimeTestFixtures.instant(1_000)
            )

            OpalDiagnostics.clearRecentRecords()
            let effects = session.apply(
                input: .clockAdvanced,
                now: PrimaryRuntimeTestFixtures.instant(10_000)
            )

            #expect(effects == [.emitTransportFailure(summary: "Covert endpoint preparation timed out")])
            let record = try #require(findDiagnosticRecord(named: OpalDiagnostics.Event.covertPrepareFailed))
            #expect(findField("operation", in: record)?.value == "covert_prepare")
            #expect(findField("error_code", in: record)?.value == "transport_unavailable")
            #expect(
                OpalDiagnostics.recentRecords(
                    matching: .init(event: OpalDiagnostics.Event.covertRequestFailed)
                ).isEmpty
            )
        }
    }

    @Test("Round events use the round identifier as trace ID")
    func roundEventsUseRoundIdentifierTraceID() throws {
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
            #expect(record.traceID == OpalDiagnostics.TraceID(rawValue: PrimaryRuntimeTestFixtures.roundIdentifier.rawValue))
            #expect(findField("phase", in: record)?.value == OpalFusion.Round.Phase.registeringInputs.rawValue)
            #expect(findField("message_kind", in: record)?.value == "StartRound")
        }
    }

    @Test("Transaction finalization rejections record round trace and redacted failure")
    func transactionFinalizationRejectionsRecordDiagnostics() throws {
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
            #expect(record.traceID == OpalDiagnostics.TraceID(rawValue: PrimaryRuntimeTestFixtures.roundIdentifier.rawValue))
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
    func roundCompletionEmitsOneCompletedDiagnosticsRecord() throws {
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
            #expect(records.first?.traceID == OpalDiagnostics.TraceID(rawValue: PrimaryRuntimeTestFixtures.roundIdentifier.rawValue))
            #expect(findField("settlement_state", in: try #require(records.first))?.value == OpalFusion.Round.CompletionStatus.success.rawValue)
        }
    }

    @Test("Pre-round primary disconnect failure records a safe error code")
    func preRoundPrimaryDisconnectFailureRecordsSafeErrorCode() throws {
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
    func primaryConnectFailureRecordsOneLifecycleFailureEvent() async throws {
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
            var session = PrimaryRuntimeTestFixtures.makeCovertSession()
            _ = session.apply(
                input: .prepare(endpointContext: PrimaryRuntimeTestFixtures.covertEndpointContext),
                now: PrimaryRuntimeTestFixtures.instant(1_000)
            )
            _ = session.apply(input: .covertPrepared, now: PrimaryRuntimeTestFixtures.instant(1_001))
            _ = session.apply(
                input: .enqueue(message: PrimaryRuntimeTestFixtures.pingMessage),
                now: PrimaryRuntimeTestFixtures.instant(1_002)
            )

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
    func primaryReadFailuresInsideRoundKeepTraceID() async throws {
        try await withDiagnosticsCapture {
            let primaryTransport = ScriptedPrimaryTransport()
            let covertTransport = ScriptedCovertTransport()
            let nowProvider = ScriptedInstantClock(unixSeconds: 995)
            let driver = OpalFusion.Runtime.LiveRuntimeDriver(
                configuration: PrimaryRuntimeTestFixtures.configuration,
                genesisHash: PrimaryRuntimeTestFixtures.clientHello.genesisHash,
                joinPools: PrimaryRuntimeTestFixtures.joinPools,
                workflow: PrimaryRuntimeTestFixtures.workflow,
                participantReservationSource: HostParticipantReservationSourceAdapter(
                    participantInputs: [PrimaryRuntimeTestFixtures.participantInput]
                ),
                transactionAssembler: HostTransactionAssemblerAdapter(
                    finalizedTransaction: PrimaryRuntimeTestFixtures.finalizedTransaction
                ),
                nowProvider: { await nowProvider.now() },
                primaryTransport: primaryTransport,
                covertTransport: covertTransport
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
            let roundTraceID = OpalDiagnostics.TraceID(
                rawValue: PrimaryRuntimeTestFixtures.roundIdentifier.rawValue
            )
            #expect(roundRecord.traceID == roundTraceID)

            OpalDiagnostics.clearRecentRecords()
            await primaryTransport.finishInbound(
                throwing: LiveRuntimeTestSupportError.inboundStreamClosed
            )

            let record = try await waitForDiagnosticRecord(
                named: OpalDiagnostics.Event.transportError
            )
            #expect(record.traceID == roundTraceID)
            #expect(findField("operation", in: record)?.value == "primary_read")

            await driver.stop()
        }
    }

    @Test("Proof validation failures emit redacted blame diagnostics")
    func proofValidationFailuresEmitRedactedDiagnostics() throws {
        try withDiagnosticsCapture {
            var scenario = try ProductionWorkflowTestFixtures.makeScenario()
            let playerCommit = try scenario.buildPlayerCommit()
            let extraInputComponent = try scenario.makeExternalInputComponent()

            try scenario.useSharedRound(
                allCommitments: playerCommit.initialCommitments + [extraInputComponent.initialCommitment],
                serializedComponents: scenario.localSerializedComponents() + [extraInputComponent.serializedComponent]
            )
            _ = try scenario.workflow.buildMyProofsList(round: &scenario.round)

            guard let playerCommitMaterial = scenario.round.executionMaterial.playerCommitMaterial,
                  let sharedRoundMaterial = scenario.round.executionMaterial.sharedRoundMaterial else {
                Issue.record("Expected shared production workflow material")
                return
            }

            let destinationComponent = playerCommitMaterial.componentsByCommitmentOrder[0]
            let invalidEncryptedProof = try Array(
                OpalCrypto.Communication.encrypt(
                    message: Data([0x00]),
                    recipientPublicKey: OpalCrypto.Secp256k1.PublicKey(
                        rawRepresentation: Data(
                            destinationComponent.initialCommitment.communicationPublicKey
                        )
                    )
                ).rawRepresentation
            )
            scenario.round.fusionResult = .init(
                isSuccess: false,
                transactionSignatures: [],
                badComponentIndices: []
            )
            scenario.round.theirProofsList = .init(
                proofs: [
                    .init(
                        encryptedProof: invalidEncryptedProof,
                        sourceCommitmentIndex: UInt32(sharedRoundMaterial.allCommitmentBytes.count - 1),
                        destinationKeyIndex: 0
                    )
                ]
            )

            OpalDiagnostics.clearRecentRecords()
            let blames = try scenario.workflow.buildBlames(round: &scenario.round)

            #expect(blames.blames.first?.reason == "proof decode failed")
            let record = try #require(findDiagnosticRecord(named: OpalDiagnostics.Event.blameProofValidationFailed))
            #expect(record.category == OpalDiagnostics.Category.fusionBlame)
            #expect(record.traceID == OpalDiagnostics.TraceID(rawValue: scenario.round.identifier!.rawValue))
            #expect(findField("error_code", in: record)?.value == "relayed_proof_validation_failed")
            #expect(findField("error_message", in: record)?.value == "<redacted>")
            #expect(record.fields.contains { $0.value.contains("proof decode failed") } == false)
        }
    }

    @Test("Reconnect scheduling emits OpalDiagnostics")
    func reconnectSchedulingEmitsDiagnostics() async throws {
        try await withDiagnosticsCapture {
            let transportFactories = SessionTransportFactoryRecorder()
            let session = OpalFusion.Client.Session(
                configuration: PrimaryRuntimeTestFixtures.configuration,
                genesisHash: PrimaryRuntimeTestFixtures.clientHello.genesisHash,
                joinPools: PrimaryRuntimeTestFixtures.joinPools,
                participantReservationSource: HostParticipantReservationSourceAdapter(
                    participantInputs: [PrimaryRuntimeTestFixtures.participantInput]
                ),
                transactionAssembler: HostTransactionAssemblerAdapter(
                    finalizedTransaction: PrimaryRuntimeTestFixtures.finalizedTransaction
                ),
                reconnectPolicy: Self.fastReconnectPolicy,
                primaryTransportFactory: { await transportFactories.makePrimary() },
                covertTransportFactory: { await transportFactories.makeCovert() }
            )

            await session.start()
            let firstTransport = try await waitForPrimaryTransport(
                transportFactories,
                at: 0
            )
            try await waitForWrittenPayloadCount(firstTransport, count: 1)
            await firstTransport.finishInbound()

            let record = try await waitForDiagnosticRecord(named: .primaryRetryScheduled)
            #expect(findField("retry_attempt", in: record)?.value == "1")
            #expect(findField("retry_delay_ms", in: record)?.value == "10")

            await session.stop()
        }
    }

    private static let fastReconnectPolicy = OpalFusion.Client.ReconnectPolicy(
        initialDelay: .milliseconds(10),
        maximumDelay: .milliseconds(10),
        multiplier: 1,
        maximumAttempts: 1
    )

    private static let diagnosticsConfiguration = OpalDiagnostics.Configuration(
        minimumLevel: .debug,
        categoryFilter: .enabledIncludingSubcategories([OpalDiagnostics.Category.fusion]),
        bufferPolicy: .enabled(capacity: 1_000)
    )

    private func withDiagnosticsCapture<Success>(
        _ operation: () throws -> Success
    ) rethrows -> Success {
        try OpalDiagnostics.withConfiguration(Self.diagnosticsConfiguration) {
            OpalDiagnostics.clearRecentRecords()
            return try operation()
        }
    }

    private func withDiagnosticsCapture<Success>(
        _ operation: () async throws -> Success
    ) async rethrows -> Success {
        try await OpalDiagnostics.withConfiguration(Self.diagnosticsConfiguration) {
            OpalDiagnostics.clearRecentRecords()
            return try await operation()
        }
    }

    private func findDiagnosticRecord(
        named event: OpalDiagnostics.Event
    ) -> OpalDiagnostics.Record? {
        OpalDiagnostics.recentRecords(matching: .init(event: event)).first
    }

    private func findField(
        _ name: String,
        in record: OpalDiagnostics.Record
    ) -> OpalDiagnostics.Field? {
        record.fields.first { $0.name == name }
    }

    private func waitForDiagnosticRecord(
        named event: OpalDiagnostics.Event
    ) async throws -> OpalDiagnostics.Record {
        try await LiveRuntimeTestSupport.withTimeout(.seconds(1)) {
            while true {
                if let record = findDiagnosticRecord(named: event) {
                    return record
                }

                try await Task.sleep(for: .milliseconds(10))
            }
        }
    }

    private func waitForPrimaryTransport(
        _ transportFactories: SessionTransportFactoryRecorder,
        at index: Int
    ) async throws -> ScriptedPrimaryTransport {
        try await LiveRuntimeTestSupport.withTimeout(.seconds(1)) {
            while true {
                if let transport = await transportFactories.primaryTransport(at: index) {
                    return transport
                }

                try await Task.sleep(for: .milliseconds(10))
            }
        }
    }

    private func waitForWrittenPayloadCount(
        _ transport: ScriptedPrimaryTransport,
        count: Int
    ) async throws {
        try await LiveRuntimeTestSupport.withTimeout(.seconds(1)) {
            while await transport.recordedWrittenPayloads().count < count {
                try await Task.sleep(for: .milliseconds(10))
            }
        }
    }

}

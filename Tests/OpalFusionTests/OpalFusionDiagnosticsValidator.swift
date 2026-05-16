// OpalFusionDiagnosticsValidator.swift

@testable import OpalFusion
import Foundation
import Network
import OpalCrypto
import OpalDiagnostics
import SwiftProtobuf
import Testing

@Suite(.serialized)
struct OpalFusionDiagnosticsValidator {
    @Test("Public diagnostics catalog exposes stable typed values")
    func publicDiagnosticsCatalogExposesStableTypedValues() {
        let category: OpalFusion.Diagnostics.Category = OpalFusion.Diagnostics.Categories.primary
        let event: OpalFusion.Diagnostics.Event = OpalFusion.Diagnostics.Events.primaryMessageDecodeFailed
        let level: OpalFusion.Diagnostics.Level = .error

        #expect(category == OpalFusion.Diagnostics.Categories.primary)
        #expect(event == OpalFusion.Diagnostics.Events.primaryMessageDecodeFailed)
        #expect(level == .error)
        #expect(OpalFusion.Diagnostics.ErrorCodes.relayedProofValidationFailed == "relayed_proof_validation_failed")
    }

    @Test("Fusion category filter includes subcategories and excludes unrelated packages")
    func fusionCategoryFilterIncludesSubcategories() {
        withDiagnosticsCapture {
            OpalFusionDiagnostics.record(
                OpalFusion.Diagnostics.Events.primaryMessageDecodeFailed,
                category: OpalFusion.Diagnostics.Categories.primary,
                fields: [
                    OpalFusionDiagnostics.makeOperationField("primary_decode")
                ]
            )
            OpalDiagnostics.logger(category: .crypto).record(
                event: "opalcrypto.filtered",
                level: .debug
            )

            #expect(OpalDiagnostics.recentRecords.map(\.event) == [
                OpalFusion.Diagnostics.Events.primaryMessageDecodeFailed
            ])
            #expect(OpalDiagnostics.recentRecords.map(\.category) == [
                OpalFusion.Diagnostics.Categories.primary
            ])
        }
    }

    @Test("Primary decode failures record public counts and redacted errors")
    func primaryDecodeFailuresRecordRedactedDiagnostics() throws {
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

            let record = try #require(findDiagnosticRecord(named: OpalFusion.Diagnostics.Events.primaryMessageDecodeFailed))
            #expect(record.category == OpalFusion.Diagnostics.Categories.primary)
            #expect(findField("operation", in: record)?.value == "primary_inbound_decode")
            #expect(findField("frame_byte_count", in: record)?.value == "\(malformedFrame.count)")
            #expect(findField("error_message", in: record)?.value == "<redacted>")
            #expect(record.fields.contains { $0.value.contains("FF") } == false)
        }
    }

    @Test("Invalid configuration diagnostics preserve the safe configuration error code")
    func invalidConfigurationDiagnosticsPreserveErrorCode() throws {
        try withDiagnosticsCapture {
            var session = PrimaryRuntimeTestFixtures.makeSession()

            _ = session.apply(
                input: .invalidConfiguration(summary: "server secret material rejected"),
                now: PrimaryRuntimeTestFixtures.instant(994)
            )

            let record = try #require(findDiagnosticRecord(named: OpalFusion.Diagnostics.Events.transportError))
            #expect(findField("operation", in: record)?.value == "primary_runtime")
            #expect(findField("error_code", in: record)?.value == OpalFusion.Diagnostics.ErrorCodes.invalidConfiguration)
            #expect(findField("error_message", in: record)?.value == "<redacted>")
            #expect(record.fields.contains { $0.value.contains("server secret material") } == false)
        }
    }

    @Test("Primary network setup states use primary connection events")
    func primaryNetworkSetupStatesUsePrimaryConnectionEvents() {
        #expect(
            OpalFusion.Runtime.NetworkPrimaryConnection.makeDiagnosticsEvent(for: .setup) ==
                OpalFusion.Diagnostics.Events.primaryConnectionPreparing
        )
        #expect(
            OpalFusion.Runtime.NetworkPrimaryConnection.makeDiagnosticsEvent(for: .preparing) ==
                OpalFusion.Diagnostics.Events.primaryConnectionPreparing
        )
    }

    @Test("Covert response decode failures record redacted diagnostics")
    func covertResponseDecodeFailuresRecordRedactedDiagnostics() throws {
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
            let record = try #require(findDiagnosticRecord(named: OpalFusion.Diagnostics.Events.covertResponseDecodeFailed))
            #expect(record.category == OpalFusion.Diagnostics.Categories.covert)
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
            let record = try #require(findDiagnosticRecord(named: OpalFusion.Diagnostics.Events.covertPrepareFailed))
            #expect(findField("operation", in: record)?.value == "covert_prepare")
            #expect(findField("error_code", in: record)?.value == OpalFusion.Diagnostics.ErrorCodes.transportUnavailable)
            #expect(
                OpalDiagnostics.recentRecords(
                    matching: .init(event: OpalFusion.Diagnostics.Events.covertRequestFailed)
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

            let record = try #require(findDiagnosticRecord(named: OpalFusion.Diagnostics.Events.roundEntered))
            #expect(record.traceID == OpalFusion.Diagnostics.TraceID(rawValue: PrimaryRuntimeTestFixtures.roundIdentifier.rawValue))
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

            let record = try #require(findDiagnosticRecord(named: OpalFusion.Diagnostics.Events.transactionFinalizationFailed))
            #expect(record.category == OpalFusion.Diagnostics.Categories.transaction)
            #expect(record.traceID == OpalFusion.Diagnostics.TraceID(rawValue: PrimaryRuntimeTestFixtures.roundIdentifier.rawValue))
            #expect(findField("error_code", in: record)?.value == OpalFusion.Diagnostics.ErrorCodes.hostPolicyRejected)
            #expect(findField("error_message", in: record)?.value == "<redacted>")
            #expect(record.fields.contains { $0.value.contains("wallet raw transaction material") } == false)
            #expect(
                OpalDiagnostics.recentRecords(
                    matching: .init(event: OpalFusion.Diagnostics.Events.roundFailed)
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
                matching: .init(event: OpalFusion.Diagnostics.Events.roundCompleted)
            )
            #expect(records.count == 1)
            #expect(records.first?.traceID == OpalFusion.Diagnostics.TraceID(rawValue: PrimaryRuntimeTestFixtures.roundIdentifier.rawValue))
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

            let record = try #require(findDiagnosticRecord(named: OpalFusion.Diagnostics.Events.roundFailed))
            #expect(findField("operation", in: record)?.value == "host_event")
            #expect(findField("error_code", in: record)?.value == OpalFusion.Diagnostics.ErrorCodes.transportUnavailable)
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
                    connectError: NSError(domain: "OpalFusionDiagnosticsValidator", code: 1)
                )
            )

            await driver.start()

            let records = OpalDiagnostics.recentRecords(
                matching: .init(event: OpalFusion.Diagnostics.Events.primaryConnectFailed)
            )
            #expect(records.count == 1)
            let record = try #require(records.first)
            #expect(findField("operation", in: record)?.value == "primary_connect")
            #expect(findField("error_code", in: record)?.value == OpalFusion.Diagnostics.ErrorCodes.unknown)
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
            OpalFusionDiagnostics.record(
                OpalFusion.Diagnostics.Events.covertRequestFailed,
                category: OpalFusion.Diagnostics.Categories.covert,
                traceID: OpalFusionDiagnostics.makeTraceID(
                    for: PrimaryRuntimeTestFixtures.covertEndpointContext.roundIdentifier
                ),
                fields: [
                    OpalFusionDiagnostics.makeOperationField("covert_request")
                ] + OpalFusionDiagnostics.makeErrorFields(
                    for: OpalFusion.Runtime.LiveTransportError.unexpectedHTTPStatus(503)
                )
            )
            _ = session.apply(
                input: .covertRequestFailed(summary: "Covert request failed"),
                now: PrimaryRuntimeTestFixtures.instant(1_003)
            )

            let records = OpalDiagnostics.recentRecords(
                matching: .init(event: OpalFusion.Diagnostics.Events.covertRequestFailed)
            )
            #expect(records.count == 1)
            let record = try #require(records.first)
            #expect(findField("operation", in: record)?.value == "covert_request")
            #expect(findField("error_code", in: record)?.value == OpalFusion.Diagnostics.ErrorCodes.unexpectedHTTPStatus)
        }
    }

    @Test("Driver-level primary transport failures are not duplicated by session state")
    func driverLevelPrimaryTransportFailuresAreNotDuplicatedBySessionState() throws {
        try withDiagnosticsCapture {
            var session = PrimaryRuntimeTestFixtures.makeSession()

            OpalFusionDiagnostics.record(
                OpalFusion.Diagnostics.Events.transportError,
                category: OpalFusion.Diagnostics.Categories.transport,
                fields: [
                    OpalFusionDiagnostics.makeOperationField("primary_read")
                ] + OpalFusionDiagnostics.makeErrorFields(
                    for: OpalFusion.Runtime.LiveTransportError.primaryConnectionNotReady
                )
            )
            _ = session.apply(
                input: .diagnosedPrimaryTransportFailed(summary: "Primary read failed"),
                now: PrimaryRuntimeTestFixtures.instant(1_003)
            )

            let records = OpalDiagnostics.recentRecords(
                matching: .init(event: OpalFusion.Diagnostics.Events.transportError)
            )
            #expect(records.count == 1)
            let record = try #require(records.first)
            #expect(findField("operation", in: record)?.value == "primary_read")
            #expect(findField("error_code", in: record)?.value == OpalFusion.Diagnostics.ErrorCodes.primaryConnectionNotReady)
            #expect(session.diagnostics(activity: .failed).recentEvents.contains {
                $0.kind == .failure && $0.summary == "Primary read failed"
            })
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
                named: OpalFusion.Diagnostics.Events.covertPrepareSucceeded
            )
            await nowProvider.update(unixSeconds: 1_030)
            await primaryTransport.yieldInboundBytes(
                try PrimaryRuntimeTestFixtures.encodeServerFrame(
                    .startRound(PrimaryRuntimeTestFixtures.startRound)
                )
            )

            let roundRecord = try await waitForDiagnosticRecord(
                named: OpalFusion.Diagnostics.Events.roundEntered
            )
            let roundTraceID = OpalFusion.Diagnostics.TraceID(
                rawValue: PrimaryRuntimeTestFixtures.roundIdentifier.rawValue
            )
            #expect(roundRecord.traceID == roundTraceID)

            OpalDiagnostics.clearRecentRecords()
            await primaryTransport.finishInbound(
                throwing: LiveRuntimeTestSupportError.inboundStreamClosed
            )

            let record = try await waitForDiagnosticRecord(
                named: OpalFusion.Diagnostics.Events.transportError
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
            let record = try #require(findDiagnosticRecord(named: OpalFusion.Diagnostics.Events.blameProofValidationFailed))
            #expect(record.category == OpalFusion.Diagnostics.Categories.blame)
            #expect(record.traceID == OpalFusion.Diagnostics.TraceID(rawValue: scenario.round.identifier!.rawValue))
            #expect(findField("error_code", in: record)?.value == OpalFusion.Diagnostics.ErrorCodes.relayedProofValidationFailed)
            #expect(findField("error_message", in: record)?.value == "<redacted>")
            #expect(record.fields.contains { $0.value.contains("proof decode failed") } == false)
        }
    }

    @Test("Reconnect scheduling emits OpalDiagnostics without changing snapshot diagnostics")
    func reconnectSchedulingEmitsDiagnostics() async throws {
        try await withDiagnosticsCapture {
            let stateObserver = RecordedClientStateObserver()
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
                stateObserver: stateObserver,
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

            let retrySnapshot = try await waitForObservedSnapshot(stateObserver) {
                $0.diagnostics.activity == .retrying
            }

            let record = try #require(findDiagnosticRecord(named: OpalFusion.Diagnostics.Events.primaryRetryScheduled))
            #expect(findField("retry_attempt", in: record)?.value == "1")
            #expect(findField("retry_delay_ms", in: record)?.value == "10")
            #expect(retrySnapshot.diagnostics.recentEvents.contains {
                $0.kind == .retry &&
                    $0.retryAttempt == 1 &&
                    $0.retryDelayMilliseconds == 10
            })

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
        categoryFilter: .enabledIncludingSubcategories([OpalFusion.Diagnostics.Categories.fusion]),
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

    private func waitForObservedSnapshot(
        _ stateObserver: RecordedClientStateObserver,
        matching predicate: @escaping @Sendable (
            OpalFusion.Client.Session.Snapshot
        ) -> Bool
    ) async throws -> OpalFusion.Client.Session.Snapshot {
        try await LiveRuntimeTestSupport.withTimeout(.seconds(1)) {
            while true {
                if let snapshot = await stateObserver.snapshot().last(where: predicate) {
                    return snapshot
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

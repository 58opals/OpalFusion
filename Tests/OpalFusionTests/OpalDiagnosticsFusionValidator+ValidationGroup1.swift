// OpalDiagnosticsFusionValidator+ValidationGroup1.swift

@testable import OpalFusion
import Foundation
import Network
import OpalCrypto
import OpalDiagnostics
import Testing

extension OpalDiagnosticsFusionValidator {
    @Test("Fusion blame diagnostics preserve their public event name")
    func validateStableBlameDiagnosticEventName() {
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

    @Test("Primary protobuf coding and decoding failures use distinct diagnostics codes")
    func validatePrimaryProtobufFailureDiagnosticsCodes() {
        #expect(
            OpalDiagnostics.ErrorCode.resolveOpalFusionCode(
                for: OpalFusion.Wire.PrimaryMessageCodecError.protobufCodingFailed("redacted")
            ) == .protobufCodingFailed
        )
        #expect(
            OpalDiagnostics.ErrorCode.resolveOpalFusionCode(
                for: OpalFusion.Wire.PrimaryMessageCodecError.protobufDecodingFailed("redacted")
            ) == .protobufDecodingFailed
        )
    }

    @Test("Participant reservation failures use distinct diagnostics codes")
    func validateParticipantReservationFailureDiagnosticsCodes() {
        #expect(
            OpalDiagnostics.ErrorCode.resolveOpalFusionCode(
                for: OpalFusion.Host.ParticipantReservationFailure.reservationUnavailable(
                    reason: .walletLocked,
                    summary: "redacted"
                )
            ) == .participantReservationUnavailable
        )
        #expect(
            OpalDiagnostics.ErrorCode.resolveOpalFusionCode(
                for: OpalFusion.Host.ParticipantReservationFailure.hostPolicyRejected(
                    reason: .noEligibleInputs,
                    summary: "redacted"
                )
            ) == .participantReservationHostPolicyRejected
        )
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
            var session = makeDispatchedCovertSession()
            _ = session.apply(
                input: .roundIdentifierResolved(PrimaryRuntimeTestFixtures.roundIdentifier),
                now: PrimaryRuntimeTestFixtures.instant(1_003)
            )

            OpalDiagnostics.clearRecentRecords()
            let effects = session.apply(
                input: .covertResponseBytesReceived([0xFF]),
                now: PrimaryRuntimeTestFixtures.instant(1_004)
            )

            #expect(effects == [.emitProtocolFailure(summary: "Covert response decode failed")])
            let record = try #require(findDiagnosticRecord(named: OpalDiagnostics.Event.covertResponseDecodeFailed))
            #expect(record.category == OpalDiagnostics.Category.fusionCovert)
            #expect(record.traceID == Self.primaryRoundTraceID)
            #expect(findField("operation", in: record)?.value == "covert_response_decode")
            #expect(findField("payload_byte_count", in: record)?.value == "1")
            #expect(findField("error_message", in: record)?.value == "<redacted>")
        }
    }

    @Test("Covert preparation timeouts record prepare failure diagnostics")
    func validateCovertPreparationTimeoutsRecordPrepareFailureDiagnostics() throws {
        try withDiagnosticsCapture {
            var session = makePreparingCovertSession()

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

    @Test("Covert preparation success uses the resolved round trace ID")
    func validateCovertPreparationSuccessUsesResolvedRoundTraceID() throws {
        try withDiagnosticsCapture {
            var session = makePreparingCovertSession()
            _ = session.apply(
                input: .roundIdentifierResolved(PrimaryRuntimeTestFixtures.roundIdentifier),
                now: PrimaryRuntimeTestFixtures.instant(1_001)
            )

            OpalDiagnostics.clearRecentRecords()
            _ = session.apply(input: .covertPrepared, now: PrimaryRuntimeTestFixtures.instant(1_002))

            let record = try #require(findDiagnosticRecord(named: OpalDiagnostics.Event.covertPrepareSucceeded))
            #expect(record.traceID == Self.primaryRoundTraceID)
            #expect(findField("operation", in: record)?.value == "covert_prepare")
        }
    }
}

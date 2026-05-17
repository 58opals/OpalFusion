// OpalDiagnostics+OpalFusion.swift

import Foundation
import OpalDiagnostics

extension OpalDiagnostics.Category {
    static let fusionPrimary = OpalDiagnostics.Category(rawValue: "fusion.primary")
    static let fusionCovert = OpalDiagnostics.Category(rawValue: "fusion.covert")
    static let fusionRound = OpalDiagnostics.Category(rawValue: "fusion.round")
    static let fusionTransaction = OpalDiagnostics.Category(rawValue: "fusion.transaction")
    static let fusionBlame = OpalDiagnostics.Category(rawValue: "fusion.blame")
    static let fusionTransport = OpalDiagnostics.Category(rawValue: "fusion.transport")
}

extension OpalDiagnostics.Event {
    static let primaryConnectStarted = OpalDiagnostics.Event(rawValue: "opalfusion.primary.connect.started")
    static let primaryConnectSucceeded = OpalDiagnostics.Event(rawValue: "opalfusion.primary.connect.succeeded")
    static let primaryConnectFailed = OpalDiagnostics.Event(rawValue: "opalfusion.primary.connect.failed")
    static let primaryConnectionPreparing = OpalDiagnostics.Event(rawValue: "opalfusion.primary.connection.preparing")
    static let primaryConnectionReady = OpalDiagnostics.Event(rawValue: "opalfusion.primary.connection.ready")
    static let primaryConnectionWaiting = OpalDiagnostics.Event(rawValue: "opalfusion.primary.connection.waiting")
    static let primaryConnectionCancelled = OpalDiagnostics.Event(rawValue: "opalfusion.primary.connection.cancelled")
    static let primaryConnectionPeerEOF = OpalDiagnostics.Event(rawValue: "opalfusion.primary.connection.peer_eof")
    static let primaryMessageSent = OpalDiagnostics.Event(rawValue: "opalfusion.primary.message.sent")
    static let primaryMessageReceived = OpalDiagnostics.Event(rawValue: "opalfusion.primary.message.received")
    static let primaryMessageEncodeFailed = OpalDiagnostics.Event(rawValue: "opalfusion.primary.message.encode.failed")
    static let primaryMessageDecodeFailed = OpalDiagnostics.Event(rawValue: "opalfusion.primary.message.decode.failed")
    static let primaryRetryScheduled = OpalDiagnostics.Event(rawValue: "opalfusion.primary.retry.scheduled")
    static let handshakePhaseChanged = OpalDiagnostics.Event(rawValue: "opalfusion.handshake.phase.changed")

    static let covertPrepareStarted = OpalDiagnostics.Event(rawValue: "opalfusion.covert.prepare.started")
    static let covertPrepareSucceeded = OpalDiagnostics.Event(rawValue: "opalfusion.covert.prepare.succeeded")
    static let covertPrepareFailed = OpalDiagnostics.Event(rawValue: "opalfusion.covert.prepare.failed")
    static let covertRequestStarted = OpalDiagnostics.Event(rawValue: "opalfusion.covert.request.started")
    static let covertRequestSucceeded = OpalDiagnostics.Event(rawValue: "opalfusion.covert.request.succeeded")
    static let covertRequestFailed = OpalDiagnostics.Event(rawValue: "opalfusion.covert.request.failed")
    static let covertMessageEncodeFailed = OpalDiagnostics.Event(rawValue: "opalfusion.covert.message.encode.failed")
    static let covertResponseDecodeFailed = OpalDiagnostics.Event(rawValue: "opalfusion.covert.response.decode.failed")

    static let roundEntered = OpalDiagnostics.Event(rawValue: "opalfusion.round.entered")
    static let roundProgressed = OpalDiagnostics.Event(rawValue: "opalfusion.round.progressed")
    static let roundCompleted = OpalDiagnostics.Event(rawValue: "opalfusion.round.completed")
    static let roundFailed = OpalDiagnostics.Event(rawValue: "opalfusion.round.failed")
    static let roundRestarted = OpalDiagnostics.Event(rawValue: "opalfusion.round.restarted")

    static let transactionProposalFailed = OpalDiagnostics.Event(rawValue: "opalfusion.transaction.proposal.failed")
    static let transactionFinalizationSucceeded = OpalDiagnostics.Event(rawValue: "opalfusion.transaction.finalization.succeeded")
    static let transactionFinalizationFailed = OpalDiagnostics.Event(rawValue: "opalfusion.transaction.finalization.failed")

    static let blameProofValidationFailed = OpalDiagnostics.Event(rawValue: "opalfusion.blame.proof_validation.failed")
    static let blameSubmissionStarted = OpalDiagnostics.Event(rawValue: "opalfusion.blame.submission.started")

    static let transportError = OpalDiagnostics.Event(rawValue: "opalfusion.transport.error")
}

extension OpalDiagnostics.Level {
    static func opalFusionDefault(for event: OpalDiagnostics.Event) -> OpalDiagnostics.Level {
        if event.rawValue.hasSuffix(".failed") || event == .transportError {
            return .error
        }

        if event.rawValue.hasSuffix(".completed") ||
            event.rawValue.hasSuffix(".entered") ||
            event.rawValue.hasSuffix(".restarted") ||
            event.rawValue.hasSuffix(".peer_eof") {
            return .notice
        }

        return .debug
    }
}

extension OpalDiagnostics.TraceID {
    static func opalFusionRound(
        _ roundIdentifier: OpalFusion.Round.Identifier?
    ) -> OpalDiagnostics.TraceID? {
        guard let roundIdentifier else {
            return nil
        }

        return OpalDiagnostics.TraceID(rawValue: roundIdentifier.rawValue)
    }
}

extension OpalDiagnostics.Field {
    static func publicField(_ name: String, _ value: String) -> OpalDiagnostics.Field {
        OpalDiagnostics.Field(name: name, publicValue: value)
    }

    static func publicField(_ name: String, _ value: Int) -> OpalDiagnostics.Field {
        OpalDiagnostics.Field(name: name, value: value)
    }

    static func privateField(_ name: String, _ value: String) -> OpalDiagnostics.Field {
        OpalDiagnostics.Field(name: name, value: value, privacy: .private)
    }

    static func operation(_ operation: String) -> OpalDiagnostics.Field {
        publicField("operation", operation)
    }

    static func phase(_ phase: OpalFusion.Round.Phase) -> OpalDiagnostics.Field {
        publicField("phase", phase.rawValue)
    }

    static func phase(_ phase: String) -> OpalDiagnostics.Field {
        publicField("phase", phase)
    }

    static func messageKind(_ messageKind: String) -> OpalDiagnostics.Field {
        publicField("message_kind", messageKind)
    }

    static func messageKind(
        _ messageKind: OpalFusion.Runtime.PrimaryRuntimeSession.PreRoundTrace.InboundKind?
    ) -> OpalDiagnostics.Field {
        Self.messageKind(messageKind?.rawValue ?? "nil")
    }

    static func messageKind(
        for message: OpalFusion.ProtocolModel.ClientMessage
    ) -> OpalDiagnostics.Field {
        messageKind(messageKindName(for: message))
    }

    static func messageKind(
        for message: OpalFusion.ProtocolModel.ServerMessage
    ) -> OpalDiagnostics.Field {
        messageKind(messageKindName(for: message))
    }

    static func messageKind(
        for message: OpalFusion.ProtocolModel.CovertMessage
    ) -> OpalDiagnostics.Field {
        messageKind(messageKindName(for: message))
    }

    static func messageKind(
        for response: OpalFusion.ProtocolModel.CovertResponse
    ) -> OpalDiagnostics.Field {
        messageKind(messageKindName(for: response))
    }

    static func payloadByteCount(_ count: Int) -> OpalDiagnostics.Field {
        publicField("payload_byte_count", count)
    }

    static func frameByteCount(_ count: Int) -> OpalDiagnostics.Field {
        publicField("frame_byte_count", count)
    }

    static func retryAttempt(_ attempt: Int) -> OpalDiagnostics.Field {
        publicField("retry_attempt", attempt)
    }

    static func retryDelayMilliseconds(_ milliseconds: Int) -> OpalDiagnostics.Field {
        publicField("retry_delay_ms", milliseconds)
    }

    static func roundState(_ state: OpalFusion.Execution.RoundSubstate) -> OpalDiagnostics.Field {
        publicField("round_state", state.rawValue)
    }

    static func settlementState(_ status: OpalFusion.Round.CompletionStatus) -> OpalDiagnostics.Field {
        publicField("settlement_state", status.rawValue)
    }

    static func terminal(_ isTerminal: Bool) -> OpalDiagnostics.Field {
        OpalDiagnostics.Field(name: "terminal", value: isTerminal)
    }

    static func errorCode(_ errorCode: String) -> OpalDiagnostics.Field {
        publicField("error_code", errorCode)
    }

    static func errorFields(for error: Swift.Error) -> [OpalDiagnostics.Field] {
        [
            errorCode(errorCode(for: error)),
            publicField("error_type", String(reflecting: Swift.type(of: error))),
            privateField("error_message", String(describing: error))
        ]
    }

    static func sanitizedSummaryFields(
        errorCode: String,
        summary: String
    ) -> [OpalDiagnostics.Field] {
        [
            Self.errorCode(errorCode),
            privateField("error_message", summary)
        ]
    }

    static func errorCode(for error: Swift.Error) -> String {
        switch error {
        case OpalFusion.Client.Error.invalidConfiguration:
            "invalid_configuration"
        case OpalFusion.Client.Error.transportUnavailable:
            "transport_unavailable"
        case OpalFusion.Client.Error.coordinatorRejected:
            "coordinator_rejected"
        case OpalFusion.Client.Error.hostRejected:
            "host_rejected"
        case OpalFusion.Client.Error.protocolIncompatible:
            "protocol_incompatible"
        case OpalFusion.Client.Error.blameRequired:
            "blame_required"
        case OpalFusion.Client.Error.notImplemented:
            "not_implemented"

        case OpalFusion.Runtime.LiveTransportError.primaryConnectionAlreadyStarted:
            "primary_connection_already_started"
        case OpalFusion.Runtime.LiveTransportError.primaryConnectionNotReady:
            "primary_connection_not_ready"
        case OpalFusion.Runtime.LiveTransportError.primaryConnectionCancelled:
            "primary_connection_cancelled"
        case OpalFusion.Runtime.LiveTransportError.covertEndpointNotPrepared:
            "covert_endpoint_not_prepared"
        case OpalFusion.Runtime.LiveTransportError.malformedCovertURL:
            "malformed_covert_url"
        case OpalFusion.Runtime.LiveTransportError.covertPayloadTooLarge:
            "covert_payload_too_large"
        case OpalFusion.Runtime.LiveTransportError.covertResponsePayloadTooLarge:
            "covert_response_payload_too_large"
        case OpalFusion.Runtime.LiveTransportError.invalidHTTPResponse:
            "invalid_http_response"
        case OpalFusion.Runtime.LiveTransportError.unexpectedHTTPStatus:
            "unexpected_http_status"
        case OpalFusion.Runtime.LiveTransportError.invalidConfiguration:
            "invalid_configuration"

        case OpalFusion.Wire.PrimaryMessageCodecError.missingClientMessageCase:
            "missing_client_message_case"
        case OpalFusion.Wire.PrimaryMessageCodecError.missingServerMessageCase:
            "missing_server_message_case"
        case OpalFusion.Wire.PrimaryMessageCodecError.missingBlameDecrypter:
            "missing_blame_decrypter"
        case OpalFusion.Wire.PrimaryMessageCodecError.invalidUTF8Field:
            "invalid_utf8_field"
        case OpalFusion.Wire.PrimaryMessageCodecError.protobufDecodingFailed:
            "protobuf_decoding_failed"

        case OpalFusion.Wire.CovertMessageCodecError.missingCovertMessageCase:
            "missing_covert_message_case"
        case OpalFusion.Wire.CovertMessageCodecError.missingCovertResponseCase:
            "missing_covert_response_case"
        case OpalFusion.Wire.CovertMessageCodecError.protobufCodingFailed:
            "protobuf_coding_failed"

        case OpalFusion.Host.TransactionFinalizationFailure.transactionAssemblyFailed:
            "transaction_assembly_failed"
        case OpalFusion.Host.TransactionFinalizationFailure.hostPolicyRejected:
            "host_policy_rejected"

        case OpalFusion.Execution.WorkflowFailure.invalidParticipantReservation:
            "invalid_participant_reservation"
        case OpalFusion.Execution.WorkflowFailure.missingParticipantInputPublicKey:
            "missing_participant_input_public_key"
        case OpalFusion.Execution.WorkflowFailure.invalidTransactionTemplate:
            "invalid_transaction_template"
        case OpalFusion.Execution.WorkflowFailure.protocolValidationFailed:
            "workflow_protocol_validation_failed"
        case OpalFusion.Execution.WorkflowFailure.unsupportedExecution:
            "unsupported_execution"

        case is OpalFusion.Execution.RelayedProofValidationFailure:
            "relayed_proof_validation_failed"

        default:
            "unknown"
        }
    }
}

private extension OpalDiagnostics.Field {
    static func messageKindName(
        for message: OpalFusion.ProtocolModel.ClientMessage
    ) -> String {
        switch message {
        case .clientHello:
            "ClientHello"
        case .joinPools:
            "JoinPools"
        case .playerCommit:
            "PlayerCommit"
        case .myProofsList:
            "MyProofsList"
        case .blames:
            "Blames"
        }
    }

    static func messageKindName(
        for message: OpalFusion.ProtocolModel.ServerMessage
    ) -> String {
        switch message {
        case .serverHello:
            "ServerHello"
        case .tierStatusUpdate:
            "TierStatusUpdate"
        case .fusionBegin:
            "FusionBegin"
        case .startRound:
            "StartRound"
        case .blindSignatureResponses:
            "BlindSignatureResponses"
        case .allCommitments:
            "AllCommitments"
        case .shareCovertComponents:
            "ShareCovertComponents"
        case .fusionResult:
            "FusionResult"
        case .theirProofsList:
            "TheirProofsList"
        case .restartRound:
            "RestartRound"
        case .serverFailure:
            "ServerFailure"
        }
    }

    static func messageKindName(
        for message: OpalFusion.ProtocolModel.CovertMessage
    ) -> String {
        switch message {
        case .component:
            "CovertComponent"
        case .transactionSignature:
            "CovertTransactionSignature"
        case .ping:
            "Ping"
        }
    }

    static func messageKindName(
        for response: OpalFusion.ProtocolModel.CovertResponse
    ) -> String {
        switch response {
        case .acknowledgement:
            "Acknowledgement"
        case .serverFailure:
            "ServerFailure"
        }
    }
}

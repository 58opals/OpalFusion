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

extension OpalDiagnostics.ErrorCode {
    static let invalidConfiguration = Self(rawValue: "invalid_configuration")
    static let transportUnavailable = Self(rawValue: "transport_unavailable")
    static let coordinatorRejected = Self(rawValue: "coordinator_rejected")
    static let hostRejected = Self(rawValue: "host_rejected")
    static let protocolIncompatible = Self(rawValue: "protocol_incompatible")
    static let blameRequired = Self(rawValue: "blame_required")
    static let notImplemented = Self(rawValue: "not_implemented")
    static let primaryConnectionAlreadyStarted = Self(rawValue: "primary_connection_already_started")
    static let primaryConnectionNotReady = Self(rawValue: "primary_connection_not_ready")
    static let primaryConnectionCancelled = Self(rawValue: "primary_connection_cancelled")
    static let covertEndpointNotPrepared = Self(rawValue: "covert_endpoint_not_prepared")
    static let malformedCovertURL = Self(rawValue: "malformed_covert_url")
    static let covertPayloadTooLarge = Self(rawValue: "covert_payload_too_large")
    static let covertResponsePayloadTooLarge = Self(rawValue: "covert_response_payload_too_large")
    static let invalidHTTPResponse = Self(rawValue: "invalid_http_response")
    static let unexpectedHTTPStatus = Self(rawValue: "unexpected_http_status")
    static let missingClientMessageCase = Self(rawValue: "missing_client_message_case")
    static let missingServerMessageCase = Self(rawValue: "missing_server_message_case")
    static let missingBlameDecrypter = Self(rawValue: "missing_blame_decrypter")
    static let invalidUTF8Field = Self(rawValue: "invalid_utf8_field")
    static let protobufDecodingFailed = Self(rawValue: "protobuf_decoding_failed")
    static let missingCovertMessageCase = Self(rawValue: "missing_covert_message_case")
    static let missingCovertResponseCase = Self(rawValue: "missing_covert_response_case")
    static let protobufCodingFailed = Self(rawValue: "protobuf_coding_failed")
    static let transactionAssemblyFailed = Self(rawValue: "transaction_assembly_failed")
    static let hostPolicyRejected = Self(rawValue: "host_policy_rejected")
    static let invalidParticipantReservation = Self(rawValue: "invalid_participant_reservation")
    static let missingParticipantInputPublicKey = Self(rawValue: "missing_participant_input_public_key")
    static let invalidTransactionTemplate = Self(rawValue: "invalid_transaction_template")
    static let workflowProtocolValidationFailed = Self(rawValue: "workflow_protocol_validation_failed")
    static let unsupportedExecution = Self(rawValue: "unsupported_execution")
    static let relayedProofValidationFailed = Self(rawValue: "relayed_proof_validation_failed")
    static let unknown = Self(rawValue: "unknown")

    static func resolveOpalFusionCode(for error: Swift.Error) -> Self {
        switch error {
        case OpalFusion.Client.Error.invalidConfiguration:
            .invalidConfiguration
        case OpalFusion.Client.Error.transportUnavailable:
            .transportUnavailable
        case OpalFusion.Client.Error.coordinatorRejected:
            .coordinatorRejected
        case OpalFusion.Client.Error.hostRejected:
            .hostRejected
        case OpalFusion.Client.Error.protocolIncompatible:
            .protocolIncompatible
        case OpalFusion.Client.Error.blameRequired:
            .blameRequired
        case OpalFusion.Client.Error.notImplemented:
            .notImplemented

        case OpalFusion.Runtime.LiveTransportError.primaryConnectionAlreadyStarted:
            .primaryConnectionAlreadyStarted
        case OpalFusion.Runtime.LiveTransportError.primaryConnectionNotReady:
            .primaryConnectionNotReady
        case OpalFusion.Runtime.LiveTransportError.primaryConnectionCancelled:
            .primaryConnectionCancelled
        case OpalFusion.Runtime.LiveTransportError.covertEndpointNotPrepared:
            .covertEndpointNotPrepared
        case OpalFusion.Runtime.LiveTransportError.malformedCovertURL:
            .malformedCovertURL
        case OpalFusion.Runtime.LiveTransportError.covertPayloadTooLarge:
            .covertPayloadTooLarge
        case OpalFusion.Runtime.LiveTransportError.covertResponsePayloadTooLarge:
            .covertResponsePayloadTooLarge
        case OpalFusion.Runtime.LiveTransportError.invalidHTTPResponse:
            .invalidHTTPResponse
        case OpalFusion.Runtime.LiveTransportError.unexpectedHTTPStatus:
            .unexpectedHTTPStatus
        case OpalFusion.Runtime.LiveTransportError.invalidConfiguration:
            .invalidConfiguration

        case OpalFusion.Wire.PrimaryMessageCodecError.missingClientMessageCase:
            .missingClientMessageCase
        case OpalFusion.Wire.PrimaryMessageCodecError.missingServerMessageCase:
            .missingServerMessageCase
        case OpalFusion.Wire.PrimaryMessageCodecError.missingBlameDecrypter:
            .missingBlameDecrypter
        case OpalFusion.Wire.PrimaryMessageCodecError.invalidUTF8Field:
            .invalidUTF8Field
        case OpalFusion.Wire.PrimaryMessageCodecError.protobufCodingFailed:
            .protobufCodingFailed
        case OpalFusion.Wire.PrimaryMessageCodecError.protobufDecodingFailed:
            .protobufDecodingFailed

        case OpalFusion.Wire.CovertMessageCodecError.missingCovertMessageCase:
            .missingCovertMessageCase
        case OpalFusion.Wire.CovertMessageCodecError.missingCovertResponseCase:
            .missingCovertResponseCase
        case OpalFusion.Wire.CovertMessageCodecError.protobufCodingFailed:
            .protobufCodingFailed

        case OpalFusion.Host.TransactionFinalizationFailure.transactionAssemblyFailed:
            .transactionAssemblyFailed
        case OpalFusion.Host.TransactionFinalizationFailure.hostPolicyRejected:
            .hostPolicyRejected

        case OpalFusion.Execution.WorkflowFailure.invalidParticipantReservation:
            .invalidParticipantReservation
        case OpalFusion.Execution.WorkflowFailure.missingParticipantInputPublicKey:
            .missingParticipantInputPublicKey
        case OpalFusion.Execution.WorkflowFailure.invalidTransactionTemplate:
            .invalidTransactionTemplate
        case OpalFusion.Execution.WorkflowFailure.protocolValidationFailed:
            .workflowProtocolValidationFailed
        case OpalFusion.Execution.WorkflowFailure.unsupportedExecution:
            .unsupportedExecution

        case is OpalFusion.Execution.RelayedProofValidationFailure:
            .relayedProofValidationFailed

        default:
            .unknown
        }
    }
}

extension OpalDiagnostics.Field {
    static func operation(_ operation: String) -> OpalDiagnostics.Field {
        OpalDiagnostics.Field(name: "operation", publicValue: operation)
    }

    static func phase(_ phase: OpalFusion.Round.Phase) -> OpalDiagnostics.Field {
        OpalDiagnostics.Field(name: "phase", publicValue: phase.rawValue)
    }

    static func phase(_ phase: String) -> OpalDiagnostics.Field {
        OpalDiagnostics.Field(name: "phase", publicValue: phase)
    }

    static func messageKind(_ messageKind: String) -> OpalDiagnostics.Field {
        OpalDiagnostics.Field(name: "message_kind", publicValue: messageKind)
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
        OpalDiagnostics.Field(name: "payload_byte_count", value: count)
    }

    static func frameByteCount(_ count: Int) -> OpalDiagnostics.Field {
        OpalDiagnostics.Field(name: "frame_byte_count", value: count)
    }

    static func retryAttempt(_ attempt: Int) -> OpalDiagnostics.Field {
        OpalDiagnostics.Field(name: "retry_attempt", value: attempt)
    }

    static func retryDelayMilliseconds(_ milliseconds: Int) -> OpalDiagnostics.Field {
        OpalDiagnostics.Field(name: "retry_delay_ms", value: milliseconds)
    }

    static func roundState(_ state: OpalFusion.Execution.RoundSubstate) -> OpalDiagnostics.Field {
        OpalDiagnostics.Field(name: "round_state", publicValue: state.rawValue)
    }

    static func settlementState(_ status: OpalFusion.Round.CompletionStatus) -> OpalDiagnostics.Field {
        OpalDiagnostics.Field(name: "settlement_state", publicValue: status.rawValue)
    }

    static func terminal(_ isTerminal: Bool) -> OpalDiagnostics.Field {
        OpalDiagnostics.Field(name: "terminal", value: isTerminal)
    }

    static func errorFields(for error: Swift.Error) -> [OpalDiagnostics.Field] {
        [
            OpalDiagnostics.Field.errorCode(OpalDiagnostics.ErrorCode.resolveOpalFusionCode(for: error)),
            OpalDiagnostics.Field.errorType(error),
            OpalDiagnostics.Field.errorMessage(String(describing: error))
        ]
    }

    static func sanitizedSummaryFields(
        errorCode: OpalDiagnostics.ErrorCode,
        summary: String
    ) -> [OpalDiagnostics.Field] {
        [
            OpalDiagnostics.Field.errorCode(errorCode),
            OpalDiagnostics.Field.errorMessage(summary)
        ]
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

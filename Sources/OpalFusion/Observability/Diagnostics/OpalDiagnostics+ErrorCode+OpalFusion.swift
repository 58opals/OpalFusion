// OpalDiagnostics+ErrorCode+OpalFusion.swift

import Foundation
import OpalDiagnostics

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

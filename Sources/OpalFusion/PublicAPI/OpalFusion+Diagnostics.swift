// OpalFusion+Diagnostics.swift

import OpalDiagnostics

public extension OpalFusion {
    /// Stable diagnostics names and trace helpers for correlating OpalFusion operations from application code.
    enum Diagnostics {
        public typealias Category = OpalDiagnostics.Category
        public typealias Event = OpalDiagnostics.Event
        public typealias Level = OpalDiagnostics.Level
        public typealias TraceID = OpalDiagnostics.TraceID

        public enum Categories {
            public static let fusion = OpalDiagnostics.Category.fusion
            public static let primary = OpalDiagnostics.Category(rawValue: "fusion.primary")
            public static let covert = OpalDiagnostics.Category(rawValue: "fusion.covert")
            public static let round = OpalDiagnostics.Category(rawValue: "fusion.round")
            public static let transaction = OpalDiagnostics.Category(rawValue: "fusion.transaction")
            public static let blame = OpalDiagnostics.Category(rawValue: "fusion.blame")
            public static let transport = OpalDiagnostics.Category(rawValue: "fusion.transport")
        }

        public enum Events {
            public static let primaryConnectStarted = OpalDiagnostics.Event(rawValue: "opalfusion.primary.connect.started")
            public static let primaryConnectSucceeded = OpalDiagnostics.Event(rawValue: "opalfusion.primary.connect.succeeded")
            public static let primaryConnectFailed = OpalDiagnostics.Event(rawValue: "opalfusion.primary.connect.failed")
            public static let primaryConnectionPreparing = OpalDiagnostics.Event(rawValue: "opalfusion.primary.connection.preparing")
            public static let primaryConnectionReady = OpalDiagnostics.Event(rawValue: "opalfusion.primary.connection.ready")
            public static let primaryConnectionWaiting = OpalDiagnostics.Event(rawValue: "opalfusion.primary.connection.waiting")
            public static let primaryConnectionCancelled = OpalDiagnostics.Event(rawValue: "opalfusion.primary.connection.cancelled")
            public static let primaryConnectionPeerEOF = OpalDiagnostics.Event(rawValue: "opalfusion.primary.connection.peer_eof")
            public static let primaryMessageSent = OpalDiagnostics.Event(rawValue: "opalfusion.primary.message.sent")
            public static let primaryMessageReceived = OpalDiagnostics.Event(rawValue: "opalfusion.primary.message.received")
            public static let primaryMessageEncodeFailed = OpalDiagnostics.Event(rawValue: "opalfusion.primary.message.encode.failed")
            public static let primaryMessageDecodeFailed = OpalDiagnostics.Event(rawValue: "opalfusion.primary.message.decode.failed")
            public static let primaryRetryScheduled = OpalDiagnostics.Event(rawValue: "opalfusion.primary.retry.scheduled")
            public static let handshakePhaseChanged = OpalDiagnostics.Event(rawValue: "opalfusion.handshake.phase.changed")

            public static let covertPrepareStarted = OpalDiagnostics.Event(rawValue: "opalfusion.covert.prepare.started")
            public static let covertPrepareSucceeded = OpalDiagnostics.Event(rawValue: "opalfusion.covert.prepare.succeeded")
            public static let covertPrepareFailed = OpalDiagnostics.Event(rawValue: "opalfusion.covert.prepare.failed")
            public static let covertRequestStarted = OpalDiagnostics.Event(rawValue: "opalfusion.covert.request.started")
            public static let covertRequestSucceeded = OpalDiagnostics.Event(rawValue: "opalfusion.covert.request.succeeded")
            public static let covertRequestFailed = OpalDiagnostics.Event(rawValue: "opalfusion.covert.request.failed")
            public static let covertMessageEncodeFailed = OpalDiagnostics.Event(rawValue: "opalfusion.covert.message.encode.failed")
            public static let covertResponseDecodeFailed = OpalDiagnostics.Event(rawValue: "opalfusion.covert.response.decode.failed")

            public static let roundEntered = OpalDiagnostics.Event(rawValue: "opalfusion.round.entered")
            public static let roundProgressed = OpalDiagnostics.Event(rawValue: "opalfusion.round.progressed")
            public static let roundCompleted = OpalDiagnostics.Event(rawValue: "opalfusion.round.completed")
            public static let roundFailed = OpalDiagnostics.Event(rawValue: "opalfusion.round.failed")
            public static let roundRestarted = OpalDiagnostics.Event(rawValue: "opalfusion.round.restarted")

            public static let transactionProposalFailed = OpalDiagnostics.Event(rawValue: "opalfusion.transaction.proposal.failed")
            public static let transactionFinalizationSucceeded = OpalDiagnostics.Event(rawValue: "opalfusion.transaction.finalization.succeeded")
            public static let transactionFinalizationFailed = OpalDiagnostics.Event(rawValue: "opalfusion.transaction.finalization.failed")

            public static let blameProofValidationFailed = OpalDiagnostics.Event(rawValue: "opalfusion.blame.proof_validation.failed")
            public static let blameSubmissionStarted = OpalDiagnostics.Event(rawValue: "opalfusion.blame.submission.started")

            public static let transportError = OpalDiagnostics.Event(rawValue: "opalfusion.transport.error")
        }

        public enum ErrorCodes {
            public static let invalidConfiguration = "invalid_configuration"
            public static let transportUnavailable = "transport_unavailable"
            public static let coordinatorRejected = "coordinator_rejected"
            public static let hostRejected = "host_rejected"
            public static let protocolIncompatible = "protocol_incompatible"
            public static let blameRequired = "blame_required"
            public static let notImplemented = "not_implemented"
            public static let primaryConnectionAlreadyStarted = "primary_connection_already_started"
            public static let primaryConnectionNotReady = "primary_connection_not_ready"
            public static let primaryConnectionCancelled = "primary_connection_cancelled"
            public static let covertEndpointNotPrepared = "covert_endpoint_not_prepared"
            public static let malformedCovertURL = "malformed_covert_url"
            public static let covertPayloadTooLarge = "covert_payload_too_large"
            public static let covertResponsePayloadTooLarge = "covert_response_payload_too_large"
            public static let invalidHTTPResponse = "invalid_http_response"
            public static let unexpectedHTTPStatus = "unexpected_http_status"
            public static let missingClientMessageCase = "missing_client_message_case"
            public static let missingServerMessageCase = "missing_server_message_case"
            public static let missingBlameDecrypter = "missing_blame_decrypter"
            public static let invalidUTF8Field = "invalid_utf8_field"
            public static let protobufDecodingFailed = "protobuf_decoding_failed"
            public static let missingCovertMessageCase = "missing_covert_message_case"
            public static let missingCovertResponseCase = "missing_covert_response_case"
            public static let protobufCodingFailed = "protobuf_coding_failed"
            public static let transactionAssemblyFailed = "transaction_assembly_failed"
            public static let hostPolicyRejected = "host_policy_rejected"
            public static let invalidParticipantReservation = "invalid_participant_reservation"
            public static let missingParticipantInputPublicKey = "missing_participant_input_public_key"
            public static let invalidTransactionTemplate = "invalid_transaction_template"
            public static let workflowProtocolValidationFailed = "workflow_protocol_validation_failed"
            public static let unsupportedExecution = "unsupported_execution"
            public static let relayedProofValidationFailed = "relayed_proof_validation_failed"
            public static let unknown = "unknown"
        }
    }
}

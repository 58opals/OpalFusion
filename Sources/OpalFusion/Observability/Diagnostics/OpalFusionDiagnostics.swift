// OpalFusionDiagnostics.swift

import Foundation
import OpalDiagnostics

enum OpalFusionDiagnostics {
    typealias Field = OpalDiagnostics.Field

    enum Category {
        static let fusion = OpalFusion.Diagnostics.Categories.fusion
        static let primary = OpalFusion.Diagnostics.Categories.primary
        static let covert = OpalFusion.Diagnostics.Categories.covert
        static let round = OpalFusion.Diagnostics.Categories.round
        static let transaction = OpalFusion.Diagnostics.Categories.transaction
        static let blame = OpalFusion.Diagnostics.Categories.blame
        static let transport = OpalFusion.Diagnostics.Categories.transport
    }

    enum Event {
        static let primaryConnectStarted = OpalFusion.Diagnostics.Events.primaryConnectStarted
        static let primaryConnectSucceeded = OpalFusion.Diagnostics.Events.primaryConnectSucceeded
        static let primaryConnectFailed = OpalFusion.Diagnostics.Events.primaryConnectFailed
        static let primaryConnectionPreparing = OpalFusion.Diagnostics.Events.primaryConnectionPreparing
        static let primaryConnectionReady = OpalFusion.Diagnostics.Events.primaryConnectionReady
        static let primaryConnectionWaiting = OpalFusion.Diagnostics.Events.primaryConnectionWaiting
        static let primaryConnectionCancelled = OpalFusion.Diagnostics.Events.primaryConnectionCancelled
        static let primaryConnectionPeerEOF = OpalFusion.Diagnostics.Events.primaryConnectionPeerEOF
        static let primaryMessageSent = OpalFusion.Diagnostics.Events.primaryMessageSent
        static let primaryMessageReceived = OpalFusion.Diagnostics.Events.primaryMessageReceived
        static let primaryMessageEncodeFailed = OpalFusion.Diagnostics.Events.primaryMessageEncodeFailed
        static let primaryMessageDecodeFailed = OpalFusion.Diagnostics.Events.primaryMessageDecodeFailed
        static let primaryRetryScheduled = OpalFusion.Diagnostics.Events.primaryRetryScheduled
        static let handshakePhaseChanged = OpalFusion.Diagnostics.Events.handshakePhaseChanged
        static let covertPrepareStarted = OpalFusion.Diagnostics.Events.covertPrepareStarted
        static let covertPrepareSucceeded = OpalFusion.Diagnostics.Events.covertPrepareSucceeded
        static let covertPrepareFailed = OpalFusion.Diagnostics.Events.covertPrepareFailed
        static let covertRequestStarted = OpalFusion.Diagnostics.Events.covertRequestStarted
        static let covertRequestSucceeded = OpalFusion.Diagnostics.Events.covertRequestSucceeded
        static let covertRequestFailed = OpalFusion.Diagnostics.Events.covertRequestFailed
        static let covertMessageEncodeFailed = OpalFusion.Diagnostics.Events.covertMessageEncodeFailed
        static let covertResponseDecodeFailed = OpalFusion.Diagnostics.Events.covertResponseDecodeFailed
        static let roundEntered = OpalFusion.Diagnostics.Events.roundEntered
        static let roundProgressed = OpalFusion.Diagnostics.Events.roundProgressed
        static let roundCompleted = OpalFusion.Diagnostics.Events.roundCompleted
        static let roundFailed = OpalFusion.Diagnostics.Events.roundFailed
        static let roundRestarted = OpalFusion.Diagnostics.Events.roundRestarted
        static let transactionProposalFailed = OpalFusion.Diagnostics.Events.transactionProposalFailed
        static let transactionFinalizationSucceeded = OpalFusion.Diagnostics.Events.transactionFinalizationSucceeded
        static let transactionFinalizationFailed = OpalFusion.Diagnostics.Events.transactionFinalizationFailed
        static let blameProofValidationFailed = OpalFusion.Diagnostics.Events.blameProofValidationFailed
        static let blameSubmissionStarted = OpalFusion.Diagnostics.Events.blameSubmissionStarted
        static let transportError = OpalFusion.Diagnostics.Events.transportError
    }

    static func record(
        _ event: OpalDiagnostics.Event,
        category: OpalDiagnostics.Category,
        level: OpalDiagnostics.Level? = nil,
        traceID: OpalDiagnostics.TraceID? = nil,
        fields: [OpalDiagnostics.Field] = []
    ) {
        OpalDiagnostics.logger(category: category).record(
            event: event,
            level: level ?? defaultLevel(for: event),
            traceID: traceID,
            fields: fields
        )
    }

    static func publicField(_ name: String, _ value: String) -> OpalDiagnostics.Field {
        OpalDiagnostics.Field(name: name, publicValue: value)
    }

    static func publicField(_ name: String, _ value: Int) -> OpalDiagnostics.Field {
        OpalDiagnostics.Field(name: name, value: value)
    }

    static func publicField(_ name: String, _ value: UInt64) -> OpalDiagnostics.Field {
        OpalDiagnostics.Field(name: name, value: value)
    }

    static func publicField(_ name: String, _ value: Bool) -> OpalDiagnostics.Field {
        OpalDiagnostics.Field(name: name, value: value)
    }

    static func privateField(_ name: String, _ value: String) -> OpalDiagnostics.Field {
        OpalDiagnostics.Field(name: name, value: value, privacy: .private)
    }

    static func operationField(_ operation: String) -> OpalDiagnostics.Field {
        publicField("operation", operation)
    }

    static func phaseField(_ phase: OpalFusion.Round.Phase) -> OpalDiagnostics.Field {
        publicField("phase", phase.rawValue)
    }

    static func messageKindField(_ messageKind: String) -> OpalDiagnostics.Field {
        publicField("message_kind", messageKind)
    }

    static func payloadByteCountField(_ count: Int) -> OpalDiagnostics.Field {
        publicField("payload_byte_count", count)
    }

    static func frameByteCountField(_ count: Int) -> OpalDiagnostics.Field {
        publicField("frame_byte_count", count)
    }

    static func retryAttemptField(_ attempt: Int) -> OpalDiagnostics.Field {
        publicField("retry_attempt", attempt)
    }

    static func retryDelayMillisecondsField(_ milliseconds: Int) -> OpalDiagnostics.Field {
        publicField("retry_delay_ms", milliseconds)
    }

    static func roundStateField(_ state: OpalFusion.Execution.RoundSubstate) -> OpalDiagnostics.Field {
        publicField("round_state", state.rawValue)
    }

    static func settlementStateField(_ status: OpalFusion.Round.CompletionStatus) -> OpalDiagnostics.Field {
        publicField("settlement_state", status.rawValue)
    }

    static func makeTraceID(for roundIdentifier: OpalFusion.Round.Identifier?) -> OpalDiagnostics.TraceID? {
        guard let roundIdentifier else {
            return nil
        }

        return OpalDiagnostics.TraceID(rawValue: roundIdentifier.rawValue)
    }

    static func errorFields(_ error: Swift.Error) -> [OpalDiagnostics.Field] {
        [
            publicField("error_code", errorCode(for: error)),
            publicField("error_type", String(reflecting: Swift.type(of: error))),
            privateField("error_message", String(describing: error))
        ]
    }

    static func sanitizedSummaryFields(
        errorCode: String,
        summary: String
    ) -> [OpalDiagnostics.Field] {
        [
            publicField("error_code", errorCode),
            privateField("error_message", summary)
        ]
    }
}

extension OpalFusionDiagnostics {
    static func messageKind(
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

    static func messageKind(
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

    static func messageKind(
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

    static func messageKind(
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

extension OpalFusionDiagnostics {
    private static func defaultLevel(for event: OpalDiagnostics.Event) -> OpalDiagnostics.Level {
        if event.rawValue.hasSuffix(".failed") || event == Event.transportError {
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

    static func errorCode(for error: Swift.Error) -> String {
        switch error {
        case OpalFusion.Client.Error.invalidConfiguration:
            OpalFusion.Diagnostics.ErrorCodes.invalidConfiguration
        case OpalFusion.Client.Error.transportUnavailable:
            OpalFusion.Diagnostics.ErrorCodes.transportUnavailable
        case OpalFusion.Client.Error.coordinatorRejected:
            OpalFusion.Diagnostics.ErrorCodes.coordinatorRejected
        case OpalFusion.Client.Error.hostRejected:
            OpalFusion.Diagnostics.ErrorCodes.hostRejected
        case OpalFusion.Client.Error.protocolIncompatible:
            OpalFusion.Diagnostics.ErrorCodes.protocolIncompatible
        case OpalFusion.Client.Error.blameRequired:
            OpalFusion.Diagnostics.ErrorCodes.blameRequired
        case OpalFusion.Client.Error.notImplemented:
            OpalFusion.Diagnostics.ErrorCodes.notImplemented

        case OpalFusion.Runtime.LiveTransportError.primaryConnectionAlreadyStarted:
            OpalFusion.Diagnostics.ErrorCodes.primaryConnectionAlreadyStarted
        case OpalFusion.Runtime.LiveTransportError.primaryConnectionNotReady:
            OpalFusion.Diagnostics.ErrorCodes.primaryConnectionNotReady
        case OpalFusion.Runtime.LiveTransportError.primaryConnectionCancelled:
            OpalFusion.Diagnostics.ErrorCodes.primaryConnectionCancelled
        case OpalFusion.Runtime.LiveTransportError.covertEndpointNotPrepared:
            OpalFusion.Diagnostics.ErrorCodes.covertEndpointNotPrepared
        case OpalFusion.Runtime.LiveTransportError.malformedCovertURL:
            OpalFusion.Diagnostics.ErrorCodes.malformedCovertURL
        case OpalFusion.Runtime.LiveTransportError.covertPayloadTooLarge:
            OpalFusion.Diagnostics.ErrorCodes.covertPayloadTooLarge
        case OpalFusion.Runtime.LiveTransportError.covertResponsePayloadTooLarge:
            OpalFusion.Diagnostics.ErrorCodes.covertResponsePayloadTooLarge
        case OpalFusion.Runtime.LiveTransportError.invalidHTTPResponse:
            OpalFusion.Diagnostics.ErrorCodes.invalidHTTPResponse
        case OpalFusion.Runtime.LiveTransportError.unexpectedHTTPStatus:
            OpalFusion.Diagnostics.ErrorCodes.unexpectedHTTPStatus
        case OpalFusion.Runtime.LiveTransportError.invalidConfiguration:
            OpalFusion.Diagnostics.ErrorCodes.invalidConfiguration

        case OpalFusion.Wire.PrimaryMessageCodecError.missingClientMessageCase:
            OpalFusion.Diagnostics.ErrorCodes.missingClientMessageCase
        case OpalFusion.Wire.PrimaryMessageCodecError.missingServerMessageCase:
            OpalFusion.Diagnostics.ErrorCodes.missingServerMessageCase
        case OpalFusion.Wire.PrimaryMessageCodecError.missingBlameDecrypter:
            OpalFusion.Diagnostics.ErrorCodes.missingBlameDecrypter
        case OpalFusion.Wire.PrimaryMessageCodecError.invalidUTF8Field:
            OpalFusion.Diagnostics.ErrorCodes.invalidUTF8Field
        case OpalFusion.Wire.PrimaryMessageCodecError.protobufDecodingFailed:
            OpalFusion.Diagnostics.ErrorCodes.protobufDecodingFailed

        case OpalFusion.Wire.CovertMessageCodecError.missingCovertMessageCase:
            OpalFusion.Diagnostics.ErrorCodes.missingCovertMessageCase
        case OpalFusion.Wire.CovertMessageCodecError.missingCovertResponseCase:
            OpalFusion.Diagnostics.ErrorCodes.missingCovertResponseCase
        case OpalFusion.Wire.CovertMessageCodecError.protobufCodingFailed:
            OpalFusion.Diagnostics.ErrorCodes.protobufCodingFailed

        case OpalFusion.Host.TransactionFinalizationFailure.transactionAssemblyFailed:
            OpalFusion.Diagnostics.ErrorCodes.transactionAssemblyFailed
        case OpalFusion.Host.TransactionFinalizationFailure.hostPolicyRejected:
            OpalFusion.Diagnostics.ErrorCodes.hostPolicyRejected

        case OpalFusion.Execution.WorkflowFailure.invalidParticipantReservation:
            OpalFusion.Diagnostics.ErrorCodes.invalidParticipantReservation
        case OpalFusion.Execution.WorkflowFailure.missingParticipantInputPublicKey:
            OpalFusion.Diagnostics.ErrorCodes.missingParticipantInputPublicKey
        case OpalFusion.Execution.WorkflowFailure.invalidTransactionTemplate:
            OpalFusion.Diagnostics.ErrorCodes.invalidTransactionTemplate
        case OpalFusion.Execution.WorkflowFailure.protocolValidationFailed:
            OpalFusion.Diagnostics.ErrorCodes.workflowProtocolValidationFailed
        case OpalFusion.Execution.WorkflowFailure.unsupportedExecution:
            OpalFusion.Diagnostics.ErrorCodes.unsupportedExecution

        case is OpalFusion.Execution.RelayedProofValidationFailure:
            OpalFusion.Diagnostics.ErrorCodes.relayedProofValidationFailed

        default:
            OpalFusion.Diagnostics.ErrorCodes.unknown
        }
    }
}

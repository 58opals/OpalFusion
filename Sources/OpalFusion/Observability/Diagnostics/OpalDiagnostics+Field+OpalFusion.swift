// OpalDiagnostics+Field+OpalFusion.swift

import Foundation
import OpalDiagnostics

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

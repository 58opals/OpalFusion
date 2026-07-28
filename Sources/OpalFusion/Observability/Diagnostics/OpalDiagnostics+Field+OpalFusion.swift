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
        OpalDiagnostics.Field(name: "payload_byte_count", value: count, privacy: .public)
    }

    static func frameByteCount(_ count: Int) -> OpalDiagnostics.Field {
        OpalDiagnostics.Field(name: "frame_byte_count", value: count, privacy: .public)
    }

    static func retryAttempt(_ attempt: Int) -> OpalDiagnostics.Field {
        OpalDiagnostics.Field(name: "retry_attempt", value: attempt, privacy: .public)
    }

    static func retryDelayMilliseconds(_ milliseconds: Int) -> OpalDiagnostics.Field {
        OpalDiagnostics.Field(name: "retry_delay_ms", value: milliseconds, privacy: .public)
    }

    static func roundState(_ state: OpalFusion.Execution.RoundSubstate) -> OpalDiagnostics.Field {
        OpalDiagnostics.Field(name: "round_state", publicValue: state.rawValue)
    }

    static func settlementState(_ status: OpalFusion.Round.CompletionStatus) -> OpalDiagnostics.Field {
        OpalDiagnostics.Field(name: "settlement_state", publicValue: status.rawValue)
    }

    static func hostResponseClass(_ responseClass: String) -> OpalDiagnostics.Field {
        OpalDiagnostics.Field(name: "host_response_class", publicValue: responseClass)
    }

    static func validationBranch(_ branch: String) -> OpalDiagnostics.Field {
        OpalDiagnostics.Field(name: "validation_branch", publicValue: branch)
    }

    static func reasonCode(_ reasonCode: String) -> OpalDiagnostics.Field {
        OpalDiagnostics.Field(name: "reason_code", publicValue: reasonCode)
    }

    static func protocolErrorIdentifier(_ identifier: String) -> OpalDiagnostics.Field {
        OpalDiagnostics.Field(name: "protocol_error_identifier", publicValue: identifier)
    }

    static func terminal(_ isTerminal: Bool) -> OpalDiagnostics.Field {
        OpalDiagnostics.Field(name: "terminal", value: isTerminal, privacy: .public)
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

    static func hostFailureFields(
        for failure: OpalFusion.Host.ParticipantReservationFailure
    ) -> [OpalDiagnostics.Field] {
        [
            hostResponseClass(participantReservationResponseClass(for: failure)),
            validationBranch("participant_reservation"),
            reasonCode(failure.reason.rawValue)
        ]
    }

    static func hostFailureFields(
        for failure: OpalFusion.Host.TransactionFinalizationFailure
    ) -> [OpalDiagnostics.Field] {
        [
            hostResponseClass(transactionFinalizationResponseClass(for: failure)),
            validationBranch("transaction_finalization"),
            reasonCode(OpalDiagnostics.ErrorCode.resolveOpalFusionCode(for: failure).rawValue)
        ]
    }

    static func workflowFailureFields(
        for failure: OpalFusion.Execution.WorkflowFailure
    ) -> [OpalDiagnostics.Field] {
        let parts = workflowFailureDiagnosticParts(for: failure)
        return [
            validationBranch(parts.validationBranch),
            reasonCode(parts.reasonCode)
        ]
    }
}

private extension OpalDiagnostics.Field {
    static func participantReservationResponseClass(
        for failure: OpalFusion.Host.ParticipantReservationFailure
    ) -> String {
        switch failure {
        case .reservationUnavailable:
            "reservation_unavailable"
        case .hostPolicyRejected:
            "participant_reservation_rejected"
        }
    }

    static func transactionFinalizationResponseClass(
        for failure: OpalFusion.Host.TransactionFinalizationFailure
    ) -> String {
        switch failure {
        case .transactionAssemblyFailed:
            "transaction_assembly_failed"
        case .hostPolicyRejected:
            "transaction_finalization_rejected"
        }
    }

    static func workflowFailureDiagnosticParts(
        for failure: OpalFusion.Execution.WorkflowFailure
    ) -> (validationBranch: String, reasonCode: String) {
        let validationBranch = switch failure {
        case .invalidParticipantReservation:
            "participant_reservation_material"
        case .missingParticipantInputPublicKey:
            "participant_input_public_key"
        case .invalidTransactionTemplate:
            "transaction_template"
        case .protocolValidationFailed:
            "protocol_validation"
        case .unsupportedExecution:
            "unsupported_execution"
        }

        return (
            validationBranch: validationBranch,
            reasonCode: OpalDiagnostics.ErrorCode.resolveOpalFusionCode(for: failure).rawValue
        )
    }

}

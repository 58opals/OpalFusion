// OpalFusion+Execution+WorkflowFailure.swift

extension OpalFusion.Execution {
    enum WorkflowFailure: Swift.Error, Sendable, Equatable {
        case invalidParticipantReservation(String)
        case missingParticipantInputPublicKey(index: Int)
        case invalidTransactionTemplate(String)
        case protocolValidationFailed(String)
        case unsupportedExecution(String)

        var summary: String {
            switch self {
            case let .invalidParticipantReservation(summary):
                summary
            case let .missingParticipantInputPublicKey(index):
                "Reserved input at index \(index) is missing the compressed public key required for standard P2PKH support"
            case let .invalidTransactionTemplate(summary):
                summary
            case let .protocolValidationFailed(summary):
                summary
            case let .unsupportedExecution(summary):
                summary
            }
        }

        var clientError: OpalFusion.Client.Error {
            switch self {
            case .invalidParticipantReservation, .missingParticipantInputPublicKey:
                .hostRejected
            case .invalidTransactionTemplate, .protocolValidationFailed:
                .protocolIncompatible
            case .unsupportedExecution:
                .notImplemented
            }
        }

        var completionStatus: OpalFusion.Round.CompletionStatus {
            switch self {
            case .invalidParticipantReservation, .missingParticipantInputPublicKey, .unsupportedExecution:
                .hostRejected
            case .invalidTransactionTemplate, .protocolValidationFailed:
                .protocolIncompatible
            }
        }
    }
}

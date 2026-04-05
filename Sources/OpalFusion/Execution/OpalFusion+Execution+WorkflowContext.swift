// OpalFusion+Execution+WorkflowContext.swift

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

    struct WorkflowContext: Sendable {
        let buildPlayerCommit: @Sendable (inout OpalFusion.Execution.RoundContext) throws -> OpalFusion.ProtocolModel.PlayerCommit
        let buildCovertComponentMessages: @Sendable (inout OpalFusion.Execution.RoundContext) throws -> [OpalFusion.ProtocolModel.CovertMessage]
        let buildTransactionFinalizationProposal: @Sendable (inout OpalFusion.Execution.RoundContext) throws -> OpalFusion.Host.TransactionFinalizationProposal
        let buildCovertSignatureMessages: @Sendable (inout OpalFusion.Execution.RoundContext) throws -> [OpalFusion.ProtocolModel.CovertMessage]
        let buildMyProofsList: @Sendable (inout OpalFusion.Execution.RoundContext) throws -> OpalFusion.ProtocolModel.MyProofsList
        let buildBlames: @Sendable (inout OpalFusion.Execution.RoundContext) throws -> OpalFusion.ProtocolModel.Blames

        init(
            buildPlayerCommit: @escaping @Sendable (inout OpalFusion.Execution.RoundContext) throws -> OpalFusion.ProtocolModel.PlayerCommit,
            buildCovertComponentMessages: @escaping @Sendable (inout OpalFusion.Execution.RoundContext) throws -> [OpalFusion.ProtocolModel.CovertMessage],
            buildTransactionFinalizationProposal: @escaping @Sendable (inout OpalFusion.Execution.RoundContext) throws -> OpalFusion.Host.TransactionFinalizationProposal,
            buildCovertSignatureMessages: @escaping @Sendable (inout OpalFusion.Execution.RoundContext) throws -> [OpalFusion.ProtocolModel.CovertMessage],
            buildMyProofsList: @escaping @Sendable (inout OpalFusion.Execution.RoundContext) throws -> OpalFusion.ProtocolModel.MyProofsList,
            buildBlames: @escaping @Sendable (inout OpalFusion.Execution.RoundContext) throws -> OpalFusion.ProtocolModel.Blames
        ) {
            self.buildPlayerCommit = buildPlayerCommit
            self.buildCovertComponentMessages = buildCovertComponentMessages
            self.buildTransactionFinalizationProposal = buildTransactionFinalizationProposal
            self.buildCovertSignatureMessages = buildCovertSignatureMessages
            self.buildMyProofsList = buildMyProofsList
            self.buildBlames = buildBlames
        }
    }
}

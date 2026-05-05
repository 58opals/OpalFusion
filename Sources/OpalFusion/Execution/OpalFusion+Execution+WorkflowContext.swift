// OpalFusion+Execution+WorkflowContext.swift

extension OpalFusion.Execution {
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

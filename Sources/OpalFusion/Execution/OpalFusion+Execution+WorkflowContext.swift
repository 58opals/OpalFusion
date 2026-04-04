// OpalFusion+Execution+WorkflowContext.swift

extension OpalFusion.Execution {
    struct WorkflowContext: Sendable {
        let buildPlayerCommit: @Sendable (OpalFusion.Execution.RoundContext) -> OpalFusion.ProtocolModel.PlayerCommit
        let buildCovertComponentMessages: @Sendable (OpalFusion.Execution.RoundContext) -> [OpalFusion.ProtocolModel.CovertMessage]
        let buildTransactionFinalizationProposal: @Sendable (OpalFusion.Execution.RoundContext) -> OpalFusion.Host.TransactionFinalizationProposal
        let buildCovertSignatureMessages: @Sendable (OpalFusion.Execution.RoundContext) -> [OpalFusion.ProtocolModel.CovertMessage]
        let buildMyProofsList: @Sendable (OpalFusion.Execution.RoundContext) -> OpalFusion.ProtocolModel.MyProofsList
        let buildBlames: @Sendable (OpalFusion.Execution.RoundContext) -> OpalFusion.ProtocolModel.Blames

        init(
            buildPlayerCommit: @escaping @Sendable (OpalFusion.Execution.RoundContext) -> OpalFusion.ProtocolModel.PlayerCommit,
            buildCovertComponentMessages: @escaping @Sendable (OpalFusion.Execution.RoundContext) -> [OpalFusion.ProtocolModel.CovertMessage],
            buildTransactionFinalizationProposal: @escaping @Sendable (OpalFusion.Execution.RoundContext) -> OpalFusion.Host.TransactionFinalizationProposal,
            buildCovertSignatureMessages: @escaping @Sendable (OpalFusion.Execution.RoundContext) -> [OpalFusion.ProtocolModel.CovertMessage],
            buildMyProofsList: @escaping @Sendable (OpalFusion.Execution.RoundContext) -> OpalFusion.ProtocolModel.MyProofsList,
            buildBlames: @escaping @Sendable (OpalFusion.Execution.RoundContext) -> OpalFusion.ProtocolModel.Blames
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

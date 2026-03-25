// OpalFusion+Host+TransactionAssembler.swift

public extension OpalFusion.Host {
    protocol TransactionAssembler: Sendable {
        func finalizeTransaction(
            for roundIdentifier: OpalFusion.Round.Identifier,
            proposal: OpalFusion.Host.TransactionFinalizationProposal
        ) async throws -> OpalFusion.Host.FinalizedTransaction
    }
}

// OpalFusion+Host+TransactionAssembler+FinalizeTransactionCompatibility.swift

public extension OpalFusion.Host.TransactionAssembler {
    @available(
        *,
        deprecated,
        renamed: "finalizeFusionTransaction(for:proposal:)",
        message: "Use finalizeFusionTransaction(for:proposal:) to keep the CashFusion signing boundary explicit."
    )
    func finalizeTransaction(
        for roundIdentifier: OpalFusion.Round.Identifier,
        proposal: OpalFusion.Host.TransactionFinalizationProposal
    ) async throws -> OpalFusion.Host.FinalizedTransaction {
        try await finalizeFusionTransaction(
            for: roundIdentifier,
            proposal: proposal
        )
    }
}

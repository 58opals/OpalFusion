// HostTransactionAssemblerAdapter.swift

import OpalFusion

struct HostTransactionAssemblerAdapter: OpalFusion.Host.TransactionAssembler {
    let finalizedTransaction: OpalFusion.Host.FinalizedTransaction

    func finalizeTransaction(
        for roundIdentifier: OpalFusion.Round.Identifier,
        proposal: OpalFusion.Host.TransactionFinalizationProposal
    ) async throws -> OpalFusion.Host.FinalizedTransaction {
        finalizedTransaction
    }
}

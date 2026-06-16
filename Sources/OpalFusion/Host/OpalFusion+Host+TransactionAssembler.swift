// OpalFusion+Host+TransactionAssembler.swift

public extension OpalFusion.Host {
    /// Host callback that validates and signs OpalFusion's unsigned fusion transaction proposal.
    ///
    /// Implementations remain responsible for wallet policy, signing keys, transaction authoring details, persistence, and broadcast decisions.
    protocol TransactionAssembler: Sendable {
        func finalizeFusionTransaction(
            for roundIdentifier: OpalFusion.Round.Identifier,
            proposal: OpalFusion.Host.TransactionFinalizationProposal
        ) async throws -> OpalFusion.Host.FinalizedTransaction
    }
}

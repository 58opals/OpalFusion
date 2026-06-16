// BlockingTransactionAssembler.swift

@testable import OpalFusion

actor BlockingTransactionAssembler: OpalFusion.Host.TransactionAssembler {
    private let finalizedTransaction: OpalFusion.Host.FinalizedTransaction
    private var requestedRoundIdentifiers: [OpalFusion.Round.Identifier] = []
    private var proposals: [OpalFusion.Host.TransactionFinalizationProposal] = []
    private var transactionContinuation: CheckedContinuation<Result<OpalFusion.Host.FinalizedTransaction, Error>, Never>?

    init(
        finalizedTransaction: OpalFusion.Host.FinalizedTransaction
    ) {
        self.finalizedTransaction = finalizedTransaction
    }

    func finalizeFusionTransaction(
        for roundIdentifier: OpalFusion.Round.Identifier,
        proposal: OpalFusion.Host.TransactionFinalizationProposal
    ) async throws -> OpalFusion.Host.FinalizedTransaction {
        requestedRoundIdentifiers.append(roundIdentifier)
        proposals.append(proposal)
        let result = await withCheckedContinuation { continuation in
            transactionContinuation = continuation
        }

        switch result {
        case let .success(transaction):
            return transaction
        case let .failure(error):
            throw error
        }
    }

    var requestedRounds: [OpalFusion.Round.Identifier] {
        requestedRoundIdentifiers
    }

    var recordedProposals: [OpalFusion.Host.TransactionFinalizationProposal] {
        proposals
    }

    func releaseTransaction(
        _ finalizedTransaction: OpalFusion.Host.FinalizedTransaction? = nil
    ) {
        transactionContinuation?.resume(
            returning: .success(finalizedTransaction ?? self.finalizedTransaction)
        )
        transactionContinuation = nil
    }

    func failTransaction(
        _ error: Error
    ) {
        transactionContinuation?.resume(returning: .failure(error))
        transactionContinuation = nil
    }
}

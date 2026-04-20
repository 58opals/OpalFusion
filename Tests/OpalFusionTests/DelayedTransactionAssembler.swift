// DelayedTransactionAssembler.swift

@testable import OpalFusion
import Foundation

actor DelayedTransactionAssembler: OpalFusion.Host.TransactionAssembler {
    private let finalizedTransaction: OpalFusion.Host.FinalizedTransaction
    private let delay: Duration
    private var requestedRoundIdentifiers: [OpalFusion.Round.Identifier] = []
    private var proposals: [OpalFusion.Host.TransactionFinalizationProposal] = []
    private var proposalRecords: [TimedTransactionProposalRecord] = []

    init(
        finalizedTransaction: OpalFusion.Host.FinalizedTransaction,
        delay: Duration = .zero
    ) {
        self.finalizedTransaction = finalizedTransaction
        self.delay = delay
        self.requestedRoundIdentifiers = []
        self.proposals = []
    }

    func finalizeTransaction(
        for roundIdentifier: OpalFusion.Round.Identifier,
        proposal: OpalFusion.Host.TransactionFinalizationProposal
    ) async throws -> OpalFusion.Host.FinalizedTransaction {
        requestedRoundIdentifiers.append(roundIdentifier)
        proposals.append(proposal)
        proposalRecords.append(
            .init(
                roundIdentifier: roundIdentifier,
                proposal: proposal,
                recordedAt: Date()
            )
        )

        if delay > .zero {
            try await Task.sleep(for: delay)
        }

        return finalizedTransaction
    }

    func requestedRounds() -> [OpalFusion.Round.Identifier] {
        requestedRoundIdentifiers
    }

    func recordedProposals() -> [OpalFusion.Host.TransactionFinalizationProposal] {
        proposals
    }

    func timedProposalRecords() -> [TimedTransactionProposalRecord] {
        proposalRecords
    }
}

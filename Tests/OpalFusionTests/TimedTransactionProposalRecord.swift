// TimedTransactionProposalRecord.swift

@testable import OpalFusion
import Foundation

struct TimedTransactionProposalRecord: Sendable {
    let roundIdentifier: OpalFusion.Round.Identifier
    let proposal: OpalFusion.Host.TransactionFinalizationProposal
    let recordedAt: Date
}

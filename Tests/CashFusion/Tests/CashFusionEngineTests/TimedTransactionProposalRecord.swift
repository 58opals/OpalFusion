// TimedTransactionProposalRecord.swift

@testable import CashFusionEngine
@testable import OpalFusionCore
import Foundation

struct TimedTransactionProposalRecord: Sendable {
    let roundIdentifier: OpalFusion.Round.Identifier
    let proposal: OpalFusion.Host.TransactionFinalizationProposal
    let recordedAt: Date
}

// SigningTransactionFixture.swift

@testable import CashFusionEngine
@testable import OpalFusionCore
struct SigningTransactionFixture {
    let transaction: OpalFusion.Host.FinalizedTransaction
    let signature: [UInt8]
}

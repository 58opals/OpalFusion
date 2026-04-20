// SigningTransactionFixture.swift

@testable import OpalFusion

struct SigningTransactionFixture {
    let transaction: OpalFusion.Host.FinalizedTransaction
    let signature: [UInt8]
}

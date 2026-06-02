// TransactionCodecValidator+ValidationGroup4.swift

@testable import OpalFusion
import Testing

extension TransactionCodecValidator {
    @Test("BCH transaction signature hash rejects impossible output amounts")
    func validateSignatureHashRejectsImpossibleOutputAmount() throws {
        let transaction = OpalFusion.Execution.BCHTransaction(
            version: 1,
            inputs: [
                .init(
                    previousTransactionHashLittleEndian: [UInt8](repeating: 0x00, count: 32),
                    previousOutputIndex: 0,
                    unlockingScript: [],
                    sequence: 0xFFFF_FFFF
                )
            ],
            outputs: [
                .init(
                    amountSatoshis: OpalFusion.Execution.ProtocolPrimitives.maximumMoneySatoshis + 1,
                    lockingScript: [0x51]
                )
            ],
            lockTime: 0
        )

        do {
            _ = try transaction.signatureHash(
                forInputAt: 0,
                lockingScript: [0x51],
                amountSatoshis: 1_000
            )
            Issue.record("Expected impossible output amount to fail")
        } catch let error as OpalFusion.Execution.BCHTransactionError {
            #expect(
                error == .malformed(
                    "Transaction output amount exceeds the maximum BCH money supply"
                )
            )
        }
    }
}

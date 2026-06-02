// TransactionCodecValidator+ValidationGroup2.swift

@testable import OpalFusion
import Testing

extension TransactionCodecValidator {
    @Test("BCH transaction serializer rejects zero input and zero output transactions")
    func validateZeroCountTransactionSerializationRejection() throws {
        let output = OpalFusion.Execution.BCHTransaction.Output(
            amountSatoshis: 0,
            lockingScript: [0x51]
        )
        let input = OpalFusion.Execution.BCHTransaction.Input(
            previousTransactionHashLittleEndian: [UInt8](repeating: 0x00, count: 32),
            previousOutputIndex: 0,
            unlockingScript: [],
            sequence: 0xFFFF_FFFF
        )

        do {
            _ = try OpalFusion.Execution.BCHTransaction(
                version: 1,
                inputs: [],
                outputs: [output],
                lockTime: 0
            ).serialize()
            Issue.record("Expected zero-input transaction serialization to fail")
        } catch let error as OpalFusion.Execution.BCHTransactionError {
            #expect(
                error == .malformed("Transaction must contain at least one input")
            )
        }

        do {
            _ = try OpalFusion.Execution.BCHTransaction(
                version: 1,
                inputs: [input],
                outputs: [],
                lockTime: 0
            ).serialize()
            Issue.record("Expected zero-output transaction serialization to fail")
        } catch let error as OpalFusion.Execution.BCHTransactionError {
            #expect(
                error == .malformed("Transaction must contain at least one output")
            )
        }
    }

    @Test("BCH transaction serializer rejects outputs above the maximum money supply")
    func validateTransactionSerializationRejectsImpossibleOutputAmount() throws {
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
            _ = try transaction.serialize()
            Issue.record("Expected impossible output amount serialization to fail")
        } catch let error as OpalFusion.Execution.BCHTransactionError {
            #expect(
                error == .malformed(
                    "Transaction output amount exceeds the maximum BCH money supply"
                )
            )
        }
    }

    @Test("BCH transaction codec rejects output totals above the maximum money supply")
    func validateTransactionCodecRejectsImpossibleOutputTotal() throws {
        let maximumAmount = OpalFusion.Execution.ProtocolPrimitives.maximumMoneySatoshis
        let maximumAmountBytes = withUnsafeBytes(of: maximumAmount.littleEndian) {
            Array($0)
        }
        let transactionBytes =
            [UInt8](arrayLiteral: 0x01, 0x00, 0x00, 0x00)
            + [0x01]
            + [UInt8](repeating: 0x00, count: 32)
            + [0x00, 0x00, 0x00, 0x00]
            + [0x00]
            + [0xFF, 0xFF, 0xFF, 0xFF]
            + [0x02]
            + maximumAmountBytes
            + [0x00]
            + maximumAmountBytes
            + [0x00]
            + [0x00, 0x00, 0x00, 0x00]

        do {
            _ = try OpalFusion.Execution.BCHTransaction.parse(transactionBytes)
            Issue.record("Expected impossible output total to fail parsing")
        } catch let error as OpalFusion.Execution.BCHTransactionError {
            #expect(
                error == .malformed(
                    "Transaction output total exceeds the maximum BCH money supply"
                )
            )
        }

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
                .init(amountSatoshis: maximumAmount, lockingScript: [0x51]),
                .init(amountSatoshis: maximumAmount, lockingScript: [0x51])
            ],
            lockTime: 0
        )

        do {
            _ = try transaction.serialize()
            Issue.record("Expected impossible output total to fail serialization")
        } catch let error as OpalFusion.Execution.BCHTransactionError {
            #expect(
                error == .malformed(
                    "Transaction output total exceeds the maximum BCH money supply"
                )
            )
        }

        do {
            _ = try transaction.signatureHash(
                forInputAt: 0,
                lockingScript: [0x51],
                amountSatoshis: 1_000
            )
            Issue.record("Expected impossible output total to fail signature hashing")
        } catch let error as OpalFusion.Execution.BCHTransactionError {
            #expect(
                error == .malformed(
                    "Transaction output total exceeds the maximum BCH money supply"
                )
            )
        }
    }
}

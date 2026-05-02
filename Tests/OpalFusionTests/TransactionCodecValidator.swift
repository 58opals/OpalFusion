// TransactionCodecValidator.swift

@testable import OpalFusion
import Testing

struct TransactionCodecValidator {
    @Test("BCH transaction parser rejects non-canonical CompactSize encodings")
    func validateNonCanonicalCompactSizeRejection() throws {
        let transactionBytes =
            [UInt8](arrayLiteral: 0x01, 0x00, 0x00, 0x00)
            + [0xFD, 0x01, 0x00]
            + [UInt8](repeating: 0x00, count: 32)
            + [0x00, 0x00, 0x00, 0x00]
            + [0x00]
            + [0xFF, 0xFF, 0xFF, 0xFF]
            + [0x01]
            + [UInt8](repeating: 0x00, count: 8)
            + [0x00]
            + [0x00, 0x00, 0x00, 0x00]

        do {
            _ = try OpalFusion.Execution.BCHTransaction.parse(transactionBytes)
            Issue.record("Expected non-canonical CompactSize encoding to fail")
        } catch let error as OpalFusion.Execution.BCHTransactionError {
            #expect(
                error == .malformed(
                    "CompactSize value used a non-canonical encoding"
                )
            )
        }
    }

    @Test("BCH transaction parser rejects zero input and zero output transactions")
    func validateZeroCountTransactionRejection() throws {
        let zeroInputTransactionBytes =
            [UInt8](arrayLiteral: 0x01, 0x00, 0x00, 0x00)
            + [0x00]
            + [0x01]
            + [UInt8](repeating: 0x00, count: 8)
            + [0x00]
            + [0x00, 0x00, 0x00, 0x00]

        do {
            _ = try OpalFusion.Execution.BCHTransaction.parse(zeroInputTransactionBytes)
            Issue.record("Expected zero-input transaction to fail")
        } catch let error as OpalFusion.Execution.BCHTransactionError {
            #expect(
                error == .malformed("Transaction must contain at least one input")
            )
        }

        let zeroOutputTransactionBytes =
            [UInt8](arrayLiteral: 0x01, 0x00, 0x00, 0x00)
            + [0x01]
            + [UInt8](repeating: 0x00, count: 32)
            + [0x00, 0x00, 0x00, 0x00]
            + [0x00]
            + [0xFF, 0xFF, 0xFF, 0xFF]
            + [0x00]
            + [0x00, 0x00, 0x00, 0x00]

        do {
            _ = try OpalFusion.Execution.BCHTransaction.parse(zeroOutputTransactionBytes)
            Issue.record("Expected zero-output transaction to fail")
        } catch let error as OpalFusion.Execution.BCHTransactionError {
            #expect(
                error == .malformed("Transaction must contain at least one output")
            )
        }
    }

    @Test("BCH transaction parser rejects outputs above the maximum money supply")
    func validateTransactionParseRejectsImpossibleOutputAmount() throws {
        let impossibleAmount = OpalFusion.Execution.ProtocolPrimitives.maximumMoneySatoshis + 1
        let impossibleAmountBytes = withUnsafeBytes(of: impossibleAmount.littleEndian) {
            Array($0)
        }
        let transactionBytes =
            [UInt8](arrayLiteral: 0x01, 0x00, 0x00, 0x00)
            + [0x01]
            + [UInt8](repeating: 0x00, count: 32)
            + [0x00, 0x00, 0x00, 0x00]
            + [0x00]
            + [0xFF, 0xFF, 0xFF, 0xFF]
            + [0x01]
            + impossibleAmountBytes
            + [0x00]
            + [0x00, 0x00, 0x00, 0x00]

        do {
            _ = try OpalFusion.Execution.BCHTransaction.parse(transactionBytes)
            Issue.record("Expected impossible output amount to fail")
        } catch let error as OpalFusion.Execution.BCHTransactionError {
            #expect(
                error == .malformed(
                    "Transaction output amount exceeds the maximum BCH money supply"
                )
            )
        }
    }

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
            ).serialized()
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
            ).serialized()
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
            _ = try transaction.serialized()
            Issue.record("Expected impossible output amount serialization to fail")
        } catch let error as OpalFusion.Execution.BCHTransactionError {
            #expect(
                error == .malformed(
                    "Transaction output amount exceeds the maximum BCH money supply"
                )
            )
        }
    }

    @Test("BCH transaction signature hash rejects malformed previous hashes")
    func validateSignatureHashRejectsMalformedPreviousHash() throws {
        let transaction = OpalFusion.Execution.BCHTransaction(
            version: 1,
            inputs: [
                .init(
                    previousTransactionHashLittleEndian: [UInt8](repeating: 0x00, count: 31),
                    previousOutputIndex: 0,
                    unlockingScript: [],
                    sequence: 0xFFFF_FFFF
                )
            ],
            outputs: [
                .init(
                    amountSatoshis: 1_000,
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
            Issue.record("Expected malformed previous hash to fail")
        } catch let error as OpalFusion.Execution.BCHTransactionError {
            #expect(
                error == .malformed("Transaction input previous hash must be 32 bytes")
            )
        }
    }

    @Test("BCH transaction signature hash rejects zero output transactions")
    func validateSignatureHashRejectsZeroOutputs() throws {
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
            outputs: [],
            lockTime: 0
        )

        do {
            _ = try transaction.signatureHash(
                forInputAt: 0,
                lockingScript: [0x51],
                amountSatoshis: 1_000
            )
            Issue.record("Expected zero-output transaction signature hash to fail")
        } catch let error as OpalFusion.Execution.BCHTransactionError {
            #expect(
                error == .malformed("Transaction must contain at least one output")
            )
        }
    }

    @Test("BCH transaction signature hash rejects impossible spent amounts")
    func validateSignatureHashRejectsImpossibleSpentAmount() throws {
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
                    amountSatoshis: 1_000,
                    lockingScript: [0x51]
                )
            ],
            lockTime: 0
        )

        do {
            _ = try transaction.signatureHash(
                forInputAt: 0,
                lockingScript: [0x51],
                amountSatoshis: OpalFusion.Execution.ProtocolPrimitives.maximumMoneySatoshis + 1
            )
            Issue.record("Expected impossible spent amount to fail")
        } catch let error as OpalFusion.Execution.BCHTransactionError {
            #expect(
                error == .malformed(
                    "Transaction input amount exceeds the maximum BCH money supply"
                )
            )
        }
    }

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

// TransactionCodecValidator+ValidationGroup3.swift

@testable import OpalFusion
import Testing

extension TransactionCodecValidator {
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

    @Test("BCH transaction signature hash rejects unsupported sighash types")
    func validateSignatureHashRejectsUnsupportedSighashType() throws {
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
                amountSatoshis: 1_000,
                sighashType: 0x43
            )
            Issue.record("Expected unsupported sighash type to fail")
        } catch let error as OpalFusion.Execution.BCHTransactionError {
            #expect(
                error == .malformed("Unsupported BCH signature hash type")
            )
        }
    }

    @Test("BCH transaction unlocking script setter rejects out-of-bounds input indices")
    func validateUnlockingScriptSetterRejectsOutOfBoundsInput() throws {
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
            _ = try transaction.settingUnlockingScript([0x51], at: 1)
            Issue.record("Expected out-of-bounds unlocking script input index to fail")
        } catch let error as OpalFusion.Execution.BCHTransactionError {
            #expect(
                error == .malformed("Transaction input index 1 is out of bounds")
            )
        }
    }
}

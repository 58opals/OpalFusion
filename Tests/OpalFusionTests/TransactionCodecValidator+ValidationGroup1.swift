// TransactionCodecValidator+ValidationGroup1.swift

@testable import OpalFusion
import Testing

extension TransactionCodecValidator {
    @Test("BCH transaction parser preserves signed version bit patterns")
    func validateSignedVersionBitPatternParsing() throws {
        let transactionBytes =
            [UInt8](arrayLiteral: 0xFF, 0xFF, 0xFF, 0xFF)
            + [0x01]
            + [UInt8](repeating: 0x00, count: 32)
            + [0x00, 0x00, 0x00, 0x00]
            + [0x00]
            + [0xFF, 0xFF, 0xFF, 0xFF]
            + [0x01]
            + [UInt8](repeating: 0x00, count: 8)
            + [0x00]
            + [0x00, 0x00, 0x00, 0x00]

        let transaction = try OpalFusion.Execution.BCHTransaction.parse(transactionBytes)

        #expect(transaction.version == -1)
        #expect(try transaction.serialize() == transactionBytes)
    }

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

    @Test("BCH transaction parser rejects oversized CompactSize lengths without trapping")
    func validateOversizedCompactSizeLengthRejection() throws {
        let oversizedLengthBytes = withUnsafeBytes(of: UInt64(Int.max).littleEndian) {
            Array($0)
        }
        let transactionBytes =
            [UInt8](arrayLiteral: 0x01, 0x00, 0x00, 0x00)
            + [0x01]
            + [UInt8](repeating: 0x00, count: 32)
            + [0x00, 0x00, 0x00, 0x00]
            + [0xFF]
            + oversizedLengthBytes

        do {
            _ = try OpalFusion.Execution.BCHTransaction.parse(transactionBytes)
            Issue.record("Expected oversized unlocking script length to fail")
        } catch let error as OpalFusion.Execution.BCHTransactionError {
            #expect(
                error == .malformed("Unexpected end of transaction bytes")
            )
        }
    }

    @Test("BCH transaction parser rejects impossible vector counts without reserving huge memory")
    func validateImpossibleVectorCountRejection() throws {
        let impossibleCountBytes = withUnsafeBytes(of: UInt64(Int.max).littleEndian) {
            Array($0)
        }
        let impossibleInputCountBytes =
            [UInt8](arrayLiteral: 0x01, 0x00, 0x00, 0x00)
            + [0xFF]
            + impossibleCountBytes

        do {
            _ = try OpalFusion.Execution.BCHTransaction.parse(impossibleInputCountBytes)
            Issue.record("Expected impossible input count to fail")
        } catch let error as OpalFusion.Execution.BCHTransactionError {
            #expect(error == .malformed("Unexpected end of transaction bytes"))
        }

        let impossibleOutputCountBytes =
            [UInt8](arrayLiteral: 0x01, 0x00, 0x00, 0x00)
            + [0x01]
            + [UInt8](repeating: 0x00, count: 32)
            + [0x00, 0x00, 0x00, 0x00]
            + [0x00]
            + [0xFF, 0xFF, 0xFF, 0xFF]
            + [0xFF]
            + impossibleCountBytes

        do {
            _ = try OpalFusion.Execution.BCHTransaction.parse(impossibleOutputCountBytes)
            Issue.record("Expected impossible output count to fail")
        } catch let error as OpalFusion.Execution.BCHTransactionError {
            #expect(error == .malformed("Unexpected end of transaction bytes"))
        }
    }
}

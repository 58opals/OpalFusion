// OpalFusion+Execution+TransactionCodec.swift

import Foundation

extension OpalFusion.Execution {
    enum BCHTransactionError: Swift.Error, Sendable, Equatable {
        case malformed(String)
        case templateMismatch(String)
        case unsupportedInput(String)
    }

    struct BCHTransaction: Sendable, Equatable {
        struct Input: Sendable, Equatable {
            var previousTransactionHashLittleEndian: [UInt8]
            var previousOutputIndex: UInt32
            var unlockingScript: [UInt8]
            var sequence: UInt32
        }

        struct Output: Sendable, Equatable {
            var amountSatoshis: UInt64
            var lockingScript: [UInt8]
        }

        var version: Int32
        var inputs: [OpalFusion.Execution.BCHTransaction.Input]
        var outputs: [OpalFusion.Execution.BCHTransaction.Output]
        var lockTime: UInt32

        func serialized() throws -> [UInt8] {
            guard inputs.isEmpty == false else {
                throw OpalFusion.Execution.BCHTransactionError.malformed(
                    "Transaction must contain at least one input"
                )
            }

            guard outputs.isEmpty == false else {
                throw OpalFusion.Execution.BCHTransactionError.malformed(
                    "Transaction must contain at least one output"
                )
            }

            var bytes = [UInt8]()
            bytes.append(contentsOf: version.littleEndianBytes)
            bytes.append(contentsOf: try CompactSize.encode(inputs.count))
            for input in inputs {
                guard input.previousTransactionHashLittleEndian.count == 32 else {
                    throw OpalFusion.Execution.BCHTransactionError.malformed(
                        "Transaction input previous hash must be 32 bytes"
                    )
                }
                bytes.append(contentsOf: input.previousTransactionHashLittleEndian)
                bytes.append(contentsOf: input.previousOutputIndex.littleEndianBytes)
                bytes.append(contentsOf: try CompactSize.encode(input.unlockingScript.count))
                bytes.append(contentsOf: input.unlockingScript)
                bytes.append(contentsOf: input.sequence.littleEndianBytes)
            }

            bytes.append(contentsOf: try CompactSize.encode(outputs.count))
            for output in outputs {
                guard output.amountSatoshis <= OpalFusion.Execution.ProtocolPrimitives.maximumMoneySatoshis else {
                    throw OpalFusion.Execution.BCHTransactionError.malformed(
                        "Transaction output amount exceeds the maximum BCH money supply"
                    )
                }

                bytes.append(contentsOf: output.amountSatoshis.littleEndianBytes)
                bytes.append(contentsOf: try CompactSize.encode(output.lockingScript.count))
                bytes.append(contentsOf: output.lockingScript)
            }
            bytes.append(contentsOf: lockTime.littleEndianBytes)
            return bytes
        }

        func settingUnlockingScript(
            _ unlockingScript: [UInt8],
            at inputIndex: Int
        ) -> OpalFusion.Execution.BCHTransaction {
            var copy = self
            copy.inputs[inputIndex].unlockingScript = unlockingScript
            return copy
        }

        func signatureHash(
            forInputAt inputIndex: Int,
            lockingScript: [UInt8],
            amountSatoshis: UInt64,
            sighashType: UInt32 = 0x41
        ) throws -> [UInt8] {
            guard inputs.indices.contains(inputIndex) else {
                throw OpalFusion.Execution.BCHTransactionError.malformed(
                    "Transaction input index \(inputIndex) is out of bounds"
                )
            }
            guard inputs.allSatisfy({ $0.previousTransactionHashLittleEndian.count == 32 }) else {
                throw OpalFusion.Execution.BCHTransactionError.malformed(
                    "Transaction input previous hash must be 32 bytes"
                )
            }
            guard amountSatoshis <= OpalFusion.Execution.ProtocolPrimitives.maximumMoneySatoshis else {
                throw OpalFusion.Execution.BCHTransactionError.malformed(
                    "Transaction input amount exceeds the maximum BCH money supply"
                )
            }
            guard outputs.isEmpty == false else {
                throw OpalFusion.Execution.BCHTransactionError.malformed(
                    "Transaction must contain at least one output"
                )
            }

            let hashPrevouts = OpalFusion.Execution.ProtocolPrimitives.hash256(
                inputs.flatMap { input in
                    input.previousTransactionHashLittleEndian
                        + input.previousOutputIndex.littleEndianBytes
                }
            )
            let hashSequence = OpalFusion.Execution.ProtocolPrimitives.hash256(
                inputs.flatMap { $0.sequence.littleEndianBytes }
            )
            var serializedOutputs = [UInt8]()
            for output in outputs {
                guard output.amountSatoshis <= OpalFusion.Execution.ProtocolPrimitives.maximumMoneySatoshis else {
                    throw OpalFusion.Execution.BCHTransactionError.malformed(
                        "Transaction output amount exceeds the maximum BCH money supply"
                    )
                }

                serializedOutputs.append(contentsOf: output.amountSatoshis.littleEndianBytes)
                serializedOutputs.append(
                    contentsOf: try CompactSize.encode(output.lockingScript.count)
                )
                serializedOutputs.append(contentsOf: output.lockingScript)
            }
            let hashOutputs = OpalFusion.Execution.ProtocolPrimitives.hash256(
                serializedOutputs
            )
            let input = inputs[inputIndex]
            var preimage = [UInt8]()
            preimage.append(contentsOf: version.littleEndianBytes)
            preimage.append(contentsOf: hashPrevouts)
            preimage.append(contentsOf: hashSequence)
            preimage.append(contentsOf: input.previousTransactionHashLittleEndian)
            preimage.append(contentsOf: input.previousOutputIndex.littleEndianBytes)
            preimage.append(contentsOf: try CompactSize.encode(lockingScript.count))
            preimage.append(contentsOf: lockingScript)
            preimage.append(contentsOf: amountSatoshis.littleEndianBytes)
            preimage.append(contentsOf: input.sequence.littleEndianBytes)
            preimage.append(contentsOf: hashOutputs)
            preimage.append(contentsOf: lockTime.littleEndianBytes)
            preimage.append(contentsOf: sighashType.littleEndianBytes)
            return OpalFusion.Execution.ProtocolPrimitives.hash256(preimage)
        }

        static func parse(
            _ bytes: [UInt8]
        ) throws -> OpalFusion.Execution.BCHTransaction {
            var cursor = 0
            let version = try Int32(
                littleEndianBytes: readBytes(count: 4, from: bytes, cursor: &cursor)
            )

            let inputCount = try CompactSize.decode(from: bytes, cursor: &cursor)
            guard inputCount > 0 else {
                throw OpalFusion.Execution.BCHTransactionError.malformed(
                    "Transaction must contain at least one input"
                )
            }

            var inputs: [OpalFusion.Execution.BCHTransaction.Input] = []
            inputs.reserveCapacity(inputCount)
            for _ in 0..<inputCount {
                let previousTransactionHashLittleEndian = try readBytes(
                    count: 32,
                    from: bytes,
                    cursor: &cursor
                )
                let previousOutputIndex = try UInt32(
                    littleEndianBytes: readBytes(count: 4, from: bytes, cursor: &cursor)
                )
                let unlockingScriptLength = try CompactSize.decode(from: bytes, cursor: &cursor)
                let unlockingScript = try readBytes(
                    count: unlockingScriptLength,
                    from: bytes,
                    cursor: &cursor
                )
                let sequence = try UInt32(
                    littleEndianBytes: readBytes(count: 4, from: bytes, cursor: &cursor)
                )
                inputs.append(
                    .init(
                        previousTransactionHashLittleEndian: previousTransactionHashLittleEndian,
                        previousOutputIndex: previousOutputIndex,
                        unlockingScript: unlockingScript,
                        sequence: sequence
                    )
                )
            }

            let outputCount = try CompactSize.decode(from: bytes, cursor: &cursor)
            guard outputCount > 0 else {
                throw OpalFusion.Execution.BCHTransactionError.malformed(
                    "Transaction must contain at least one output"
                )
            }

            var outputs: [OpalFusion.Execution.BCHTransaction.Output] = []
            outputs.reserveCapacity(outputCount)
            for _ in 0..<outputCount {
                let amountSatoshis = try UInt64(
                    littleEndianBytes: readBytes(count: 8, from: bytes, cursor: &cursor)
                )
                guard amountSatoshis <= OpalFusion.Execution.ProtocolPrimitives.maximumMoneySatoshis else {
                    throw OpalFusion.Execution.BCHTransactionError.malformed(
                        "Transaction output amount exceeds the maximum BCH money supply"
                    )
                }

                let lockingScriptLength = try CompactSize.decode(from: bytes, cursor: &cursor)
                let lockingScript = try readBytes(
                    count: lockingScriptLength,
                    from: bytes,
                    cursor: &cursor
                )
                outputs.append(
                    .init(
                        amountSatoshis: amountSatoshis,
                        lockingScript: lockingScript
                    )
                )
            }

            let lockTime = try UInt32(
                littleEndianBytes: readBytes(count: 4, from: bytes, cursor: &cursor)
            )
            guard cursor == bytes.count else {
                throw OpalFusion.Execution.BCHTransactionError.malformed(
                    "Transaction bytes contained trailing data"
                )
            }

            return .init(
                version: version,
                inputs: inputs,
                outputs: outputs,
                lockTime: lockTime
            )
        }
    }
}

private enum CompactSize {
    static func encode(_ value: Int) throws -> [UInt8] {
        guard value >= 0 else {
            throw OpalFusion.Execution.BCHTransactionError.malformed(
                "CompactSize value must be non-negative"
            )
        }
        if value < 0xFD {
            return [UInt8(value)]
        }
        if value <= Int(UInt16.max) {
            return [0xFD] + UInt16(value).littleEndianBytes
        }
        if value <= Int(UInt32.max) {
            return [0xFE] + UInt32(value).littleEndianBytes
        }
        return [0xFF] + UInt64(value).littleEndianBytes
    }

    static func decode(
        from bytes: [UInt8],
        cursor: inout Int
    ) throws -> Int {
        let prefix = try readBytes(count: 1, from: bytes, cursor: &cursor)[0]
        switch prefix {
        case 0x00...0xFC:
            return Int(prefix)
        case 0xFD:
            let value = try UInt16(
                littleEndianBytes: readBytes(count: 2, from: bytes, cursor: &cursor)
            )
            guard value >= 0xFD else {
                throw OpalFusion.Execution.BCHTransactionError.malformed(
                    "CompactSize value used a non-canonical encoding"
                )
            }
            return Int(value)
        case 0xFE:
            let value = try UInt32(
                littleEndianBytes: readBytes(count: 4, from: bytes, cursor: &cursor)
            )
            guard value > UInt32(UInt16.max) else {
                throw OpalFusion.Execution.BCHTransactionError.malformed(
                    "CompactSize value used a non-canonical encoding"
                )
            }
            return Int(value)
        default:
            let value = try UInt64(
                littleEndianBytes: readBytes(count: 8, from: bytes, cursor: &cursor)
            )
            guard value > UInt64(UInt32.max) else {
                throw OpalFusion.Execution.BCHTransactionError.malformed(
                    "CompactSize value used a non-canonical encoding"
                )
            }
            guard value <= UInt64(Int.max) else {
                throw OpalFusion.Execution.BCHTransactionError.malformed(
                    "CompactSize value exceeded the supported range"
                )
            }
            return Int(value)
        }
    }
}

private func readBytes(
    count: Int,
    from bytes: [UInt8],
    cursor: inout Int
) throws -> [UInt8] {
    guard count >= 0,
          cursor >= 0,
          cursor <= bytes.count,
          count <= bytes.count - cursor else {
        throw OpalFusion.Execution.BCHTransactionError.malformed(
            "Unexpected end of transaction bytes"
        )
    }
    defer { cursor += count }
    return Array(bytes[cursor..<(cursor + count)])
}

private extension Int32 {
    var littleEndianBytes: [UInt8] {
        withUnsafeBytes(of: self.littleEndian) { Array($0) }
    }

    init(littleEndianBytes: [UInt8]) throws {
        guard littleEndianBytes.count == 4 else {
            throw OpalFusion.Execution.BCHTransactionError.malformed(
                "Expected 4 bytes for Int32"
            )
        }
        self = littleEndianBytes.enumerated().reduce(0) { partial, element in
            partial | (Int32(element.element) << (8 * element.offset))
        }
    }
}

private extension UInt16 {
    var littleEndianBytes: [UInt8] {
        withUnsafeBytes(of: self.littleEndian) { Array($0) }
    }

    init(littleEndianBytes: [UInt8]) throws {
        guard littleEndianBytes.count == 2 else {
            throw OpalFusion.Execution.BCHTransactionError.malformed(
                "Expected 2 bytes for UInt16"
            )
        }
        self = littleEndianBytes.enumerated().reduce(0) { partial, element in
            partial | (UInt16(element.element) << (8 * element.offset))
        }
    }
}

private extension UInt32 {
    var littleEndianBytes: [UInt8] {
        withUnsafeBytes(of: self.littleEndian) { Array($0) }
    }

    init(littleEndianBytes: [UInt8]) throws {
        guard littleEndianBytes.count == 4 else {
            throw OpalFusion.Execution.BCHTransactionError.malformed(
                "Expected 4 bytes for UInt32"
            )
        }
        self = littleEndianBytes.enumerated().reduce(0) { partial, element in
            partial | (UInt32(element.element) << (8 * element.offset))
        }
    }
}

private extension UInt64 {
    var littleEndianBytes: [UInt8] {
        withUnsafeBytes(of: self.littleEndian) { Array($0) }
    }

    init(littleEndianBytes: [UInt8]) throws {
        guard littleEndianBytes.count == 8 else {
            throw OpalFusion.Execution.BCHTransactionError.malformed(
                "Expected 8 bytes for UInt64"
            )
        }
        self = littleEndianBytes.enumerated().reduce(0) { partial, element in
            partial | (UInt64(element.element) << (8 * element.offset))
        }
    }
}

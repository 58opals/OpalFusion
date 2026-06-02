// OpalFusion+Execution+BCHTransaction+ImplementationGroup2.swift

import Foundation

extension OpalFusion.Execution.BCHTransaction {
    static func parse(
        _ bytes: [UInt8]
    ) throws -> OpalFusion.Execution.BCHTransaction {
        var cursor = 0
        let version = try Int32(
            opalFusionLittleEndianBytes: Self.readBytes(count: 4, from: bytes, cursor: &cursor)
        )

        let inputCount = try Self.decodeCompactSize(from: bytes, cursor: &cursor)
        guard inputCount > 0 else {
            throw OpalFusion.Execution.BCHTransactionError.malformed(
                "Transaction must contain at least one input"
            )
        }
        try Self.validateVectorCount(
            inputCount,
            minimumBytesPerElement: 41,
            remainingByteCount: bytes.count - cursor
        )

        var inputs: [OpalFusion.Execution.BCHTransaction.Input] = []
        inputs.reserveCapacity(inputCount)
        for _ in 0..<inputCount {
            let previousTransactionHashLittleEndian = try Self.readBytes(
                count: 32,
                from: bytes,
                cursor: &cursor
            )
            let previousOutputIndex = try UInt32(
                opalFusionLittleEndianBytes: Self.readBytes(count: 4, from: bytes, cursor: &cursor)
            )
            let unlockingScriptLength = try Self.decodeCompactSize(from: bytes, cursor: &cursor)
            let unlockingScript = try Self.readBytes(
                count: unlockingScriptLength,
                from: bytes,
                cursor: &cursor
            )
            let sequence = try UInt32(
                opalFusionLittleEndianBytes: Self.readBytes(count: 4, from: bytes, cursor: &cursor)
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

        let outputCount = try Self.decodeCompactSize(from: bytes, cursor: &cursor)
        guard outputCount > 0 else {
            throw OpalFusion.Execution.BCHTransactionError.malformed(
                "Transaction must contain at least one output"
            )
        }
        try Self.validateVectorCount(
            outputCount,
            minimumBytesPerElement: 9,
            remainingByteCount: bytes.count - cursor
        )

        var outputs: [OpalFusion.Execution.BCHTransaction.Output] = []
        outputs.reserveCapacity(outputCount)
        var outputTotalSatoshis: UInt64 = 0
        for _ in 0..<outputCount {
            let amountSatoshis = try UInt64(
                opalFusionLittleEndianBytes: Self.readBytes(count: 8, from: bytes, cursor: &cursor)
            )
            guard amountSatoshis <= OpalFusion.Execution.ProtocolPrimitives.maximumMoneySatoshis else {
                throw OpalFusion.Execution.BCHTransactionError.malformed(
                    "Transaction output amount exceeds the maximum BCH money supply"
                )
            }
            outputTotalSatoshis = try Self.addingOutputAmount(
                amountSatoshis,
                to: outputTotalSatoshis
            )

            let lockingScriptLength = try Self.decodeCompactSize(from: bytes, cursor: &cursor)
            let lockingScript = try Self.readBytes(
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
            opalFusionLittleEndianBytes: Self.readBytes(count: 4, from: bytes, cursor: &cursor)
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

    func serializeOutputs() throws -> [UInt8] {
        var bytes = [UInt8]()
        var outputTotalSatoshis: UInt64 = 0
        for output in outputs {
            guard output.amountSatoshis <= OpalFusion.Execution.ProtocolPrimitives.maximumMoneySatoshis else {
                throw OpalFusion.Execution.BCHTransactionError.malformed(
                    "Transaction output amount exceeds the maximum BCH money supply"
                )
            }
            outputTotalSatoshis = try Self.addingOutputAmount(
                output.amountSatoshis,
                to: outputTotalSatoshis
            )

            bytes.append(contentsOf: output.amountSatoshis.opalFusionLittleEndianBytes)
            bytes.append(contentsOf: try Self.encodeCompactSize(output.lockingScript.count))
            bytes.append(contentsOf: output.lockingScript)
        }
        return bytes
    }

    static func encodeCompactSize(_ value: Int) throws -> [UInt8] {
        guard value >= 0 else {
            throw OpalFusion.Execution.BCHTransactionError.malformed(
                "CompactSize value must be non-negative"
            )
        }
        if value < 0xFD {
            return [UInt8(value)]
        }
        if value <= Int(UInt16.max) {
            return [0xFD] + UInt16(value).opalFusionLittleEndianBytes
        }
        if value <= Int(UInt32.max) {
            return [0xFE] + UInt32(value).opalFusionLittleEndianBytes
        }
        return [0xFF] + UInt64(value).opalFusionLittleEndianBytes
    }
}

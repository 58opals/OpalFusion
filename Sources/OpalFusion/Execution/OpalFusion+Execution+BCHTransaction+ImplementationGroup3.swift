// OpalFusion+Execution+BCHTransaction+ImplementationGroup3.swift

import Foundation

extension OpalFusion.Execution.BCHTransaction {
    static func decodeCompactSize(
        from bytes: [UInt8],
        cursor: inout Int
    ) throws -> Int {
        let prefix = try Self.readBytes(count: 1, from: bytes, cursor: &cursor)[0]
        switch prefix {
        case 0x00...0xFC:
            return Int(prefix)
        case 0xFD:
            let value = try UInt16(
                opalFusionLittleEndianBytes: Self.readBytes(count: 2, from: bytes, cursor: &cursor)
            )
            guard value >= 0xFD else {
                throw OpalFusion.Execution.BCHTransactionError.malformed(
                    "CompactSize value used a non-canonical encoding"
                )
            }
            return Int(value)
        case 0xFE:
            let value = try UInt32(
                opalFusionLittleEndianBytes: Self.readBytes(count: 4, from: bytes, cursor: &cursor)
            )
            guard value > UInt32(UInt16.max) else {
                throw OpalFusion.Execution.BCHTransactionError.malformed(
                    "CompactSize value used a non-canonical encoding"
                )
            }
            return Int(value)
        default:
            let value = try UInt64(
                opalFusionLittleEndianBytes: Self.readBytes(count: 8, from: bytes, cursor: &cursor)
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

    static func readBytes(
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

    static func addingOutputAmount(
        _ amountSatoshis: UInt64,
        to totalSatoshis: UInt64
    ) throws -> UInt64 {
        let (newTotal, overflow) = totalSatoshis.addingReportingOverflow(amountSatoshis)
        guard overflow == false,
              newTotal <= OpalFusion.Execution.ProtocolPrimitives.maximumMoneySatoshis else {
            throw OpalFusion.Execution.BCHTransactionError.malformed(
                "Transaction output total exceeds the maximum BCH money supply"
            )
        }
        return newTotal
    }

    static func validateVectorCount(
        _ count: Int,
        minimumBytesPerElement: Int,
        remainingByteCount: Int
    ) throws {
        guard count <= remainingByteCount / minimumBytesPerElement else {
            throw OpalFusion.Execution.BCHTransactionError.malformed(
                "Unexpected end of transaction bytes"
            )
        }
    }
}

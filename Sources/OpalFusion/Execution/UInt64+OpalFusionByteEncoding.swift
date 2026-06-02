// UInt64+OpalFusionByteEncoding.swift

extension UInt64 {
    var opalFusionBigEndianBytes: [UInt8] {
        withUnsafeBytes(of: bigEndian) { Array($0) }
    }

    var opalFusionLittleEndianBytes: [UInt8] {
        withUnsafeBytes(of: littleEndian) { Array($0) }
    }

    init(opalFusionBigEndianBytes bytes: [UInt8]) {
        precondition(bytes.count == 8)
        self = bytes.reduce(0) { ($0 << 8) | UInt64($1) }
    }

    init(opalFusionLittleEndianBytes bytes: [UInt8]) throws {
        guard bytes.count == 8 else {
            throw OpalFusion.Execution.BCHTransactionError.malformed(
                "Expected 8 bytes for UInt64"
            )
        }
        self = bytes.enumerated().reduce(0) { partial, element in
            partial | (UInt64(element.element) << (8 * element.offset))
        }
    }
}

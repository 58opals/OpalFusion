// UInt32+OpalFusionByteEncoding.swift

extension UInt32 {
    var opalFusionBigEndianBytes: [UInt8] {
        withUnsafeBytes(of: bigEndian) { Array($0) }
    }

    var opalFusionLittleEndianBytes: [UInt8] {
        withUnsafeBytes(of: littleEndian) { Array($0) }
    }

    init(opalFusionLittleEndianBytes bytes: [UInt8]) throws {
        guard bytes.count == 4 else {
            throw OpalFusion.Execution.BCHTransactionError.malformed(
                "Expected 4 bytes for UInt32"
            )
        }
        self = bytes.enumerated().reduce(0) { partial, element in
            partial | (UInt32(element.element) << (8 * element.offset))
        }
    }
}

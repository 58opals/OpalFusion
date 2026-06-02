// UInt16+OpalFusionByteEncoding.swift

extension UInt16 {
    var opalFusionLittleEndianBytes: [UInt8] {
        withUnsafeBytes(of: littleEndian) { Array($0) }
    }

    init(opalFusionLittleEndianBytes bytes: [UInt8]) throws {
        guard bytes.count == 2 else {
            throw OpalFusion.Execution.BCHTransactionError.malformed(
                "Expected 2 bytes for UInt16"
            )
        }
        self = bytes.enumerated().reduce(0) { partial, element in
            partial | (UInt16(element.element) << (8 * element.offset))
        }
    }
}

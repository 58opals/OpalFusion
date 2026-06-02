// Int32+OpalFusionByteEncoding.swift

extension Int32 {
    var opalFusionLittleEndianBytes: [UInt8] {
        withUnsafeBytes(of: littleEndian) { Array($0) }
    }

    init(opalFusionLittleEndianBytes bytes: [UInt8]) throws {
        guard bytes.count == 4 else {
            throw OpalFusion.Execution.BCHTransactionError.malformed(
                "Expected 4 bytes for Int32"
            )
        }
        let bitPattern = bytes.enumerated().reduce(UInt32(0)) { partial, element in
            partial | (UInt32(element.element) << (8 * element.offset))
        }
        self = Int32(bitPattern: bitPattern)
    }
}

// OpalFusion+Mosaic+CanonicalCodingError.swift

extension OpalFusion.Mosaic {
    enum CanonicalCodingError: Swift.Error, Equatable, Sendable {
        case lengthExceedsUInt32(Int)
        case truncatedInput(
            expectedByteCount: Int,
            remainingByteCount: Int
        )
        case invalidBoolean(UInt8)
        case invalidUTF8Text
        case nonPrintableASCIIText
        case duplicateSetMember
        case nonCanonicalSetOrdering
        case trailingBytes(Int)
    }
}

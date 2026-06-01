// OpalFusion+Wire+CashFusionProtobufCodingError.swift

extension OpalFusion.Wire {
    enum CashFusionProtobufCodingError: Swift.Error, Equatable {
        case invalidFieldNumber(Int)
        case invalidWireKind(Int)
        case varintOverflow
        case truncatedInput
        case lengthDelimitedValueOutOfBounds(length: UInt64, remainingByteCount: Int)
        case wireKindMismatch(
            expected: OpalFusion.Wire.CashFusionProtobufWireKind,
            actual: OpalFusion.Wire.CashFusionProtobufWireKind
        )
        case uint32ValueOutOfRange(UInt64)
        case invalidUTF8String
        case missingRequiredField(messageName: String, fieldNumber: Int)
        case conflictingOneOfField(messageName: String, fieldNumber: Int)
    }
}

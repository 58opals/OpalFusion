// OpalFusion+Wire+CashFusionProtobufWireKind.swift

extension OpalFusion.Wire {
    enum CashFusionProtobufWireKind: Int, Sendable, Equatable {
        case varint = 0
        case fixed64 = 1
        case lengthDelimited = 2
        case fixed32 = 5

        init(rawWireKind: UInt64) throws {
            guard let wireKind = Self(rawValue: Int(rawWireKind)) else {
                throw OpalFusion.Wire.CashFusionProtobufCodingError.invalidWireKind(
                    Int(rawWireKind)
                )
            }
            self = wireKind
        }
    }
}

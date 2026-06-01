// OpalFusion+Wire+CashFusionProtobufFieldHeader.swift

extension OpalFusion.Wire {
    struct CashFusionProtobufFieldHeader: Sendable, Equatable {
        static let maximumFieldNumber = 536_870_911

        let number: Int
        let wireKind: OpalFusion.Wire.CashFusionProtobufWireKind

        init(
            number: Int,
            wireKind: OpalFusion.Wire.CashFusionProtobufWireKind
        ) throws {
            try Self.validateFieldNumber(number)
            self.number = number
            self.wireKind = wireKind
        }

        static func validateFieldNumber(_ fieldNumber: Int) throws {
            guard fieldNumber > 0, fieldNumber <= maximumFieldNumber else {
                throw OpalFusion.Wire.CashFusionProtobufCodingError.invalidFieldNumber(
                    fieldNumber
                )
            }
        }
    }
}

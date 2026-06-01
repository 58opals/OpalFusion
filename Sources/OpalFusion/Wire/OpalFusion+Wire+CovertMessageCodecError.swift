// OpalFusion+Wire+CovertMessageCodecError.swift

extension OpalFusion.Wire {
    enum CovertMessageCodecError: Swift.Error, Equatable {
        case missingCovertMessageCase
        case missingCovertResponseCase
        case protobufCodingFailed(String)
    }
}

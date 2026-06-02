// OpalFusion+Wire+PrimaryMessageCodecError.swift

extension OpalFusion.Wire {
    enum PrimaryMessageCodecError: Swift.Error, Equatable {
        case missingClientMessageCase
        case missingServerMessageCase
        case missingBlameDecrypter
        case invalidUTF8Field(String)
        case protobufCodingFailed(String)
        case protobufDecodingFailed(String)
    }
}

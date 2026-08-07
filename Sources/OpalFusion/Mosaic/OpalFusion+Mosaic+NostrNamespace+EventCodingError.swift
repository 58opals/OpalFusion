// OpalFusion+Mosaic+NostrNamespace+EventCodingError.swift

extension OpalFusion.Mosaic.NostrNamespace {
    enum EventCodingError: Swift.Error, Sendable, Equatable {
        case invalidResourceLimit
        case eventJSONByteCountExceedsMaximum(maximum: Int, actual: Int)
        case tagCountExceedsMaximum(maximum: Int, actual: Int)
        case emptyTag(index: Int)
        case tagElementCountExceedsMaximum(tagIndex: Int, maximum: Int, actual: Int)
        case stringByteCountExceedsMaximum(maximum: Int, actual: Int)
        case invalidJSON
        case duplicateTopLevelField(String)
        case unexpectedTopLevelField(String)
        case missingTopLevelField(String)
        case invalidHexadecimal(field: String)
        case invalidIdentifierLength(actual: Int)
        case invalidPublicKey
        case invalidSignature
        case identifierMismatch
        case signatureVerificationFailed
    }
}

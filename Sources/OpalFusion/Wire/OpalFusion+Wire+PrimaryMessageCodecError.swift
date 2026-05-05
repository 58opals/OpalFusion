// OpalFusion+Wire+PrimaryMessageCodecError.swift

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

import SwiftProtobuf

extension OpalFusion.Wire {
    enum PrimaryMessageCodecError: Swift.Error, Equatable {
        case missingClientMessageCase
        case missingServerMessageCase
        case missingBlameDecrypter
        case invalidUTF8Field(String)
        case protobufDecodingFailed(String)
    }
}

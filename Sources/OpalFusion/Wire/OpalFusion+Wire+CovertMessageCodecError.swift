// OpalFusion+Wire+CovertMessageCodecError.swift

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

import SwiftProtobuf

extension OpalFusion.Wire {
    enum CovertMessageCodecError: Swift.Error, Equatable {
        case missingCovertMessageCase
        case missingCovertResponseCase
        case protobufCodingFailed(String)
    }
}

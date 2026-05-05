// FusionBlindSignatureResponses.swift

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import SwiftProtobuf

struct FusionBlindSignatureResponses: Sendable {
  // SwiftProtobuf.Message conformance is added in an extension below. See the
  // `Message` and `Message+*Additions` files in the SwiftProtobuf library for
  // methods supported on all messages.

  /// 32 byte scalars
  var scalars: [Data] = []

  var unknownFields = SwiftProtobuf.UnknownStorage()

  init() {}
}

extension FusionBlindSignatureResponses: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  static let protoMessageName: String = "fusion.BlindSigResponses"
  static let _protobuf_nameMap = SwiftProtobuf._NameMap(bytecode: "\0\u{1}scalars\0")

  mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      // The use of inline closures is to circumvent an issue where the compiler
      // allocates stack space for every case branch when no optimizations are
      // enabled. https://github.com/apple/swift-protobuf/issues/1034
      switch fieldNumber {
      case 1: try { try decoder.decodeRepeatedBytesField(value: &self.scalars) }()
      default: break
      }
    }
  }

  func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    if !self.scalars.isEmpty {
      try visitor.visitRepeatedBytesField(value: self.scalars, fieldNumber: 1)
    }
    try unknownFields.traverse(visitor: &visitor)
  }

  static func ==(lhs: FusionBlindSignatureResponses, rhs: FusionBlindSignatureResponses) -> Bool {
    if lhs.scalars != rhs.scalars {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}

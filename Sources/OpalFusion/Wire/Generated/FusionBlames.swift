// FusionBlames.swift

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import SwiftProtobuf

struct FusionBlames: Sendable {
  // SwiftProtobuf.Message conformance is added in an extension below. See the
  // `Message` and `Message+*Additions` files in the SwiftProtobuf library for
  // methods supported on all messages.

  var blames: [FusionBlames.BlameProof] = []

  var unknownFields = SwiftProtobuf.UnknownStorage()
  init() {}
}

extension FusionBlames: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  static let protoMessageName: String = "fusion.Blames"
  static let _protobuf_nameMap = SwiftProtobuf._NameMap(bytecode: "\0\u{1}blames\0")

  public var isInitialized: Bool {
    if !SwiftProtobuf.Internal.areAllInitialized(self.blames) {return false}
    return true
  }

  mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      // The use of inline closures is to circumvent an issue where the compiler
      // allocates stack space for every case branch when no optimizations are
      // enabled. https://github.com/apple/swift-protobuf/issues/1034
      switch fieldNumber {
      case 1: try { try decoder.decodeRepeatedMessageField(value: &self.blames) }()
      default: break
      }
    }
  }

  func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    if !self.blames.isEmpty {
      try visitor.visitRepeatedMessageField(value: self.blames, fieldNumber: 1)
    }
    try unknownFields.traverse(visitor: &visitor)
  }

  static func ==(lhs: FusionBlames, rhs: FusionBlames) -> Bool {
    if lhs.blames != rhs.blames {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}

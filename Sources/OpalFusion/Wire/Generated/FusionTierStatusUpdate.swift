// FusionTierStatusUpdate.swift

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import SwiftProtobuf

struct FusionTierStatusUpdate: Sendable {
  // SwiftProtobuf.Message conformance is added in an extension below. See the
  // `Message` and `Message+*Additions` files in the SwiftProtobuf library for
  // methods supported on all messages.

  var statuses: Dictionary<UInt64,FusionTierStatusUpdate.TierStatus> = [:]

  var unknownFields = SwiftProtobuf.UnknownStorage()
  init() {}
}

extension FusionTierStatusUpdate: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  static let protoMessageName: String = "fusion.TierStatusUpdate"
  static let _protobuf_nameMap = SwiftProtobuf._NameMap(bytecode: "\0\u{1}statuses\0")

  mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      // The use of inline closures is to circumvent an issue where the compiler
      // allocates stack space for every case branch when no optimizations are
      // enabled. https://github.com/apple/swift-protobuf/issues/1034
      switch fieldNumber {
      case 1: try { try decoder.decodeMapField(fieldType: SwiftProtobuf._ProtobufMessageMap<SwiftProtobuf.ProtobufUInt64,FusionTierStatusUpdate.TierStatus>.self, value: &self.statuses) }()
      default: break
      }
    }
  }

  func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    if !self.statuses.isEmpty {
      try visitor.visitMapField(fieldType: SwiftProtobuf._ProtobufMessageMap<SwiftProtobuf.ProtobufUInt64,FusionTierStatusUpdate.TierStatus>.self, value: self.statuses, fieldNumber: 1)
    }
    try unknownFields.traverse(visitor: &visitor)
  }

  static func ==(lhs: FusionTierStatusUpdate, rhs: FusionTierStatusUpdate) -> Bool {
    if lhs.statuses != rhs.statuses {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}

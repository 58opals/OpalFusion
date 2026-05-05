// FusionJoinPools.swift

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import SwiftProtobuf

struct FusionJoinPools: Sendable {
  // SwiftProtobuf.Message conformance is added in an extension below. See the
  // `Message` and `Message+*Additions` files in the SwiftProtobuf library for
  // methods supported on all messages.

  var tiers: [UInt64] = []

  /// at most five tags.
  var tags: [FusionJoinPools.PoolTag] = []

  var unknownFields = SwiftProtobuf.UnknownStorage()
  init() {}
}

extension FusionJoinPools: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  static let protoMessageName: String = "fusion.JoinPools"
  static let _protobuf_nameMap = SwiftProtobuf._NameMap(bytecode: "\0\u{1}tiers\0\u{1}tags\0")

  public var isInitialized: Bool {
    if !SwiftProtobuf.Internal.areAllInitialized(self.tags) {return false}
    return true
  }

  mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      // The use of inline closures is to circumvent an issue where the compiler
      // allocates stack space for every case branch when no optimizations are
      // enabled. https://github.com/apple/swift-protobuf/issues/1034
      switch fieldNumber {
      case 1: try { try decoder.decodeRepeatedUInt64Field(value: &self.tiers) }()
      case 2: try { try decoder.decodeRepeatedMessageField(value: &self.tags) }()
      default: break
      }
    }
  }

  func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    if !self.tiers.isEmpty {
      try visitor.visitRepeatedUInt64Field(value: self.tiers, fieldNumber: 1)
    }
    if !self.tags.isEmpty {
      try visitor.visitRepeatedMessageField(value: self.tags, fieldNumber: 2)
    }
    try unknownFields.traverse(visitor: &visitor)
  }

  static func ==(lhs: FusionJoinPools, rhs: FusionJoinPools) -> Bool {
    if lhs.tiers != rhs.tiers {return false}
    if lhs.tags != rhs.tags {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}

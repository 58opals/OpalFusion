// FusionAllCommitments.swift

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import SwiftProtobuf

struct FusionAllCommitments: Sendable {
  // SwiftProtobuf.Message conformance is added in an extension below. See the
  // `Message` and `Message+*Additions` files in the SwiftProtobuf library for
  // methods supported on all messages.

  /// All the commitments from all players. At ~140 bytes per commitment and hundreds of commitments, this can be quite large, so it gets sent in its own message during the covert phase.
  var initialCommitments: [Data] = []

  var unknownFields = SwiftProtobuf.UnknownStorage()

  init() {}
}

extension FusionAllCommitments: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  static let protoMessageName: String = "fusion.AllCommitments"
  static let _protobuf_nameMap = SwiftProtobuf._NameMap(bytecode: "\0\u{3}initial_commitments\0")

  mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      // The use of inline closures is to circumvent an issue where the compiler
      // allocates stack space for every case branch when no optimizations are
      // enabled. https://github.com/apple/swift-protobuf/issues/1034
      switch fieldNumber {
      case 1: try { try decoder.decodeRepeatedBytesField(value: &self.initialCommitments) }()
      default: break
      }
    }
  }

  func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    if !self.initialCommitments.isEmpty {
      try visitor.visitRepeatedBytesField(value: self.initialCommitments, fieldNumber: 1)
    }
    try unknownFields.traverse(visitor: &visitor)
  }

  static func ==(lhs: FusionAllCommitments, rhs: FusionAllCommitments) -> Bool {
    if lhs.initialCommitments != rhs.initialCommitments {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}

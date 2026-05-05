// FusionResultMessage.swift

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import SwiftProtobuf

struct FusionResultMessage: Sendable {
  // SwiftProtobuf.Message conformance is added in an extension below. See the
  // `Message` and `Message+*Additions` files in the SwiftProtobuf library for
  // methods supported on all messages.

  var ok: Bool {
    get {_ok ?? false}
    set {_ok = newValue}
  }
  /// Returns true if `ok` has been explicitly set.
  var hasOk: Bool {self._ok != nil}
  /// Clears the value of `ok`. Subsequent reads from it will return its default value.
  mutating func clearOk() {self._ok = nil}

  /// if ok
  var txsignatures: [Data] = []

  /// if not ok
  var badComponents: [UInt32] = []

  var unknownFields = SwiftProtobuf.UnknownStorage()

  init() {}

  fileprivate var _ok: Bool? = nil
}

extension FusionResultMessage: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  static let protoMessageName: String = "fusion.FusionResult"
  static let _protobuf_nameMap = SwiftProtobuf._NameMap(bytecode: "\0\u{1}ok\0\u{1}txsignatures\0\u{3}bad_components\0")

  public var isInitialized: Bool {
    if self._ok == nil {return false}
    return true
  }

  mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      // The use of inline closures is to circumvent an issue where the compiler
      // allocates stack space for every case branch when no optimizations are
      // enabled. https://github.com/apple/swift-protobuf/issues/1034
      switch fieldNumber {
      case 1: try { try decoder.decodeSingularBoolField(value: &self._ok) }()
      case 2: try { try decoder.decodeRepeatedBytesField(value: &self.txsignatures) }()
      case 3: try { try decoder.decodeRepeatedUInt32Field(value: &self.badComponents) }()
      default: break
      }
    }
  }

  func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    // The use of inline closures is to circumvent an issue where the compiler
    // allocates stack space for every if/case branch local when no optimizations
    // are enabled. https://github.com/apple/swift-protobuf/issues/1034 and
    // https://github.com/apple/swift-protobuf/issues/1182
    try { if let v = self._ok {
      try visitor.visitSingularBoolField(value: v, fieldNumber: 1)
    } }()
    if !self.txsignatures.isEmpty {
      try visitor.visitRepeatedBytesField(value: self.txsignatures, fieldNumber: 2)
    }
    if !self.badComponents.isEmpty {
      try visitor.visitRepeatedUInt32Field(value: self.badComponents, fieldNumber: 3)
    }
    try unknownFields.traverse(visitor: &visitor)
  }

  static func ==(lhs: FusionResultMessage, rhs: FusionResultMessage) -> Bool {
    if lhs._ok != rhs._ok {return false}
    if lhs.txsignatures != rhs.txsignatures {return false}
    if lhs.badComponents != rhs.badComponents {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}

// FusionShareCovertComponents.swift

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import SwiftProtobuf

struct FusionShareCovertComponents: Sendable {
  // SwiftProtobuf.Message conformance is added in an extension below. See the
  // `Message` and `Message+*Additions` files in the SwiftProtobuf library for
  // methods supported on all messages.

  /// This is a large message! 168 bytes per initial commitment, ~112 bytes per input component.
  /// Can easily reach 100 kB or more.
  var components: [Data] = []

  /// if the server already sees a problem in submitted components
  var skipSignatures: Bool {
    get {_skipSignatures ?? false}
    set {_skipSignatures = newValue}
  }
  /// Returns true if `skipSignatures` has been explicitly set.
  var hasSkipSignatures: Bool {self._skipSignatures != nil}
  /// Clears the value of `skipSignatures`. Subsequent reads from it will return its default value.
  mutating func clearSkipSignatures() {self._skipSignatures = nil}

  /// the server's calculation of session hash, so clients can crosscheck.
  var sessionHash: Data {
    get {_sessionHash ?? Data()}
    set {_sessionHash = newValue}
  }
  /// Returns true if `sessionHash` has been explicitly set.
  var hasSessionHash: Bool {self._sessionHash != nil}
  /// Clears the value of `sessionHash`. Subsequent reads from it will return its default value.
  mutating func clearSessionHash() {self._sessionHash = nil}

  var unknownFields = SwiftProtobuf.UnknownStorage()

  init() {}

  fileprivate var _skipSignatures: Bool? = nil
  fileprivate var _sessionHash: Data? = nil
}

extension FusionShareCovertComponents: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  static let protoMessageName: String = "fusion.ShareCovertComponents"
  static let _protobuf_nameMap = SwiftProtobuf._NameMap(bytecode: "\0\u{2}\u{4}components\0\u{3}skip_signatures\0\u{3}session_hash\0")

  mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      // The use of inline closures is to circumvent an issue where the compiler
      // allocates stack space for every case branch when no optimizations are
      // enabled. https://github.com/apple/swift-protobuf/issues/1034
      switch fieldNumber {
      case 4: try { try decoder.decodeRepeatedBytesField(value: &self.components) }()
      case 5: try { try decoder.decodeSingularBoolField(value: &self._skipSignatures) }()
      case 6: try { try decoder.decodeSingularBytesField(value: &self._sessionHash) }()
      default: break
      }
    }
  }

  func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    // The use of inline closures is to circumvent an issue where the compiler
    // allocates stack space for every if/case branch local when no optimizations
    // are enabled. https://github.com/apple/swift-protobuf/issues/1034 and
    // https://github.com/apple/swift-protobuf/issues/1182
    if !self.components.isEmpty {
      try visitor.visitRepeatedBytesField(value: self.components, fieldNumber: 4)
    }
    try { if let v = self._skipSignatures {
      try visitor.visitSingularBoolField(value: v, fieldNumber: 5)
    } }()
    try { if let v = self._sessionHash {
      try visitor.visitSingularBytesField(value: v, fieldNumber: 6)
    } }()
    try unknownFields.traverse(visitor: &visitor)
  }

  static func ==(lhs: FusionShareCovertComponents, rhs: FusionShareCovertComponents) -> Bool {
    if lhs.components != rhs.components {return false}
    if lhs._skipSignatures != rhs._skipSignatures {return false}
    if lhs._sessionHash != rhs._sessionHash {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}

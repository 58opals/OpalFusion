// FusionCovertComponent.swift

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import SwiftProtobuf

struct FusionCovertComponent: Sendable {
  // SwiftProtobuf.Message conformance is added in an extension below. See the
  // `Message` and `Message+*Additions` files in the SwiftProtobuf library for
  // methods supported on all messages.

  /// The round key is used to identify the pool if needed
  var roundPubkey: Data {
    get {_roundPubkey ?? Data()}
    set {_roundPubkey = newValue}
  }
  /// Returns true if `roundPubkey` has been explicitly set.
  var hasRoundPubkey: Bool {self._roundPubkey != nil}
  /// Clears the value of `roundPubkey`. Subsequent reads from it will return its default value.
  mutating func clearRoundPubkey() {self._roundPubkey = nil}

  var signature: Data {
    get {_signature ?? Data()}
    set {_signature = newValue}
  }
  /// Returns true if `signature` has been explicitly set.
  var hasSignature: Bool {self._signature != nil}
  /// Clears the value of `signature`. Subsequent reads from it will return its default value.
  mutating func clearSignature() {self._signature = nil}

  /// bytes so that it can be signed and hashed verbatim
  var component: Data {
    get {_component ?? Data()}
    set {_component = newValue}
  }
  /// Returns true if `component` has been explicitly set.
  var hasComponent: Bool {self._component != nil}
  /// Clears the value of `component`. Subsequent reads from it will return its default value.
  mutating func clearComponent() {self._component = nil}

  var unknownFields = SwiftProtobuf.UnknownStorage()

  init() {}

  fileprivate var _roundPubkey: Data? = nil
  fileprivate var _signature: Data? = nil
  fileprivate var _component: Data? = nil
}

extension FusionCovertComponent: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  static let protoMessageName: String = "fusion.CovertComponent"
  static let _protobuf_nameMap = SwiftProtobuf._NameMap(bytecode: "\0\u{3}round_pubkey\0\u{1}signature\0\u{1}component\0")

  public var isInitialized: Bool {
    if self._signature == nil {return false}
    if self._component == nil {return false}
    return true
  }

  mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      // The use of inline closures is to circumvent an issue where the compiler
      // allocates stack space for every case branch when no optimizations are
      // enabled. https://github.com/apple/swift-protobuf/issues/1034
      switch fieldNumber {
      case 1: try { try decoder.decodeSingularBytesField(value: &self._roundPubkey) }()
      case 2: try { try decoder.decodeSingularBytesField(value: &self._signature) }()
      case 3: try { try decoder.decodeSingularBytesField(value: &self._component) }()
      default: break
      }
    }
  }

  func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    // The use of inline closures is to circumvent an issue where the compiler
    // allocates stack space for every if/case branch local when no optimizations
    // are enabled. https://github.com/apple/swift-protobuf/issues/1034 and
    // https://github.com/apple/swift-protobuf/issues/1182
    try { if let v = self._roundPubkey {
      try visitor.visitSingularBytesField(value: v, fieldNumber: 1)
    } }()
    try { if let v = self._signature {
      try visitor.visitSingularBytesField(value: v, fieldNumber: 2)
    } }()
    try { if let v = self._component {
      try visitor.visitSingularBytesField(value: v, fieldNumber: 3)
    } }()
    try unknownFields.traverse(visitor: &visitor)
  }

  static func ==(lhs: FusionCovertComponent, rhs: FusionCovertComponent) -> Bool {
    if lhs._roundPubkey != rhs._roundPubkey {return false}
    if lhs._signature != rhs._signature {return false}
    if lhs._component != rhs._component {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}

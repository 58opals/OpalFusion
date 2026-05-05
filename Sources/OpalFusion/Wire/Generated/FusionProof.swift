// FusionProof.swift

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import SwiftProtobuf

struct FusionProof: Sendable {
  // SwiftProtobuf.Message conformance is added in an extension below. See the
  // `Message` and `Message+*Additions` files in the SwiftProtobuf library for
  // methods supported on all messages.

  /// During blame phase, messages of this form are encrypted and sent
  /// to a different player. It is already known which commitment this
  /// should apply to, so we only need to point at the component.
  var componentIdx: UInt32 {
    get {_componentIdx ?? 0}
    set {_componentIdx = newValue}
  }
  /// Returns true if `componentIdx` has been explicitly set.
  var hasComponentIdx: Bool {self._componentIdx != nil}
  /// Clears the value of `componentIdx`. Subsequent reads from it will return its default value.
  mutating func clearComponentIdx() {self._componentIdx = nil}

  /// 32 bytes
  var salt: Data {
    get {_salt ?? Data()}
    set {_salt = newValue}
  }
  /// Returns true if `salt` has been explicitly set.
  var hasSalt: Bool {self._salt != nil}
  /// Clears the value of `salt`. Subsequent reads from it will return its default value.
  mutating func clearSalt() {self._salt = nil}

  /// 32 bytes
  var pedersenNonce: Data {
    get {_pedersenNonce ?? Data()}
    set {_pedersenNonce = newValue}
  }
  /// Returns true if `pedersenNonce` has been explicitly set.
  var hasPedersenNonce: Bool {self._pedersenNonce != nil}
  /// Clears the value of `pedersenNonce`. Subsequent reads from it will return its default value.
  mutating func clearPedersenNonce() {self._pedersenNonce = nil}

  var unknownFields = SwiftProtobuf.UnknownStorage()

  init() {}

  fileprivate var _componentIdx: UInt32? = nil
  fileprivate var _salt: Data? = nil
  fileprivate var _pedersenNonce: Data? = nil
}

extension FusionProof: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  static let protoMessageName: String = "fusion.Proof"
  static let _protobuf_nameMap = SwiftProtobuf._NameMap(bytecode: "\0\u{3}component_idx\0\u{1}salt\0\u{3}pedersen_nonce\0")

  public var isInitialized: Bool {
    if self._componentIdx == nil {return false}
    if self._salt == nil {return false}
    if self._pedersenNonce == nil {return false}
    return true
  }

  mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      // The use of inline closures is to circumvent an issue where the compiler
      // allocates stack space for every case branch when no optimizations are
      // enabled. https://github.com/apple/swift-protobuf/issues/1034
      switch fieldNumber {
      case 1: try { try decoder.decodeSingularFixed32Field(value: &self._componentIdx) }()
      case 2: try { try decoder.decodeSingularBytesField(value: &self._salt) }()
      case 3: try { try decoder.decodeSingularBytesField(value: &self._pedersenNonce) }()
      default: break
      }
    }
  }

  func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    // The use of inline closures is to circumvent an issue where the compiler
    // allocates stack space for every if/case branch local when no optimizations
    // are enabled. https://github.com/apple/swift-protobuf/issues/1034 and
    // https://github.com/apple/swift-protobuf/issues/1182
    try { if let v = self._componentIdx {
      try visitor.visitSingularFixed32Field(value: v, fieldNumber: 1)
    } }()
    try { if let v = self._salt {
      try visitor.visitSingularBytesField(value: v, fieldNumber: 2)
    } }()
    try { if let v = self._pedersenNonce {
      try visitor.visitSingularBytesField(value: v, fieldNumber: 3)
    } }()
    try unknownFields.traverse(visitor: &visitor)
  }

  static func ==(lhs: FusionProof, rhs: FusionProof) -> Bool {
    if lhs._componentIdx != rhs._componentIdx {return false}
    if lhs._salt != rhs._salt {return false}
    if lhs._pedersenNonce != rhs._pedersenNonce {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}

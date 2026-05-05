// FusionInitialCommitment.swift

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import SwiftProtobuf

struct FusionInitialCommitment: Sendable {
  // SwiftProtobuf.Message conformance is added in an extension below. See the
  // `Message` and `Message+*Additions` files in the SwiftProtobuf library for
  // methods supported on all messages.

  /// 32 byte hash
  var saltedComponentHash: Data {
    get {_saltedComponentHash ?? Data()}
    set {_saltedComponentHash = newValue}
  }
  /// Returns true if `saltedComponentHash` has been explicitly set.
  var hasSaltedComponentHash: Bool {self._saltedComponentHash != nil}
  /// Clears the value of `saltedComponentHash`. Subsequent reads from it will return its default value.
  mutating func clearSaltedComponentHash() {self._saltedComponentHash = nil}

  /// uncompressed point
  var amountCommitment: Data {
    get {_amountCommitment ?? Data()}
    set {_amountCommitment = newValue}
  }
  /// Returns true if `amountCommitment` has been explicitly set.
  var hasAmountCommitment: Bool {self._amountCommitment != nil}
  /// Clears the value of `amountCommitment`. Subsequent reads from it will return its default value.
  mutating func clearAmountCommitment() {self._amountCommitment = nil}

  /// compressed point
  var communicationKey: Data {
    get {_communicationKey ?? Data()}
    set {_communicationKey = newValue}
  }
  /// Returns true if `communicationKey` has been explicitly set.
  var hasCommunicationKey: Bool {self._communicationKey != nil}
  /// Clears the value of `communicationKey`. Subsequent reads from it will return its default value.
  mutating func clearCommunicationKey() {self._communicationKey = nil}

  var unknownFields = SwiftProtobuf.UnknownStorage()

  init() {}

  fileprivate var _saltedComponentHash: Data? = nil
  fileprivate var _amountCommitment: Data? = nil
  fileprivate var _communicationKey: Data? = nil
}

extension FusionInitialCommitment: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  static let protoMessageName: String = "fusion.InitialCommitment"
  static let _protobuf_nameMap = SwiftProtobuf._NameMap(bytecode: "\0\u{3}salted_component_hash\0\u{3}amount_commitment\0\u{3}communication_key\0")

  public var isInitialized: Bool {
    if self._saltedComponentHash == nil {return false}
    if self._amountCommitment == nil {return false}
    if self._communicationKey == nil {return false}
    return true
  }

  mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      // The use of inline closures is to circumvent an issue where the compiler
      // allocates stack space for every case branch when no optimizations are
      // enabled. https://github.com/apple/swift-protobuf/issues/1034
      switch fieldNumber {
      case 1: try { try decoder.decodeSingularBytesField(value: &self._saltedComponentHash) }()
      case 2: try { try decoder.decodeSingularBytesField(value: &self._amountCommitment) }()
      case 3: try { try decoder.decodeSingularBytesField(value: &self._communicationKey) }()
      default: break
      }
    }
  }

  func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    // The use of inline closures is to circumvent an issue where the compiler
    // allocates stack space for every if/case branch local when no optimizations
    // are enabled. https://github.com/apple/swift-protobuf/issues/1034 and
    // https://github.com/apple/swift-protobuf/issues/1182
    try { if let v = self._saltedComponentHash {
      try visitor.visitSingularBytesField(value: v, fieldNumber: 1)
    } }()
    try { if let v = self._amountCommitment {
      try visitor.visitSingularBytesField(value: v, fieldNumber: 2)
    } }()
    try { if let v = self._communicationKey {
      try visitor.visitSingularBytesField(value: v, fieldNumber: 3)
    } }()
    try unknownFields.traverse(visitor: &visitor)
  }

  static func ==(lhs: FusionInitialCommitment, rhs: FusionInitialCommitment) -> Bool {
    if lhs._saltedComponentHash != rhs._saltedComponentHash {return false}
    if lhs._amountCommitment != rhs._amountCommitment {return false}
    if lhs._communicationKey != rhs._communicationKey {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}

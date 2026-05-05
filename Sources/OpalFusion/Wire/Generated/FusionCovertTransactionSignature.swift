// FusionCovertTransactionSignature.swift

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import SwiftProtobuf

struct FusionCovertTransactionSignature: Sendable {
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

  var whichInput: UInt32 {
    get {_whichInput ?? 0}
    set {_whichInput = newValue}
  }
  /// Returns true if `whichInput` has been explicitly set.
  var hasWhichInput: Bool {self._whichInput != nil}
  /// Clears the value of `whichInput`. Subsequent reads from it will return its default value.
  mutating func clearWhichInput() {self._whichInput = nil}

  var txsignature: Data {
    get {_txsignature ?? Data()}
    set {_txsignature = newValue}
  }
  /// Returns true if `txsignature` has been explicitly set.
  var hasTxsignature: Bool {self._txsignature != nil}
  /// Clears the value of `txsignature`. Subsequent reads from it will return its default value.
  mutating func clearTxsignature() {self._txsignature = nil}

  var unknownFields = SwiftProtobuf.UnknownStorage()

  init() {}

  fileprivate var _roundPubkey: Data? = nil
  fileprivate var _whichInput: UInt32? = nil
  fileprivate var _txsignature: Data? = nil
}

extension FusionCovertTransactionSignature: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  static let protoMessageName: String = "fusion.CovertTransactionSignature"
  static let _protobuf_nameMap = SwiftProtobuf._NameMap(bytecode: "\0\u{3}round_pubkey\0\u{3}which_input\0\u{1}txsignature\0")

  public var isInitialized: Bool {
    if self._whichInput == nil {return false}
    if self._txsignature == nil {return false}
    return true
  }

  mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      // The use of inline closures is to circumvent an issue where the compiler
      // allocates stack space for every case branch when no optimizations are
      // enabled. https://github.com/apple/swift-protobuf/issues/1034
      switch fieldNumber {
      case 1: try { try decoder.decodeSingularBytesField(value: &self._roundPubkey) }()
      case 2: try { try decoder.decodeSingularUInt32Field(value: &self._whichInput) }()
      case 3: try { try decoder.decodeSingularBytesField(value: &self._txsignature) }()
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
    try { if let v = self._whichInput {
      try visitor.visitSingularUInt32Field(value: v, fieldNumber: 2)
    } }()
    try { if let v = self._txsignature {
      try visitor.visitSingularBytesField(value: v, fieldNumber: 3)
    } }()
    try unknownFields.traverse(visitor: &visitor)
  }

  static func ==(lhs: FusionCovertTransactionSignature, rhs: FusionCovertTransactionSignature) -> Bool {
    if lhs._roundPubkey != rhs._roundPubkey {return false}
    if lhs._whichInput != rhs._whichInput {return false}
    if lhs._txsignature != rhs._txsignature {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}

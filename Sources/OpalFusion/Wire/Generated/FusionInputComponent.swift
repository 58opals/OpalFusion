// FusionInputComponent.swift

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import SwiftProtobuf

struct FusionInputComponent: Sendable {
  // SwiftProtobuf.Message conformance is added in an extension below. See the
  // `Message` and `Message+*Additions` files in the SwiftProtobuf library for
  // methods supported on all messages.

  /// in 'reverse' order, just like in tx
  var prevTxid: Data {
    get {_prevTxid ?? Data()}
    set {_prevTxid = newValue}
  }
  /// Returns true if `prevTxid` has been explicitly set.
  var hasPrevTxid: Bool {self._prevTxid != nil}
  /// Clears the value of `prevTxid`. Subsequent reads from it will return its default value.
  mutating func clearPrevTxid() {self._prevTxid = nil}

  var prevIndex: UInt32 {
    get {_prevIndex ?? 0}
    set {_prevIndex = newValue}
  }
  /// Returns true if `prevIndex` has been explicitly set.
  var hasPrevIndex: Bool {self._prevIndex != nil}
  /// Clears the value of `prevIndex`. Subsequent reads from it will return its default value.
  mutating func clearPrevIndex() {self._prevIndex = nil}

  var pubkey: Data {
    get {_pubkey ?? Data()}
    set {_pubkey = newValue}
  }
  /// Returns true if `pubkey` has been explicitly set.
  var hasPubkey: Bool {self._pubkey != nil}
  /// Clears the value of `pubkey`. Subsequent reads from it will return its default value.
  mutating func clearPubkey() {self._pubkey = nil}

  var amount: UInt64 {
    get {_amount ?? 0}
    set {_amount = newValue}
  }
  /// Returns true if `amount` has been explicitly set.
  var hasAmount: Bool {self._amount != nil}
  /// Clears the value of `amount`. Subsequent reads from it will return its default value.
  mutating func clearAmount() {self._amount = nil}

  var unknownFields = SwiftProtobuf.UnknownStorage()

  init() {}

  fileprivate var _prevTxid: Data? = nil
  fileprivate var _prevIndex: UInt32? = nil
  fileprivate var _pubkey: Data? = nil
  fileprivate var _amount: UInt64? = nil
}

extension FusionInputComponent: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  static let protoMessageName: String = "fusion.InputComponent"
  static let _protobuf_nameMap = SwiftProtobuf._NameMap(bytecode: "\0\u{3}prev_txid\0\u{3}prev_index\0\u{1}pubkey\0\u{1}amount\0")

  public var isInitialized: Bool {
    if self._prevTxid == nil {return false}
    if self._prevIndex == nil {return false}
    if self._pubkey == nil {return false}
    if self._amount == nil {return false}
    return true
  }

  mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      // The use of inline closures is to circumvent an issue where the compiler
      // allocates stack space for every case branch when no optimizations are
      // enabled. https://github.com/apple/swift-protobuf/issues/1034
      switch fieldNumber {
      case 1: try { try decoder.decodeSingularBytesField(value: &self._prevTxid) }()
      case 2: try { try decoder.decodeSingularUInt32Field(value: &self._prevIndex) }()
      case 3: try { try decoder.decodeSingularBytesField(value: &self._pubkey) }()
      case 4: try { try decoder.decodeSingularUInt64Field(value: &self._amount) }()
      default: break
      }
    }
  }

  func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    // The use of inline closures is to circumvent an issue where the compiler
    // allocates stack space for every if/case branch local when no optimizations
    // are enabled. https://github.com/apple/swift-protobuf/issues/1034 and
    // https://github.com/apple/swift-protobuf/issues/1182
    try { if let v = self._prevTxid {
      try visitor.visitSingularBytesField(value: v, fieldNumber: 1)
    } }()
    try { if let v = self._prevIndex {
      try visitor.visitSingularUInt32Field(value: v, fieldNumber: 2)
    } }()
    try { if let v = self._pubkey {
      try visitor.visitSingularBytesField(value: v, fieldNumber: 3)
    } }()
    try { if let v = self._amount {
      try visitor.visitSingularUInt64Field(value: v, fieldNumber: 4)
    } }()
    try unknownFields.traverse(visitor: &visitor)
  }

  static func ==(lhs: FusionInputComponent, rhs: FusionInputComponent) -> Bool {
    if lhs._prevTxid != rhs._prevTxid {return false}
    if lhs._prevIndex != rhs._prevIndex {return false}
    if lhs._pubkey != rhs._pubkey {return false}
    if lhs._amount != rhs._amount {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}

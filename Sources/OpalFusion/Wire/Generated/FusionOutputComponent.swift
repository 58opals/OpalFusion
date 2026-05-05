// FusionOutputComponent.swift

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import SwiftProtobuf

struct FusionOutputComponent: Sendable {
  // SwiftProtobuf.Message conformance is added in an extension below. See the
  // `Message` and `Message+*Additions` files in the SwiftProtobuf library for
  // methods supported on all messages.

  var scriptpubkey: Data {
    get {_scriptpubkey ?? Data()}
    set {_scriptpubkey = newValue}
  }
  /// Returns true if `scriptpubkey` has been explicitly set.
  var hasScriptpubkey: Bool {self._scriptpubkey != nil}
  /// Clears the value of `scriptpubkey`. Subsequent reads from it will return its default value.
  mutating func clearScriptpubkey() {self._scriptpubkey = nil}

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

  fileprivate var _scriptpubkey: Data? = nil
  fileprivate var _amount: UInt64? = nil
}

extension FusionOutputComponent: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  static let protoMessageName: String = "fusion.OutputComponent"
  static let _protobuf_nameMap = SwiftProtobuf._NameMap(bytecode: "\0\u{1}scriptpubkey\0\u{1}amount\0")

  public var isInitialized: Bool {
    if self._scriptpubkey == nil {return false}
    if self._amount == nil {return false}
    return true
  }

  mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      // The use of inline closures is to circumvent an issue where the compiler
      // allocates stack space for every case branch when no optimizations are
      // enabled. https://github.com/apple/swift-protobuf/issues/1034
      switch fieldNumber {
      case 1: try { try decoder.decodeSingularBytesField(value: &self._scriptpubkey) }()
      case 2: try { try decoder.decodeSingularUInt64Field(value: &self._amount) }()
      default: break
      }
    }
  }

  func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    // The use of inline closures is to circumvent an issue where the compiler
    // allocates stack space for every if/case branch local when no optimizations
    // are enabled. https://github.com/apple/swift-protobuf/issues/1034 and
    // https://github.com/apple/swift-protobuf/issues/1182
    try { if let v = self._scriptpubkey {
      try visitor.visitSingularBytesField(value: v, fieldNumber: 1)
    } }()
    try { if let v = self._amount {
      try visitor.visitSingularUInt64Field(value: v, fieldNumber: 2)
    } }()
    try unknownFields.traverse(visitor: &visitor)
  }

  static func ==(lhs: FusionOutputComponent, rhs: FusionOutputComponent) -> Bool {
    if lhs._scriptpubkey != rhs._scriptpubkey {return false}
    if lhs._amount != rhs._amount {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}

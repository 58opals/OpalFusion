// FusionBeginMessage.swift

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import SwiftProtobuf

struct FusionBeginMessage: Sendable {
  // SwiftProtobuf.Message conformance is added in an extension below. See the
  // `Message` and `Message+*Additions` files in the SwiftProtobuf library for
  // methods supported on all messages.

  var tier: UInt64 {
    get {_tier ?? 0}
    set {_tier = newValue}
  }
  /// Returns true if `tier` has been explicitly set.
  var hasTier: Bool {self._tier != nil}
  /// Clears the value of `tier`. Subsequent reads from it will return its default value.
  mutating func clearTier() {self._tier = nil}

  var covertDomain: Data {
    get {_covertDomain ?? Data()}
    set {_covertDomain = newValue}
  }
  /// Returns true if `covertDomain` has been explicitly set.
  var hasCovertDomain: Bool {self._covertDomain != nil}
  /// Clears the value of `covertDomain`. Subsequent reads from it will return its default value.
  mutating func clearCovertDomain() {self._covertDomain = nil}

  var covertPort: UInt32 {
    get {_covertPort ?? 0}
    set {_covertPort = newValue}
  }
  /// Returns true if `covertPort` has been explicitly set.
  var hasCovertPort: Bool {self._covertPort != nil}
  /// Clears the value of `covertPort`. Subsequent reads from it will return its default value.
  mutating func clearCovertPort() {self._covertPort = nil}

  var covertSsl: Bool {
    get {_covertSsl ?? false}
    set {_covertSsl = newValue}
  }
  /// Returns true if `covertSsl` has been explicitly set.
  var hasCovertSsl: Bool {self._covertSsl != nil}
  /// Clears the value of `covertSsl`. Subsequent reads from it will return its default value.
  mutating func clearCovertSsl() {self._covertSsl = nil}

  /// server unix time when sending this message; can't be too far off from recipient's clock.
  var serverTime: UInt64 {
    get {_serverTime ?? 0}
    set {_serverTime = newValue}
  }
  /// Returns true if `serverTime` has been explicitly set.
  var hasServerTime: Bool {self._serverTime != nil}
  /// Clears the value of `serverTime`. Subsequent reads from it will return its default value.
  mutating func clearServerTime() {self._serverTime = nil}

  var unknownFields = SwiftProtobuf.UnknownStorage()

  init() {}

  fileprivate var _tier: UInt64? = nil
  fileprivate var _covertDomain: Data? = nil
  fileprivate var _covertPort: UInt32? = nil
  fileprivate var _covertSsl: Bool? = nil
  fileprivate var _serverTime: UInt64? = nil
}

extension FusionBeginMessage: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  static let protoMessageName: String = "fusion.FusionBegin"
  static let _protobuf_nameMap = SwiftProtobuf._NameMap(bytecode: "\0\u{1}tier\0\u{3}covert_domain\0\u{3}covert_port\0\u{3}covert_ssl\0\u{3}server_time\0")

  public var isInitialized: Bool {
    if self._tier == nil {return false}
    if self._covertDomain == nil {return false}
    if self._covertPort == nil {return false}
    if self._serverTime == nil {return false}
    return true
  }

  mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      // The use of inline closures is to circumvent an issue where the compiler
      // allocates stack space for every case branch when no optimizations are
      // enabled. https://github.com/apple/swift-protobuf/issues/1034
      switch fieldNumber {
      case 1: try { try decoder.decodeSingularUInt64Field(value: &self._tier) }()
      case 2: try { try decoder.decodeSingularBytesField(value: &self._covertDomain) }()
      case 3: try { try decoder.decodeSingularUInt32Field(value: &self._covertPort) }()
      case 4: try { try decoder.decodeSingularBoolField(value: &self._covertSsl) }()
      case 5: try { try decoder.decodeSingularFixed64Field(value: &self._serverTime) }()
      default: break
      }
    }
  }

  func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    // The use of inline closures is to circumvent an issue where the compiler
    // allocates stack space for every if/case branch local when no optimizations
    // are enabled. https://github.com/apple/swift-protobuf/issues/1034 and
    // https://github.com/apple/swift-protobuf/issues/1182
    try { if let v = self._tier {
      try visitor.visitSingularUInt64Field(value: v, fieldNumber: 1)
    } }()
    try { if let v = self._covertDomain {
      try visitor.visitSingularBytesField(value: v, fieldNumber: 2)
    } }()
    try { if let v = self._covertPort {
      try visitor.visitSingularUInt32Field(value: v, fieldNumber: 3)
    } }()
    try { if let v = self._covertSsl {
      try visitor.visitSingularBoolField(value: v, fieldNumber: 4)
    } }()
    try { if let v = self._serverTime {
      try visitor.visitSingularFixed64Field(value: v, fieldNumber: 5)
    } }()
    try unknownFields.traverse(visitor: &visitor)
  }

  static func ==(lhs: FusionBeginMessage, rhs: FusionBeginMessage) -> Bool {
    if lhs._tier != rhs._tier {return false}
    if lhs._covertDomain != rhs._covertDomain {return false}
    if lhs._covertPort != rhs._covertPort {return false}
    if lhs._covertSsl != rhs._covertSsl {return false}
    if lhs._serverTime != rhs._serverTime {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}

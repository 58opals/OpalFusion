// FusionServerHello.swift

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import SwiftProtobuf

struct FusionServerHello: Sendable {
  // SwiftProtobuf.Message conformance is added in an extension below. See the
  // `Message` and `Message+*Additions` files in the SwiftProtobuf library for
  // methods supported on all messages.

  var tiers: [UInt64] = []

  var numComponents: UInt32 {
    get {_numComponents ?? 0}
    set {_numComponents = newValue}
  }
  /// Returns true if `numComponents` has been explicitly set.
  var hasNumComponents: Bool {self._numComponents != nil}
  /// Clears the value of `numComponents`. Subsequent reads from it will return its default value.
  mutating func clearNumComponents() {self._numComponents = nil}

  /// sats/kB
  var componentFeerate: UInt64 {
    get {_componentFeerate ?? 0}
    set {_componentFeerate = newValue}
  }
  /// Returns true if `componentFeerate` has been explicitly set.
  var hasComponentFeerate: Bool {self._componentFeerate != nil}
  /// Clears the value of `componentFeerate`. Subsequent reads from it will return its default value.
  mutating func clearComponentFeerate() {self._componentFeerate = nil}

  /// sats
  var minExcessFee: UInt64 {
    get {_minExcessFee ?? 0}
    set {_minExcessFee = newValue}
  }
  /// Returns true if `minExcessFee` has been explicitly set.
  var hasMinExcessFee: Bool {self._minExcessFee != nil}
  /// Clears the value of `minExcessFee`. Subsequent reads from it will return its default value.
  mutating func clearMinExcessFee() {self._minExcessFee = nil}

  /// sats
  var maxExcessFee: UInt64 {
    get {_maxExcessFee ?? 0}
    set {_maxExcessFee = newValue}
  }
  /// Returns true if `maxExcessFee` has been explicitly set.
  var hasMaxExcessFee: Bool {self._maxExcessFee != nil}
  /// Clears the value of `maxExcessFee`. Subsequent reads from it will return its default value.
  mutating func clearMaxExcessFee() {self._maxExcessFee = nil}

  /// BCH Address "bitcoincash:qpx..."
  var donationAddress: String {
    get {_donationAddress ?? String()}
    set {_donationAddress = newValue}
  }
  /// Returns true if `donationAddress` has been explicitly set.
  var hasDonationAddress: Bool {self._donationAddress != nil}
  /// Clears the value of `donationAddress`. Subsequent reads from it will return its default value.
  mutating func clearDonationAddress() {self._donationAddress = nil}

  var unknownFields = SwiftProtobuf.UnknownStorage()

  init() {}

  fileprivate var _numComponents: UInt32? = nil
  fileprivate var _componentFeerate: UInt64? = nil
  fileprivate var _minExcessFee: UInt64? = nil
  fileprivate var _maxExcessFee: UInt64? = nil
  fileprivate var _donationAddress: String? = nil
}

extension FusionServerHello: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  static let protoMessageName: String = "fusion.ServerHello"
  static let _protobuf_nameMap = SwiftProtobuf._NameMap(bytecode: "\0\u{1}tiers\0\u{3}num_components\0\u{4}\u{2}component_feerate\0\u{3}min_excess_fee\0\u{3}max_excess_fee\0\u{4}\u{9}donation_address\0")

  public var isInitialized: Bool {
    if self._numComponents == nil {return false}
    if self._componentFeerate == nil {return false}
    if self._minExcessFee == nil {return false}
    if self._maxExcessFee == nil {return false}
    return true
  }

  mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      // The use of inline closures is to circumvent an issue where the compiler
      // allocates stack space for every case branch when no optimizations are
      // enabled. https://github.com/apple/swift-protobuf/issues/1034
      switch fieldNumber {
      case 1: try { try decoder.decodeRepeatedUInt64Field(value: &self.tiers) }()
      case 2: try { try decoder.decodeSingularUInt32Field(value: &self._numComponents) }()
      case 4: try { try decoder.decodeSingularUInt64Field(value: &self._componentFeerate) }()
      case 5: try { try decoder.decodeSingularUInt64Field(value: &self._minExcessFee) }()
      case 6: try { try decoder.decodeSingularUInt64Field(value: &self._maxExcessFee) }()
      case 15: try { try decoder.decodeSingularStringField(value: &self._donationAddress) }()
      default: break
      }
    }
  }

  func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    // The use of inline closures is to circumvent an issue where the compiler
    // allocates stack space for every if/case branch local when no optimizations
    // are enabled. https://github.com/apple/swift-protobuf/issues/1034 and
    // https://github.com/apple/swift-protobuf/issues/1182
    if !self.tiers.isEmpty {
      try visitor.visitRepeatedUInt64Field(value: self.tiers, fieldNumber: 1)
    }
    try { if let v = self._numComponents {
      try visitor.visitSingularUInt32Field(value: v, fieldNumber: 2)
    } }()
    try { if let v = self._componentFeerate {
      try visitor.visitSingularUInt64Field(value: v, fieldNumber: 4)
    } }()
    try { if let v = self._minExcessFee {
      try visitor.visitSingularUInt64Field(value: v, fieldNumber: 5)
    } }()
    try { if let v = self._maxExcessFee {
      try visitor.visitSingularUInt64Field(value: v, fieldNumber: 6)
    } }()
    try { if let v = self._donationAddress {
      try visitor.visitSingularStringField(value: v, fieldNumber: 15)
    } }()
    try unknownFields.traverse(visitor: &visitor)
  }

  static func ==(lhs: FusionServerHello, rhs: FusionServerHello) -> Bool {
    if lhs.tiers != rhs.tiers {return false}
    if lhs._numComponents != rhs._numComponents {return false}
    if lhs._componentFeerate != rhs._componentFeerate {return false}
    if lhs._minExcessFee != rhs._minExcessFee {return false}
    if lhs._maxExcessFee != rhs._maxExcessFee {return false}
    if lhs._donationAddress != rhs._donationAddress {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}

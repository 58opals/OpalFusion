// FusionStartRound.swift

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import SwiftProtobuf

struct FusionStartRound: Sendable {
  // SwiftProtobuf.Message conformance is added in an extension below. See the
  // `Message` and `Message+*Additions` files in the SwiftProtobuf library for
  // methods supported on all messages.

  var roundPubkey: Data {
    get {_roundPubkey ?? Data()}
    set {_roundPubkey = newValue}
  }
  /// Returns true if `roundPubkey` has been explicitly set.
  var hasRoundPubkey: Bool {self._roundPubkey != nil}
  /// Clears the value of `roundPubkey`. Subsequent reads from it will return its default value.
  mutating func clearRoundPubkey() {self._roundPubkey = nil}

  var blindNoncePoints: [Data] = []

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

  fileprivate var _roundPubkey: Data? = nil
  fileprivate var _serverTime: UInt64? = nil
}

extension FusionStartRound: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  static let protoMessageName: String = "fusion.StartRound"
  static let _protobuf_nameMap = SwiftProtobuf._NameMap(bytecode: "\0\u{3}round_pubkey\0\u{3}blind_nonce_points\0\u{4}\u{3}server_time\0")

  public var isInitialized: Bool {
    if self._roundPubkey == nil {return false}
    if self._serverTime == nil {return false}
    return true
  }

  mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      // The use of inline closures is to circumvent an issue where the compiler
      // allocates stack space for every case branch when no optimizations are
      // enabled. https://github.com/apple/swift-protobuf/issues/1034
      switch fieldNumber {
      case 1: try { try decoder.decodeSingularBytesField(value: &self._roundPubkey) }()
      case 2: try { try decoder.decodeRepeatedBytesField(value: &self.blindNoncePoints) }()
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
    try { if let v = self._roundPubkey {
      try visitor.visitSingularBytesField(value: v, fieldNumber: 1)
    } }()
    if !self.blindNoncePoints.isEmpty {
      try visitor.visitRepeatedBytesField(value: self.blindNoncePoints, fieldNumber: 2)
    }
    try { if let v = self._serverTime {
      try visitor.visitSingularFixed64Field(value: v, fieldNumber: 5)
    } }()
    try unknownFields.traverse(visitor: &visitor)
  }

  static func ==(lhs: FusionStartRound, rhs: FusionStartRound) -> Bool {
    if lhs._roundPubkey != rhs._roundPubkey {return false}
    if lhs.blindNoncePoints != rhs.blindNoncePoints {return false}
    if lhs._serverTime != rhs._serverTime {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}

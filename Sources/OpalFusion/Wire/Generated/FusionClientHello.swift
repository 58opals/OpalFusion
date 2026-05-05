// FusionClientHello.swift

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import SwiftProtobuf

struct FusionClientHello: Sendable {
  // SwiftProtobuf.Message conformance is added in an extension below. See the
  // `Message` and `Message+*Additions` files in the SwiftProtobuf library for
  // methods supported on all messages.

  var version: Data {
    get {_version ?? Data()}
    set {_version = newValue}
  }
  /// Returns true if `version` has been explicitly set.
  var hasVersion: Bool {self._version != nil}
  /// Clears the value of `version`. Subsequent reads from it will return its default value.
  mutating func clearVersion() {self._version = nil}

  /// 32 byte hash (bitcoind little-endian memory order)
  var genesisHash: Data {
    get {_genesisHash ?? Data()}
    set {_genesisHash = newValue}
  }
  /// Returns true if `genesisHash` has been explicitly set.
  var hasGenesisHash: Bool {self._genesisHash != nil}
  /// Clears the value of `genesisHash`. Subsequent reads from it will return its default value.
  mutating func clearGenesisHash() {self._genesisHash = nil}

  var unknownFields = SwiftProtobuf.UnknownStorage()

  init() {}

  fileprivate var _version: Data? = nil
  fileprivate var _genesisHash: Data? = nil
}

extension FusionClientHello: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  static let protoMessageName: String = "fusion.ClientHello"
  static let _protobuf_nameMap = SwiftProtobuf._NameMap(bytecode: "\0\u{1}version\0\u{3}genesis_hash\0")

  public var isInitialized: Bool {
    if self._version == nil {return false}
    return true
  }

  mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      // The use of inline closures is to circumvent an issue where the compiler
      // allocates stack space for every case branch when no optimizations are
      // enabled. https://github.com/apple/swift-protobuf/issues/1034
      switch fieldNumber {
      case 1: try { try decoder.decodeSingularBytesField(value: &self._version) }()
      case 2: try { try decoder.decodeSingularBytesField(value: &self._genesisHash) }()
      default: break
      }
    }
  }

  func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    // The use of inline closures is to circumvent an issue where the compiler
    // allocates stack space for every if/case branch local when no optimizations
    // are enabled. https://github.com/apple/swift-protobuf/issues/1034 and
    // https://github.com/apple/swift-protobuf/issues/1182
    try { if let v = self._version {
      try visitor.visitSingularBytesField(value: v, fieldNumber: 1)
    } }()
    try { if let v = self._genesisHash {
      try visitor.visitSingularBytesField(value: v, fieldNumber: 2)
    } }()
    try unknownFields.traverse(visitor: &visitor)
  }

  static func ==(lhs: FusionClientHello, rhs: FusionClientHello) -> Bool {
    if lhs._version != rhs._version {return false}
    if lhs._genesisHash != rhs._genesisHash {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}

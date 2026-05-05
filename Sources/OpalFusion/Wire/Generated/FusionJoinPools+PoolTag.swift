// FusionJoinPools+PoolTag.swift

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import SwiftProtobuf

extension FusionJoinPools {
  struct PoolTag: Sendable {
    // SwiftProtobuf.Message conformance is added in an extension below. See the
    // `Message` and `Message+*Additions` files in the SwiftProtobuf library for
    // methods supported on all messages.

    /// These tags can be used to client to stop the server from including
    /// the client too many times in the same fusion. Thus, the client can
    /// connect many times without fear of fusing with themselves.
    var id: Data {
      get {_id ?? Data()}
      set {_id = newValue}
    }
    /// Returns true if `id` has been explicitly set.
    var hasID: Bool {self._id != nil}
    /// Clears the value of `id`. Subsequent reads from it will return its default value.
    mutating func clearID() {self._id = nil}

    /// between 1 and 5 inclusive
    var limit: UInt32 {
      get {_limit ?? 0}
      set {_limit = newValue}
    }
    /// Returns true if `limit` has been explicitly set.
    var hasLimit: Bool {self._limit != nil}
    /// Clears the value of `limit`. Subsequent reads from it will return its default value.
    mutating func clearLimit() {self._limit = nil}

    /// whether to do an IP-less tag -- this will collide with all other users, make sure it's random so you can't get DoSed.
    var noIp: Bool {
      get {_noIp ?? false}
      set {_noIp = newValue}
    }
    /// Returns true if `noIp` has been explicitly set.
    var hasNoIp: Bool {self._noIp != nil}
    /// Clears the value of `noIp`. Subsequent reads from it will return its default value.
    mutating func clearNoIp() {self._noIp = nil}

    var unknownFields = SwiftProtobuf.UnknownStorage()

    init() {}

    fileprivate var _id: Data? = nil
    fileprivate var _limit: UInt32? = nil
    fileprivate var _noIp: Bool? = nil
  }
}

extension FusionJoinPools.PoolTag: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  static let protoMessageName: String = FusionJoinPools.protoMessageName + ".PoolTag"
  static let _protobuf_nameMap = SwiftProtobuf._NameMap(bytecode: "\0\u{1}id\0\u{1}limit\0\u{3}no_ip\0")

  public var isInitialized: Bool {
    if self._id == nil {return false}
    if self._limit == nil {return false}
    return true
  }

  mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      // The use of inline closures is to circumvent an issue where the compiler
      // allocates stack space for every case branch when no optimizations are
      // enabled. https://github.com/apple/swift-protobuf/issues/1034
      switch fieldNumber {
      case 1: try { try decoder.decodeSingularBytesField(value: &self._id) }()
      case 2: try { try decoder.decodeSingularUInt32Field(value: &self._limit) }()
      case 3: try { try decoder.decodeSingularBoolField(value: &self._noIp) }()
      default: break
      }
    }
  }

  func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    // The use of inline closures is to circumvent an issue where the compiler
    // allocates stack space for every if/case branch local when no optimizations
    // are enabled. https://github.com/apple/swift-protobuf/issues/1034 and
    // https://github.com/apple/swift-protobuf/issues/1182
    try { if let v = self._id {
      try visitor.visitSingularBytesField(value: v, fieldNumber: 1)
    } }()
    try { if let v = self._limit {
      try visitor.visitSingularUInt32Field(value: v, fieldNumber: 2)
    } }()
    try { if let v = self._noIp {
      try visitor.visitSingularBoolField(value: v, fieldNumber: 3)
    } }()
    try unknownFields.traverse(visitor: &visitor)
  }

  static func ==(lhs: FusionJoinPools.PoolTag, rhs: FusionJoinPools.PoolTag) -> Bool {
    if lhs._id != rhs._id {return false}
    if lhs._limit != rhs._limit {return false}
    if lhs._noIp != rhs._noIp {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}

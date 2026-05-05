// FusionTierStatusUpdate+TierStatus.swift

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import SwiftProtobuf

extension FusionTierStatusUpdate {
  struct TierStatus: Sendable {
    // SwiftProtobuf.Message conformance is added in an extension below. See the
    // `Message` and `Message+*Additions` files in the SwiftProtobuf library for
    // methods supported on all messages.

    /// in future, we will want server to indicate 'remaining time' and mask number of players.
    /// note: if player is in queue then a status will be ommitted.
    var players: UInt32 {
      get {_players ?? 0}
      set {_players = newValue}
    }
    /// Returns true if `players` has been explicitly set.
    var hasPlayers: Bool {self._players != nil}
    /// Clears the value of `players`. Subsequent reads from it will return its default value.
    mutating func clearPlayers() {self._players = nil}

    /// minimum required to start (may have delay to allow extra)
    var minPlayers: UInt32 {
      get {_minPlayers ?? 0}
      set {_minPlayers = newValue}
    }
    /// Returns true if `minPlayers` has been explicitly set.
    var hasMinPlayers: Bool {self._minPlayers != nil}
    /// Clears the value of `minPlayers`. Subsequent reads from it will return its default value.
    mutating func clearMinPlayers() {self._minPlayers = nil}

    /// maximum allowed (immediate start)
    var maxPlayers: UInt32 {
      get {_maxPlayers ?? 0}
      set {_maxPlayers = newValue}
    }
    /// Returns true if `maxPlayers` has been explicitly set.
    var hasMaxPlayers: Bool {self._maxPlayers != nil}
    /// Clears the value of `maxPlayers`. Subsequent reads from it will return its default value.
    mutating func clearMaxPlayers() {self._maxPlayers = nil}

    var timeRemaining: UInt32 {
      get {_timeRemaining ?? 0}
      set {_timeRemaining = newValue}
    }
    /// Returns true if `timeRemaining` has been explicitly set.
    var hasTimeRemaining: Bool {self._timeRemaining != nil}
    /// Clears the value of `timeRemaining`. Subsequent reads from it will return its default value.
    mutating func clearTimeRemaining() {self._timeRemaining = nil}

    var unknownFields = SwiftProtobuf.UnknownStorage()

    init() {}

    fileprivate var _players: UInt32? = nil
    fileprivate var _minPlayers: UInt32? = nil
    fileprivate var _maxPlayers: UInt32? = nil
    fileprivate var _timeRemaining: UInt32? = nil
  }
}

extension FusionTierStatusUpdate.TierStatus: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  static let protoMessageName: String = FusionTierStatusUpdate.protoMessageName + ".TierStatus"
  static let _protobuf_nameMap = SwiftProtobuf._NameMap(bytecode: "\0\u{1}players\0\u{3}min_players\0\u{3}max_players\0\u{3}time_remaining\0")

  mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      // The use of inline closures is to circumvent an issue where the compiler
      // allocates stack space for every case branch when no optimizations are
      // enabled. https://github.com/apple/swift-protobuf/issues/1034
      switch fieldNumber {
      case 1: try { try decoder.decodeSingularUInt32Field(value: &self._players) }()
      case 2: try { try decoder.decodeSingularUInt32Field(value: &self._minPlayers) }()
      case 3: try { try decoder.decodeSingularUInt32Field(value: &self._maxPlayers) }()
      case 4: try { try decoder.decodeSingularUInt32Field(value: &self._timeRemaining) }()
      default: break
      }
    }
  }

  func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    // The use of inline closures is to circumvent an issue where the compiler
    // allocates stack space for every if/case branch local when no optimizations
    // are enabled. https://github.com/apple/swift-protobuf/issues/1034 and
    // https://github.com/apple/swift-protobuf/issues/1182
    try { if let v = self._players {
      try visitor.visitSingularUInt32Field(value: v, fieldNumber: 1)
    } }()
    try { if let v = self._minPlayers {
      try visitor.visitSingularUInt32Field(value: v, fieldNumber: 2)
    } }()
    try { if let v = self._maxPlayers {
      try visitor.visitSingularUInt32Field(value: v, fieldNumber: 3)
    } }()
    try { if let v = self._timeRemaining {
      try visitor.visitSingularUInt32Field(value: v, fieldNumber: 4)
    } }()
    try unknownFields.traverse(visitor: &visitor)
  }

  static func ==(lhs: FusionTierStatusUpdate.TierStatus, rhs: FusionTierStatusUpdate.TierStatus) -> Bool {
    if lhs._players != rhs._players {return false}
    if lhs._minPlayers != rhs._minPlayers {return false}
    if lhs._maxPlayers != rhs._maxPlayers {return false}
    if lhs._timeRemaining != rhs._timeRemaining {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}

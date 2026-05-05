// FusionBlames+BlameProof.swift

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import SwiftProtobuf

extension FusionBlames {
  struct BlameProof: Sendable {
    // SwiftProtobuf.Message conformance is added in an extension below. See the
    // `Message` and `Message+*Additions` files in the SwiftProtobuf library for
    // methods supported on all messages.

    var whichProof: UInt32 {
      get {_whichProof ?? 0}
      set {_whichProof = newValue}
    }
    /// Returns true if `whichProof` has been explicitly set.
    var hasWhichProof: Bool {self._whichProof != nil}
    /// Clears the value of `whichProof`. Subsequent reads from it will return its default value.
    mutating func clearWhichProof() {self._whichProof = nil}

    var decrypter: FusionBlames.BlameProof.OneOfDecrypter? = nil

    /// 32 byte, preferred if the proof decryption works at all
    var sessionKey: Data {
      get {
        if case .sessionKey(let v)? = decrypter {return v}
        return Data()
      }
      set {decrypter = .sessionKey(newValue)}
    }

    /// 32 byte scalar
    var privkey: Data {
      get {
        if case .privkey(let v)? = decrypter {return v}
        return Data()
      }
      set {decrypter = .privkey(newValue)}
    }

    /// Some errors can only be discovered by checking the blockchain,
    /// Namely, if an input UTXO is missing/spent/unconfirmed/different
    /// scriptpubkey/different amount, than indicated.
    var needLookupBlockchain: Bool {
      get {_needLookupBlockchain ?? false}
      set {_needLookupBlockchain = newValue}
    }
    /// Returns true if `needLookupBlockchain` has been explicitly set.
    var hasNeedLookupBlockchain: Bool {self._needLookupBlockchain != nil}
    /// Clears the value of `needLookupBlockchain`. Subsequent reads from it will return its default value.
    mutating func clearNeedLookupBlockchain() {self._needLookupBlockchain = nil}

    /// The client can indicate why it thinks the blame is deserved. In
    /// case the server finds no issue, this string might help for debugging.
    var blameReason: String {
      get {_blameReason ?? String()}
      set {_blameReason = newValue}
    }
    /// Returns true if `blameReason` has been explicitly set.
    var hasBlameReason: Bool {self._blameReason != nil}
    /// Clears the value of `blameReason`. Subsequent reads from it will return its default value.
    mutating func clearBlameReason() {self._blameReason = nil}

    var unknownFields = SwiftProtobuf.UnknownStorage()
    init() {}

    fileprivate var _whichProof: UInt32? = nil
    fileprivate var _needLookupBlockchain: Bool? = nil
    fileprivate var _blameReason: String? = nil
  }
}

extension FusionBlames.BlameProof: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  static let protoMessageName: String = FusionBlames.protoMessageName + ".BlameProof"
  static let _protobuf_nameMap = SwiftProtobuf._NameMap(bytecode: "\0\u{3}which_proof\0\u{3}session_key\0\u{1}privkey\0\u{3}need_lookup_blockchain\0\u{3}blame_reason\0")

  public var isInitialized: Bool {
    if self._whichProof == nil {return false}
    return true
  }

  mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      // The use of inline closures is to circumvent an issue where the compiler
      // allocates stack space for every case branch when no optimizations are
      // enabled. https://github.com/apple/swift-protobuf/issues/1034
      switch fieldNumber {
      case 1: try { try decoder.decodeSingularUInt32Field(value: &self._whichProof) }()
      case 2: try {
        var v: Data?
        try decoder.decodeSingularBytesField(value: &v)
        if let v = v {
          if self.decrypter != nil {try decoder.handleConflictingOneOf()}
          self.decrypter = .sessionKey(v)
        }
      }()
      case 3: try {
        var v: Data?
        try decoder.decodeSingularBytesField(value: &v)
        if let v = v {
          if self.decrypter != nil {try decoder.handleConflictingOneOf()}
          self.decrypter = .privkey(v)
        }
      }()
      case 4: try { try decoder.decodeSingularBoolField(value: &self._needLookupBlockchain) }()
      case 5: try { try decoder.decodeSingularStringField(value: &self._blameReason) }()
      default: break
      }
    }
  }

  func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    // The use of inline closures is to circumvent an issue where the compiler
    // allocates stack space for every if/case branch local when no optimizations
    // are enabled. https://github.com/apple/swift-protobuf/issues/1034 and
    // https://github.com/apple/swift-protobuf/issues/1182
    try { if let v = self._whichProof {
      try visitor.visitSingularUInt32Field(value: v, fieldNumber: 1)
    } }()
    switch self.decrypter {
    case .sessionKey?: try {
      guard case .sessionKey(let v)? = self.decrypter else { preconditionFailure() }
      try visitor.visitSingularBytesField(value: v, fieldNumber: 2)
    }()
    case .privkey?: try {
      guard case .privkey(let v)? = self.decrypter else { preconditionFailure() }
      try visitor.visitSingularBytesField(value: v, fieldNumber: 3)
    }()
    case nil: break
    }
    try { if let v = self._needLookupBlockchain {
      try visitor.visitSingularBoolField(value: v, fieldNumber: 4)
    } }()
    try { if let v = self._blameReason {
      try visitor.visitSingularStringField(value: v, fieldNumber: 5)
    } }()
    try unknownFields.traverse(visitor: &visitor)
  }

  static func ==(lhs: FusionBlames.BlameProof, rhs: FusionBlames.BlameProof) -> Bool {
    if lhs._whichProof != rhs._whichProof {return false}
    if lhs.decrypter != rhs.decrypter {return false}
    if lhs._needLookupBlockchain != rhs._needLookupBlockchain {return false}
    if lhs._blameReason != rhs._blameReason {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}

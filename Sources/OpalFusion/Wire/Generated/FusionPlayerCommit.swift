// FusionPlayerCommit.swift

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import SwiftProtobuf

struct FusionPlayerCommit: Sendable {
  // SwiftProtobuf.Message conformance is added in an extension below. See the
  // `Message` and `Message+*Additions` files in the SwiftProtobuf library for
  // methods supported on all messages.

  /// serialized InitialCommitment messages; server will repeat them later, verbatim.
  var initialCommitments: [Data] = []

  var excessFee: UInt64 {
    get {_excessFee ?? 0}
    set {_excessFee = newValue}
  }
  /// Returns true if `excessFee` has been explicitly set.
  var hasExcessFee: Bool {self._excessFee != nil}
  /// Clears the value of `excessFee`. Subsequent reads from it will return its default value.
  mutating func clearExcessFee() {self._excessFee = nil}

  /// 32 bytes
  var pedersenTotalNonce: Data {
    get {_pedersenTotalNonce ?? Data()}
    set {_pedersenTotalNonce = newValue}
  }
  /// Returns true if `pedersenTotalNonce` has been explicitly set.
  var hasPedersenTotalNonce: Bool {self._pedersenTotalNonce != nil}
  /// Clears the value of `pedersenTotalNonce`. Subsequent reads from it will return its default value.
  mutating func clearPedersenTotalNonce() {self._pedersenTotalNonce = nil}

  /// 32 bytes
  var randomNumberCommitment: Data {
    get {_randomNumberCommitment ?? Data()}
    set {_randomNumberCommitment = newValue}
  }
  /// Returns true if `randomNumberCommitment` has been explicitly set.
  var hasRandomNumberCommitment: Bool {self._randomNumberCommitment != nil}
  /// Clears the value of `randomNumberCommitment`. Subsequent reads from it will return its default value.
  mutating func clearRandomNumberCommitment() {self._randomNumberCommitment = nil}

  /// 32 byte scalars
  var blindSigRequests: [Data] = []

  var unknownFields = SwiftProtobuf.UnknownStorage()

  init() {}

  fileprivate var _excessFee: UInt64? = nil
  fileprivate var _pedersenTotalNonce: Data? = nil
  fileprivate var _randomNumberCommitment: Data? = nil
}

extension FusionPlayerCommit: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  static let protoMessageName: String = "fusion.PlayerCommit"
  static let _protobuf_nameMap = SwiftProtobuf._NameMap(bytecode: "\0\u{3}initial_commitments\0\u{3}excess_fee\0\u{3}pedersen_total_nonce\0\u{3}random_number_commitment\0\u{3}blind_sig_requests\0")

  public var isInitialized: Bool {
    if self._excessFee == nil {return false}
    if self._pedersenTotalNonce == nil {return false}
    if self._randomNumberCommitment == nil {return false}
    return true
  }

  mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      // The use of inline closures is to circumvent an issue where the compiler
      // allocates stack space for every case branch when no optimizations are
      // enabled. https://github.com/apple/swift-protobuf/issues/1034
      switch fieldNumber {
      case 1: try { try decoder.decodeRepeatedBytesField(value: &self.initialCommitments) }()
      case 2: try { try decoder.decodeSingularUInt64Field(value: &self._excessFee) }()
      case 3: try { try decoder.decodeSingularBytesField(value: &self._pedersenTotalNonce) }()
      case 4: try { try decoder.decodeSingularBytesField(value: &self._randomNumberCommitment) }()
      case 5: try { try decoder.decodeRepeatedBytesField(value: &self.blindSigRequests) }()
      default: break
      }
    }
  }

  func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    // The use of inline closures is to circumvent an issue where the compiler
    // allocates stack space for every if/case branch local when no optimizations
    // are enabled. https://github.com/apple/swift-protobuf/issues/1034 and
    // https://github.com/apple/swift-protobuf/issues/1182
    if !self.initialCommitments.isEmpty {
      try visitor.visitRepeatedBytesField(value: self.initialCommitments, fieldNumber: 1)
    }
    try { if let v = self._excessFee {
      try visitor.visitSingularUInt64Field(value: v, fieldNumber: 2)
    } }()
    try { if let v = self._pedersenTotalNonce {
      try visitor.visitSingularBytesField(value: v, fieldNumber: 3)
    } }()
    try { if let v = self._randomNumberCommitment {
      try visitor.visitSingularBytesField(value: v, fieldNumber: 4)
    } }()
    if !self.blindSigRequests.isEmpty {
      try visitor.visitRepeatedBytesField(value: self.blindSigRequests, fieldNumber: 5)
    }
    try unknownFields.traverse(visitor: &visitor)
  }

  static func ==(lhs: FusionPlayerCommit, rhs: FusionPlayerCommit) -> Bool {
    if lhs.initialCommitments != rhs.initialCommitments {return false}
    if lhs._excessFee != rhs._excessFee {return false}
    if lhs._pedersenTotalNonce != rhs._pedersenTotalNonce {return false}
    if lhs._randomNumberCommitment != rhs._randomNumberCommitment {return false}
    if lhs.blindSigRequests != rhs.blindSigRequests {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}

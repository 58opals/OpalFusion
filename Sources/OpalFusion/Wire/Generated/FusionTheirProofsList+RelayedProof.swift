// FusionTheirProofsList+RelayedProof.swift

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import SwiftProtobuf

extension FusionTheirProofsList {
  struct RelayedProof: Sendable {
    // SwiftProtobuf.Message conformance is added in an extension below. See the
    // `Message` and `Message+*Additions` files in the SwiftProtobuf library for
    // methods supported on all messages.

    var encryptedProof: Data {
      get {_encryptedProof ?? Data()}
      set {_encryptedProof = newValue}
    }
    /// Returns true if `encryptedProof` has been explicitly set.
    var hasEncryptedProof: Bool {self._encryptedProof != nil}
    /// Clears the value of `encryptedProof`. Subsequent reads from it will return its default value.
    mutating func clearEncryptedProof() {self._encryptedProof = nil}

    /// which of the commitments is being proven (index in full list)
    var srcCommitmentIdx: UInt32 {
      get {_srcCommitmentIdx ?? 0}
      set {_srcCommitmentIdx = newValue}
    }
    /// Returns true if `srcCommitmentIdx` has been explicitly set.
    var hasSrcCommitmentIdx: Bool {self._srcCommitmentIdx != nil}
    /// Clears the value of `srcCommitmentIdx`. Subsequent reads from it will return its default value.
    mutating func clearSrcCommitmentIdx() {self._srcCommitmentIdx = nil}

    /// which of the recipient's keys will unlock the encryption (index in player list)
    var dstKeyIdx: UInt32 {
      get {_dstKeyIdx ?? 0}
      set {_dstKeyIdx = newValue}
    }
    /// Returns true if `dstKeyIdx` has been explicitly set.
    var hasDstKeyIdx: Bool {self._dstKeyIdx != nil}
    /// Clears the value of `dstKeyIdx`. Subsequent reads from it will return its default value.
    mutating func clearDstKeyIdx() {self._dstKeyIdx = nil}

    var unknownFields = SwiftProtobuf.UnknownStorage()

    init() {}

    fileprivate var _encryptedProof: Data? = nil
    fileprivate var _srcCommitmentIdx: UInt32? = nil
    fileprivate var _dstKeyIdx: UInt32? = nil
  }
}

extension FusionTheirProofsList.RelayedProof: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  static let protoMessageName: String = FusionTheirProofsList.protoMessageName + ".RelayedProof"
  static let _protobuf_nameMap = SwiftProtobuf._NameMap(bytecode: "\0\u{3}encrypted_proof\0\u{3}src_commitment_idx\0\u{3}dst_key_idx\0")

  public var isInitialized: Bool {
    if self._encryptedProof == nil {return false}
    if self._srcCommitmentIdx == nil {return false}
    if self._dstKeyIdx == nil {return false}
    return true
  }

  mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      // The use of inline closures is to circumvent an issue where the compiler
      // allocates stack space for every case branch when no optimizations are
      // enabled. https://github.com/apple/swift-protobuf/issues/1034
      switch fieldNumber {
      case 1: try { try decoder.decodeSingularBytesField(value: &self._encryptedProof) }()
      case 2: try { try decoder.decodeSingularUInt32Field(value: &self._srcCommitmentIdx) }()
      case 3: try { try decoder.decodeSingularUInt32Field(value: &self._dstKeyIdx) }()
      default: break
      }
    }
  }

  func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    // The use of inline closures is to circumvent an issue where the compiler
    // allocates stack space for every if/case branch local when no optimizations
    // are enabled. https://github.com/apple/swift-protobuf/issues/1034 and
    // https://github.com/apple/swift-protobuf/issues/1182
    try { if let v = self._encryptedProof {
      try visitor.visitSingularBytesField(value: v, fieldNumber: 1)
    } }()
    try { if let v = self._srcCommitmentIdx {
      try visitor.visitSingularUInt32Field(value: v, fieldNumber: 2)
    } }()
    try { if let v = self._dstKeyIdx {
      try visitor.visitSingularUInt32Field(value: v, fieldNumber: 3)
    } }()
    try unknownFields.traverse(visitor: &visitor)
  }

  static func ==(lhs: FusionTheirProofsList.RelayedProof, rhs: FusionTheirProofsList.RelayedProof) -> Bool {
    if lhs._encryptedProof != rhs._encryptedProof {return false}
    if lhs._srcCommitmentIdx != rhs._srcCommitmentIdx {return false}
    if lhs._dstKeyIdx != rhs._dstKeyIdx {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}

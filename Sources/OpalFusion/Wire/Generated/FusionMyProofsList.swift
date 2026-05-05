// FusionMyProofsList.swift

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import SwiftProtobuf

struct FusionMyProofsList: Sendable {
  // SwiftProtobuf.Message conformance is added in an extension below. See the
  // `Message` and `Message+*Additions` files in the SwiftProtobuf library for
  // methods supported on all messages.

  var encryptedProofs: [Data] = []

  /// the number we committed to, back in phase 3
  var randomNumber: Data {
    get {_randomNumber ?? Data()}
    set {_randomNumber = newValue}
  }
  /// Returns true if `randomNumber` has been explicitly set.
  var hasRandomNumber: Bool {self._randomNumber != nil}
  /// Clears the value of `randomNumber`. Subsequent reads from it will return its default value.
  mutating func clearRandomNumber() {self._randomNumber = nil}

  var unknownFields = SwiftProtobuf.UnknownStorage()

  init() {}

  fileprivate var _randomNumber: Data? = nil
}

extension FusionMyProofsList: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  static let protoMessageName: String = "fusion.MyProofsList"
  static let _protobuf_nameMap = SwiftProtobuf._NameMap(bytecode: "\0\u{3}encrypted_proofs\0\u{3}random_number\0")

  public var isInitialized: Bool {
    if self._randomNumber == nil {return false}
    return true
  }

  mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      // The use of inline closures is to circumvent an issue where the compiler
      // allocates stack space for every case branch when no optimizations are
      // enabled. https://github.com/apple/swift-protobuf/issues/1034
      switch fieldNumber {
      case 1: try { try decoder.decodeRepeatedBytesField(value: &self.encryptedProofs) }()
      case 2: try { try decoder.decodeSingularBytesField(value: &self._randomNumber) }()
      default: break
      }
    }
  }

  func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    // The use of inline closures is to circumvent an issue where the compiler
    // allocates stack space for every if/case branch local when no optimizations
    // are enabled. https://github.com/apple/swift-protobuf/issues/1034 and
    // https://github.com/apple/swift-protobuf/issues/1182
    if !self.encryptedProofs.isEmpty {
      try visitor.visitRepeatedBytesField(value: self.encryptedProofs, fieldNumber: 1)
    }
    try { if let v = self._randomNumber {
      try visitor.visitSingularBytesField(value: v, fieldNumber: 2)
    } }()
    try unknownFields.traverse(visitor: &visitor)
  }

  static func ==(lhs: FusionMyProofsList, rhs: FusionMyProofsList) -> Bool {
    if lhs.encryptedProofs != rhs.encryptedProofs {return false}
    if lhs._randomNumber != rhs._randomNumber {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}

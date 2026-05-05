// FusionComponent.swift

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import SwiftProtobuf

struct FusionComponent: Sendable {
  // SwiftProtobuf.Message conformance is added in an extension below. See the
  // `Message` and `Message+*Additions` files in the SwiftProtobuf library for
  // methods supported on all messages.

  /// 32 bytes
  var saltCommitment: Data {
    get {_saltCommitment ?? Data()}
    set {_saltCommitment = newValue}
  }
  /// Returns true if `saltCommitment` has been explicitly set.
  var hasSaltCommitment: Bool {self._saltCommitment != nil}
  /// Clears the value of `saltCommitment`. Subsequent reads from it will return its default value.
  mutating func clearSaltCommitment() {self._saltCommitment = nil}

  var component: FusionComponent.OneOfComponent? = nil

  var input: FusionInputComponent {
    get {
      if case .input(let v)? = component {return v}
      return FusionInputComponent()
    }
    set {component = .input(newValue)}
  }

  var output: FusionOutputComponent {
    get {
      if case .output(let v)? = component {return v}
      return FusionOutputComponent()
    }
    set {component = .output(newValue)}
  }

  var blank: FusionBlankComponent {
    get {
      if case .blank(let v)? = component {return v}
      return FusionBlankComponent()
    }
    set {component = .blank(newValue)}
  }

  var unknownFields = SwiftProtobuf.UnknownStorage()
  init() {}

  fileprivate var _saltCommitment: Data? = nil
}

extension FusionComponent: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  static let protoMessageName: String = "fusion.Component"
  static let _protobuf_nameMap = SwiftProtobuf._NameMap(bytecode: "\0\u{3}salt_commitment\0\u{1}input\0\u{1}output\0\u{1}blank\0")

  public var isInitialized: Bool {
    if self._saltCommitment == nil {return false}
    if let v = self.component, !v.isInitialized {return false}
    return true
  }

  mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      // The use of inline closures is to circumvent an issue where the compiler
      // allocates stack space for every case branch when no optimizations are
      // enabled. https://github.com/apple/swift-protobuf/issues/1034
      switch fieldNumber {
      case 1: try { try decoder.decodeSingularBytesField(value: &self._saltCommitment) }()
      case 2: try {
        var v: FusionInputComponent?
        var hadOneofValue = false
        if let current = self.component {
          hadOneofValue = true
          if case .input(let m) = current {v = m}
        }
        try decoder.decodeSingularMessageField(value: &v)
        if let v = v {
          if hadOneofValue {try decoder.handleConflictingOneOf()}
          self.component = .input(v)
        }
      }()
      case 3: try {
        var v: FusionOutputComponent?
        var hadOneofValue = false
        if let current = self.component {
          hadOneofValue = true
          if case .output(let m) = current {v = m}
        }
        try decoder.decodeSingularMessageField(value: &v)
        if let v = v {
          if hadOneofValue {try decoder.handleConflictingOneOf()}
          self.component = .output(v)
        }
      }()
      case 4: try {
        var v: FusionBlankComponent?
        var hadOneofValue = false
        if let current = self.component {
          hadOneofValue = true
          if case .blank(let m) = current {v = m}
        }
        try decoder.decodeSingularMessageField(value: &v)
        if let v = v {
          if hadOneofValue {try decoder.handleConflictingOneOf()}
          self.component = .blank(v)
        }
      }()
      default: break
      }
    }
  }

  func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    // The use of inline closures is to circumvent an issue where the compiler
    // allocates stack space for every if/case branch local when no optimizations
    // are enabled. https://github.com/apple/swift-protobuf/issues/1034 and
    // https://github.com/apple/swift-protobuf/issues/1182
    try { if let v = self._saltCommitment {
      try visitor.visitSingularBytesField(value: v, fieldNumber: 1)
    } }()
    switch self.component {
    case .input?: try {
      guard case .input(let v)? = self.component else { preconditionFailure() }
      try visitor.visitSingularMessageField(value: v, fieldNumber: 2)
    }()
    case .output?: try {
      guard case .output(let v)? = self.component else { preconditionFailure() }
      try visitor.visitSingularMessageField(value: v, fieldNumber: 3)
    }()
    case .blank?: try {
      guard case .blank(let v)? = self.component else { preconditionFailure() }
      try visitor.visitSingularMessageField(value: v, fieldNumber: 4)
    }()
    case nil: break
    }
    try unknownFields.traverse(visitor: &visitor)
  }

  static func ==(lhs: FusionComponent, rhs: FusionComponent) -> Bool {
    if lhs._saltCommitment != rhs._saltCommitment {return false}
    if lhs.component != rhs.component {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}

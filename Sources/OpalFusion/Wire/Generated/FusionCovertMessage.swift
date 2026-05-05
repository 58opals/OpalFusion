// FusionCovertMessage.swift

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import SwiftProtobuf

struct FusionCovertMessage: Sendable {
  // SwiftProtobuf.Message conformance is added in an extension below. See the
  // `Message` and `Message+*Additions` files in the SwiftProtobuf library for
  // methods supported on all messages.

  var msg: FusionCovertMessage.OneOfMessage? = nil

  var component: FusionCovertComponent {
    get {
      if case .component(let v)? = msg {return v}
      return FusionCovertComponent()
    }
    set {msg = .component(newValue)}
  }

  var signature: FusionCovertTransactionSignature {
    get {
      if case .signature(let v)? = msg {return v}
      return FusionCovertTransactionSignature()
    }
    set {msg = .signature(newValue)}
  }

  var ping: FusionPing {
    get {
      if case .ping(let v)? = msg {return v}
      return FusionPing()
    }
    set {msg = .ping(newValue)}
  }

  var unknownFields = SwiftProtobuf.UnknownStorage()
  init() {}
}

extension FusionCovertMessage: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  static let protoMessageName: String = "fusion.CovertMessage"
  static let _protobuf_nameMap = SwiftProtobuf._NameMap(bytecode: "\0\u{1}component\0\u{1}signature\0\u{1}ping\0")

  public var isInitialized: Bool {
    if let v = self.msg, !v.isInitialized {return false}
    return true
  }

  mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      // The use of inline closures is to circumvent an issue where the compiler
      // allocates stack space for every case branch when no optimizations are
      // enabled. https://github.com/apple/swift-protobuf/issues/1034
      switch fieldNumber {
      case 1: try {
        var v: FusionCovertComponent?
        var hadOneofValue = false
        if let current = self.msg {
          hadOneofValue = true
          if case .component(let m) = current {v = m}
        }
        try decoder.decodeSingularMessageField(value: &v)
        if let v = v {
          if hadOneofValue {try decoder.handleConflictingOneOf()}
          self.msg = .component(v)
        }
      }()
      case 2: try {
        var v: FusionCovertTransactionSignature?
        var hadOneofValue = false
        if let current = self.msg {
          hadOneofValue = true
          if case .signature(let m) = current {v = m}
        }
        try decoder.decodeSingularMessageField(value: &v)
        if let v = v {
          if hadOneofValue {try decoder.handleConflictingOneOf()}
          self.msg = .signature(v)
        }
      }()
      case 3: try {
        var v: FusionPing?
        var hadOneofValue = false
        if let current = self.msg {
          hadOneofValue = true
          if case .ping(let m) = current {v = m}
        }
        try decoder.decodeSingularMessageField(value: &v)
        if let v = v {
          if hadOneofValue {try decoder.handleConflictingOneOf()}
          self.msg = .ping(v)
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
    switch self.msg {
    case .component?: try {
      guard case .component(let v)? = self.msg else { preconditionFailure() }
      try visitor.visitSingularMessageField(value: v, fieldNumber: 1)
    }()
    case .signature?: try {
      guard case .signature(let v)? = self.msg else { preconditionFailure() }
      try visitor.visitSingularMessageField(value: v, fieldNumber: 2)
    }()
    case .ping?: try {
      guard case .ping(let v)? = self.msg else { preconditionFailure() }
      try visitor.visitSingularMessageField(value: v, fieldNumber: 3)
    }()
    case nil: break
    }
    try unknownFields.traverse(visitor: &visitor)
  }

  static func ==(lhs: FusionCovertMessage, rhs: FusionCovertMessage) -> Bool {
    if lhs.msg != rhs.msg {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}

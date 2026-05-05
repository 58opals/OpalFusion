// FusionCovertResponse.swift

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import SwiftProtobuf

struct FusionCovertResponse: Sendable {
  // SwiftProtobuf.Message conformance is added in an extension below. See the
  // `Message` and `Message+*Additions` files in the SwiftProtobuf library for
  // methods supported on all messages.

  var msg: FusionCovertResponse.OneOfMessage? = nil

  var ok: FusionAcknowledgement {
    get {
      if case .ok(let v)? = msg {return v}
      return FusionAcknowledgement()
    }
    set {msg = .ok(newValue)}
  }

  var error: FusionError {
    get {
      if case .error(let v)? = msg {return v}
      return FusionError()
    }
    set {msg = .error(newValue)}
  }

  var unknownFields = SwiftProtobuf.UnknownStorage()
  init() {}
}

extension FusionCovertResponse: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  static let protoMessageName: String = "fusion.CovertResponse"
  static let _protobuf_nameMap = SwiftProtobuf._NameMap(bytecode: "\0\u{1}ok\0\u{2}\u{e}error\0")

  mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      // The use of inline closures is to circumvent an issue where the compiler
      // allocates stack space for every case branch when no optimizations are
      // enabled. https://github.com/apple/swift-protobuf/issues/1034
      switch fieldNumber {
      case 1: try {
        var v: FusionAcknowledgement?
        var hadOneofValue = false
        if let current = self.msg {
          hadOneofValue = true
          if case .ok(let m) = current {v = m}
        }
        try decoder.decodeSingularMessageField(value: &v)
        if let v = v {
          if hadOneofValue {try decoder.handleConflictingOneOf()}
          self.msg = .ok(v)
        }
      }()
      case 15: try {
        var v: FusionError?
        var hadOneofValue = false
        if let current = self.msg {
          hadOneofValue = true
          if case .error(let m) = current {v = m}
        }
        try decoder.decodeSingularMessageField(value: &v)
        if let v = v {
          if hadOneofValue {try decoder.handleConflictingOneOf()}
          self.msg = .error(v)
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
    case .ok?: try {
      guard case .ok(let v)? = self.msg else { preconditionFailure() }
      try visitor.visitSingularMessageField(value: v, fieldNumber: 1)
    }()
    case .error?: try {
      guard case .error(let v)? = self.msg else { preconditionFailure() }
      try visitor.visitSingularMessageField(value: v, fieldNumber: 15)
    }()
    case nil: break
    }
    try unknownFields.traverse(visitor: &visitor)
  }

  static func ==(lhs: FusionCovertResponse, rhs: FusionCovertResponse) -> Bool {
    if lhs.msg != rhs.msg {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}

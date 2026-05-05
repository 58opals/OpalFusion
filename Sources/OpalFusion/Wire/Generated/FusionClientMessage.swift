// FusionClientMessage.swift

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import SwiftProtobuf

struct FusionClientMessage: Sendable {
  // SwiftProtobuf.Message conformance is added in an extension below. See the
  // `Message` and `Message+*Additions` files in the SwiftProtobuf library for
  // methods supported on all messages.

  var msg: FusionClientMessage.OneOfMessage? = nil

  var clienthello: FusionClientHello {
    get {
      if case .clienthello(let v)? = msg {return v}
      return FusionClientHello()
    }
    set {msg = .clienthello(newValue)}
  }

  var joinpools: FusionJoinPools {
    get {
      if case .joinpools(let v)? = msg {return v}
      return FusionJoinPools()
    }
    set {msg = .joinpools(newValue)}
  }

  var playercommit: FusionPlayerCommit {
    get {
      if case .playercommit(let v)? = msg {return v}
      return FusionPlayerCommit()
    }
    set {msg = .playercommit(newValue)}
  }

  var myproofslist: FusionMyProofsList {
    get {
      if case .myproofslist(let v)? = msg {return v}
      return FusionMyProofsList()
    }
    set {msg = .myproofslist(newValue)}
  }

  var blames: FusionBlames {
    get {
      if case .blames(let v)? = msg {return v}
      return FusionBlames()
    }
    set {msg = .blames(newValue)}
  }

  var unknownFields = SwiftProtobuf.UnknownStorage()
  init() {}
}

extension FusionClientMessage: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  static let protoMessageName: String = "fusion.ClientMessage"
  static let _protobuf_nameMap = SwiftProtobuf._NameMap(bytecode: "\0\u{1}clienthello\0\u{1}joinpools\0\u{1}playercommit\0\u{2}\u{2}myproofslist\0\u{1}blames\0")

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
        var v: FusionClientHello?
        var hadOneofValue = false
        if let current = self.msg {
          hadOneofValue = true
          if case .clienthello(let m) = current {v = m}
        }
        try decoder.decodeSingularMessageField(value: &v)
        if let v = v {
          if hadOneofValue {try decoder.handleConflictingOneOf()}
          self.msg = .clienthello(v)
        }
      }()
      case 2: try {
        var v: FusionJoinPools?
        var hadOneofValue = false
        if let current = self.msg {
          hadOneofValue = true
          if case .joinpools(let m) = current {v = m}
        }
        try decoder.decodeSingularMessageField(value: &v)
        if let v = v {
          if hadOneofValue {try decoder.handleConflictingOneOf()}
          self.msg = .joinpools(v)
        }
      }()
      case 3: try {
        var v: FusionPlayerCommit?
        var hadOneofValue = false
        if let current = self.msg {
          hadOneofValue = true
          if case .playercommit(let m) = current {v = m}
        }
        try decoder.decodeSingularMessageField(value: &v)
        if let v = v {
          if hadOneofValue {try decoder.handleConflictingOneOf()}
          self.msg = .playercommit(v)
        }
      }()
      case 5: try {
        var v: FusionMyProofsList?
        var hadOneofValue = false
        if let current = self.msg {
          hadOneofValue = true
          if case .myproofslist(let m) = current {v = m}
        }
        try decoder.decodeSingularMessageField(value: &v)
        if let v = v {
          if hadOneofValue {try decoder.handleConflictingOneOf()}
          self.msg = .myproofslist(v)
        }
      }()
      case 6: try {
        var v: FusionBlames?
        var hadOneofValue = false
        if let current = self.msg {
          hadOneofValue = true
          if case .blames(let m) = current {v = m}
        }
        try decoder.decodeSingularMessageField(value: &v)
        if let v = v {
          if hadOneofValue {try decoder.handleConflictingOneOf()}
          self.msg = .blames(v)
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
    case .clienthello?: try {
      guard case .clienthello(let v)? = self.msg else { preconditionFailure() }
      try visitor.visitSingularMessageField(value: v, fieldNumber: 1)
    }()
    case .joinpools?: try {
      guard case .joinpools(let v)? = self.msg else { preconditionFailure() }
      try visitor.visitSingularMessageField(value: v, fieldNumber: 2)
    }()
    case .playercommit?: try {
      guard case .playercommit(let v)? = self.msg else { preconditionFailure() }
      try visitor.visitSingularMessageField(value: v, fieldNumber: 3)
    }()
    case .myproofslist?: try {
      guard case .myproofslist(let v)? = self.msg else { preconditionFailure() }
      try visitor.visitSingularMessageField(value: v, fieldNumber: 5)
    }()
    case .blames?: try {
      guard case .blames(let v)? = self.msg else { preconditionFailure() }
      try visitor.visitSingularMessageField(value: v, fieldNumber: 6)
    }()
    case nil: break
    }
    try unknownFields.traverse(visitor: &visitor)
  }

  static func ==(lhs: FusionClientMessage, rhs: FusionClientMessage) -> Bool {
    if lhs.msg != rhs.msg {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}

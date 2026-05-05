// FusionServerMessage.swift

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import SwiftProtobuf

struct FusionServerMessage: Sendable {
  // SwiftProtobuf.Message conformance is added in an extension below. See the
  // `Message` and `Message+*Additions` files in the SwiftProtobuf library for
  // methods supported on all messages.

  var msg: FusionServerMessage.OneOfMessage? = nil

  var serverhello: FusionServerHello {
    get {
      if case .serverhello(let v)? = msg {return v}
      return FusionServerHello()
    }
    set {msg = .serverhello(newValue)}
  }

  var tierstatusupdate: FusionTierStatusUpdate {
    get {
      if case .tierstatusupdate(let v)? = msg {return v}
      return FusionTierStatusUpdate()
    }
    set {msg = .tierstatusupdate(newValue)}
  }

  var fusionbegin: FusionBeginMessage {
    get {
      if case .fusionbegin(let v)? = msg {return v}
      return FusionBeginMessage()
    }
    set {msg = .fusionbegin(newValue)}
  }

  var startround: FusionStartRound {
    get {
      if case .startround(let v)? = msg {return v}
      return FusionStartRound()
    }
    set {msg = .startround(newValue)}
  }

  var blindsigresponses: FusionBlindSignatureResponses {
    get {
      if case .blindsigresponses(let v)? = msg {return v}
      return FusionBlindSignatureResponses()
    }
    set {msg = .blindsigresponses(newValue)}
  }

  var allcommitments: FusionAllCommitments {
    get {
      if case .allcommitments(let v)? = msg {return v}
      return FusionAllCommitments()
    }
    set {msg = .allcommitments(newValue)}
  }

  var sharecovertcomponents: FusionShareCovertComponents {
    get {
      if case .sharecovertcomponents(let v)? = msg {return v}
      return FusionShareCovertComponents()
    }
    set {msg = .sharecovertcomponents(newValue)}
  }

  var fusionresult: FusionResultMessage {
    get {
      if case .fusionresult(let v)? = msg {return v}
      return FusionResultMessage()
    }
    set {msg = .fusionresult(newValue)}
  }

  var theirproofslist: FusionTheirProofsList {
    get {
      if case .theirproofslist(let v)? = msg {return v}
      return FusionTheirProofsList()
    }
    set {msg = .theirproofslist(newValue)}
  }

  var restartround: FusionRestartRound {
    get {
      if case .restartround(let v)? = msg {return v}
      return FusionRestartRound()
    }
    set {msg = .restartround(newValue)}
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

extension FusionServerMessage: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  static let protoMessageName: String = "fusion.ServerMessage"
  static let _protobuf_nameMap = SwiftProtobuf._NameMap(bytecode: "\0\u{1}serverhello\0\u{1}tierstatusupdate\0\u{1}fusionbegin\0\u{1}startround\0\u{1}blindsigresponses\0\u{1}allcommitments\0\u{1}sharecovertcomponents\0\u{1}fusionresult\0\u{1}theirproofslist\0\u{2}\u{5}restartround\0\u{1}error\0")

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
        var v: FusionServerHello?
        var hadOneofValue = false
        if let current = self.msg {
          hadOneofValue = true
          if case .serverhello(let m) = current {v = m}
        }
        try decoder.decodeSingularMessageField(value: &v)
        if let v = v {
          if hadOneofValue {try decoder.handleConflictingOneOf()}
          self.msg = .serverhello(v)
        }
      }()
      case 2: try {
        var v: FusionTierStatusUpdate?
        var hadOneofValue = false
        if let current = self.msg {
          hadOneofValue = true
          if case .tierstatusupdate(let m) = current {v = m}
        }
        try decoder.decodeSingularMessageField(value: &v)
        if let v = v {
          if hadOneofValue {try decoder.handleConflictingOneOf()}
          self.msg = .tierstatusupdate(v)
        }
      }()
      case 3: try {
        var v: FusionBeginMessage?
        var hadOneofValue = false
        if let current = self.msg {
          hadOneofValue = true
          if case .fusionbegin(let m) = current {v = m}
        }
        try decoder.decodeSingularMessageField(value: &v)
        if let v = v {
          if hadOneofValue {try decoder.handleConflictingOneOf()}
          self.msg = .fusionbegin(v)
        }
      }()
      case 4: try {
        var v: FusionStartRound?
        var hadOneofValue = false
        if let current = self.msg {
          hadOneofValue = true
          if case .startround(let m) = current {v = m}
        }
        try decoder.decodeSingularMessageField(value: &v)
        if let v = v {
          if hadOneofValue {try decoder.handleConflictingOneOf()}
          self.msg = .startround(v)
        }
      }()
      case 5: try {
        var v: FusionBlindSignatureResponses?
        var hadOneofValue = false
        if let current = self.msg {
          hadOneofValue = true
          if case .blindsigresponses(let m) = current {v = m}
        }
        try decoder.decodeSingularMessageField(value: &v)
        if let v = v {
          if hadOneofValue {try decoder.handleConflictingOneOf()}
          self.msg = .blindsigresponses(v)
        }
      }()
      case 6: try {
        var v: FusionAllCommitments?
        var hadOneofValue = false
        if let current = self.msg {
          hadOneofValue = true
          if case .allcommitments(let m) = current {v = m}
        }
        try decoder.decodeSingularMessageField(value: &v)
        if let v = v {
          if hadOneofValue {try decoder.handleConflictingOneOf()}
          self.msg = .allcommitments(v)
        }
      }()
      case 7: try {
        var v: FusionShareCovertComponents?
        var hadOneofValue = false
        if let current = self.msg {
          hadOneofValue = true
          if case .sharecovertcomponents(let m) = current {v = m}
        }
        try decoder.decodeSingularMessageField(value: &v)
        if let v = v {
          if hadOneofValue {try decoder.handleConflictingOneOf()}
          self.msg = .sharecovertcomponents(v)
        }
      }()
      case 8: try {
        var v: FusionResultMessage?
        var hadOneofValue = false
        if let current = self.msg {
          hadOneofValue = true
          if case .fusionresult(let m) = current {v = m}
        }
        try decoder.decodeSingularMessageField(value: &v)
        if let v = v {
          if hadOneofValue {try decoder.handleConflictingOneOf()}
          self.msg = .fusionresult(v)
        }
      }()
      case 9: try {
        var v: FusionTheirProofsList?
        var hadOneofValue = false
        if let current = self.msg {
          hadOneofValue = true
          if case .theirproofslist(let m) = current {v = m}
        }
        try decoder.decodeSingularMessageField(value: &v)
        if let v = v {
          if hadOneofValue {try decoder.handleConflictingOneOf()}
          self.msg = .theirproofslist(v)
        }
      }()
      case 14: try {
        var v: FusionRestartRound?
        var hadOneofValue = false
        if let current = self.msg {
          hadOneofValue = true
          if case .restartround(let m) = current {v = m}
        }
        try decoder.decodeSingularMessageField(value: &v)
        if let v = v {
          if hadOneofValue {try decoder.handleConflictingOneOf()}
          self.msg = .restartround(v)
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
    case .serverhello?: try {
      guard case .serverhello(let v)? = self.msg else { preconditionFailure() }
      try visitor.visitSingularMessageField(value: v, fieldNumber: 1)
    }()
    case .tierstatusupdate?: try {
      guard case .tierstatusupdate(let v)? = self.msg else { preconditionFailure() }
      try visitor.visitSingularMessageField(value: v, fieldNumber: 2)
    }()
    case .fusionbegin?: try {
      guard case .fusionbegin(let v)? = self.msg else { preconditionFailure() }
      try visitor.visitSingularMessageField(value: v, fieldNumber: 3)
    }()
    case .startround?: try {
      guard case .startround(let v)? = self.msg else { preconditionFailure() }
      try visitor.visitSingularMessageField(value: v, fieldNumber: 4)
    }()
    case .blindsigresponses?: try {
      guard case .blindsigresponses(let v)? = self.msg else { preconditionFailure() }
      try visitor.visitSingularMessageField(value: v, fieldNumber: 5)
    }()
    case .allcommitments?: try {
      guard case .allcommitments(let v)? = self.msg else { preconditionFailure() }
      try visitor.visitSingularMessageField(value: v, fieldNumber: 6)
    }()
    case .sharecovertcomponents?: try {
      guard case .sharecovertcomponents(let v)? = self.msg else { preconditionFailure() }
      try visitor.visitSingularMessageField(value: v, fieldNumber: 7)
    }()
    case .fusionresult?: try {
      guard case .fusionresult(let v)? = self.msg else { preconditionFailure() }
      try visitor.visitSingularMessageField(value: v, fieldNumber: 8)
    }()
    case .theirproofslist?: try {
      guard case .theirproofslist(let v)? = self.msg else { preconditionFailure() }
      try visitor.visitSingularMessageField(value: v, fieldNumber: 9)
    }()
    case .restartround?: try {
      guard case .restartround(let v)? = self.msg else { preconditionFailure() }
      try visitor.visitSingularMessageField(value: v, fieldNumber: 14)
    }()
    case .error?: try {
      guard case .error(let v)? = self.msg else { preconditionFailure() }
      try visitor.visitSingularMessageField(value: v, fieldNumber: 15)
    }()
    case nil: break
    }
    try unknownFields.traverse(visitor: &visitor)
  }

  static func ==(lhs: FusionServerMessage, rhs: FusionServerMessage) -> Bool {
    if lhs.msg != rhs.msg {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}

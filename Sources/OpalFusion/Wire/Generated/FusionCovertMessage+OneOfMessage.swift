// FusionCovertMessage+OneOfMessage.swift

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import SwiftProtobuf

extension FusionCovertMessage {
  enum OneOfMessage: Equatable, Sendable {
    case component(FusionCovertComponent)
    case signature(FusionCovertTransactionSignature)
    case ping(FusionPing)

    var isInitialized: Bool {
      // The use of inline closures is to circumvent an issue where the compiler
      // allocates stack space for every case branch when no optimizations are
      // enabled. https://github.com/apple/swift-protobuf/issues/1034
      switch self {
      case .component: return {
        guard case .component(let v) = self else { preconditionFailure() }
        return v.isInitialized
      }()
      case .signature: return {
        guard case .signature(let v) = self else { preconditionFailure() }
        return v.isInitialized
      }()
      default: return true
      }
    }

  }
}

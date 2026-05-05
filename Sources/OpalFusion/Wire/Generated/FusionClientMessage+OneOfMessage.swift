// FusionClientMessage+OneOfMessage.swift

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import SwiftProtobuf

extension FusionClientMessage {
  enum OneOfMessage: Equatable, Sendable {
    case clienthello(FusionClientHello)
    case joinpools(FusionJoinPools)
    case playercommit(FusionPlayerCommit)
    case myproofslist(FusionMyProofsList)
    case blames(FusionBlames)

    var isInitialized: Bool {
      // The use of inline closures is to circumvent an issue where the compiler
      // allocates stack space for every case branch when no optimizations are
      // enabled. https://github.com/apple/swift-protobuf/issues/1034
      switch self {
      case .clienthello: return {
        guard case .clienthello(let v) = self else { preconditionFailure() }
        return v.isInitialized
      }()
      case .joinpools: return {
        guard case .joinpools(let v) = self else { preconditionFailure() }
        return v.isInitialized
      }()
      case .playercommit: return {
        guard case .playercommit(let v) = self else { preconditionFailure() }
        return v.isInitialized
      }()
      case .myproofslist: return {
        guard case .myproofslist(let v) = self else { preconditionFailure() }
        return v.isInitialized
      }()
      case .blames: return {
        guard case .blames(let v) = self else { preconditionFailure() }
        return v.isInitialized
      }()
      }
    }

  }
}

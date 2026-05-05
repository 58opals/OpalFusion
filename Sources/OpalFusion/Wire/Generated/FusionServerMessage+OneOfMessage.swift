// FusionServerMessage+OneOfMessage.swift

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import SwiftProtobuf

extension FusionServerMessage {
  enum OneOfMessage: Equatable, Sendable {
    case serverhello(FusionServerHello)
    case tierstatusupdate(FusionTierStatusUpdate)
    case fusionbegin(FusionBeginMessage)
    case startround(FusionStartRound)
    case blindsigresponses(FusionBlindSignatureResponses)
    case allcommitments(FusionAllCommitments)
    case sharecovertcomponents(FusionShareCovertComponents)
    case fusionresult(FusionResultMessage)
    case theirproofslist(FusionTheirProofsList)
    case restartround(FusionRestartRound)
    case error(FusionError)

    var isInitialized: Bool {
      // The use of inline closures is to circumvent an issue where the compiler
      // allocates stack space for every case branch when no optimizations are
      // enabled. https://github.com/apple/swift-protobuf/issues/1034
      switch self {
      case .serverhello: return {
        guard case .serverhello(let v) = self else { preconditionFailure() }
        return v.isInitialized
      }()
      case .fusionbegin: return {
        guard case .fusionbegin(let v) = self else { preconditionFailure() }
        return v.isInitialized
      }()
      case .startround: return {
        guard case .startround(let v) = self else { preconditionFailure() }
        return v.isInitialized
      }()
      case .fusionresult: return {
        guard case .fusionresult(let v) = self else { preconditionFailure() }
        return v.isInitialized
      }()
      case .theirproofslist: return {
        guard case .theirproofslist(let v) = self else { preconditionFailure() }
        return v.isInitialized
      }()
      default: return true
      }
    }

  }
}

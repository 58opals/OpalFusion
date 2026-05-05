// FusionCovertResponse+OneOfMessage.swift

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import SwiftProtobuf

extension FusionCovertResponse {
  enum OneOfMessage: Equatable, Sendable {
    case ok(FusionAcknowledgement)
    case error(FusionError)

  }
}

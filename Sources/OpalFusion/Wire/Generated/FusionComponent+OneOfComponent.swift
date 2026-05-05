// FusionComponent+OneOfComponent.swift

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import SwiftProtobuf

extension FusionComponent {
  enum OneOfComponent: Equatable, Sendable {
    case input(FusionInputComponent)
    case output(FusionOutputComponent)
    case blank(FusionBlankComponent)

    var isInitialized: Bool {
      // The use of inline closures is to circumvent an issue where the compiler
      // allocates stack space for every case branch when no optimizations are
      // enabled. https://github.com/apple/swift-protobuf/issues/1034
      switch self {
      case .input: return {
        guard case .input(let v) = self else { preconditionFailure() }
        return v.isInitialized
      }()
      case .output: return {
        guard case .output(let v) = self else { preconditionFailure() }
        return v.isInitialized
      }()
      default: return true
      }
    }

  }
}

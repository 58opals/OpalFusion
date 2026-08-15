// OpalFusion+MosaicPrivateAlphaRuntime+PostManifestTerminalRecord.swift

#if os(macOS)
import Foundation

extension OpalFusion.MosaicPrivateAlphaRuntime {
    enum PostManifestTerminalRecord: Equatable, Sendable {
        case abort(
            binding: Binding,
            phase: OpalFusion.Mosaic.Attempt.Phase,
            event: PrivateDeploymentEvent,
            wasReceived: Bool
        )
        case completion(
            binding: Binding,
            event: PrivateDeploymentEvent
        )

        var binding: Binding {
            switch self {
            case let .abort(binding, _, _, _),
                 let .completion(binding, _):
                binding
            }
        }

        var event: PrivateDeploymentEvent {
            switch self {
            case let .abort(_, _, event, _),
                 let .completion(_, event):
                event
            }
        }

        var wasReceived: Bool {
            switch self {
            case let .abort(_, _, _, wasReceived): wasReceived
            case .completion: true
            }
        }
    }
}
#endif

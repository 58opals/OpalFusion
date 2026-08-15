// OpalFusion+MosaicPrivateAlphaRuntime+PrivateDeploymentPublicationRecoveryState.swift

#if os(macOS)
import Foundation

extension OpalFusion.MosaicPrivateAlphaRuntime {
    enum PrivateDeploymentPublicationRecoveryState: Equatable, Sendable {
        case none
        case formation(
            event: PrivateDeploymentEvent,
            relayEndpointIdentifiers: [String]
        )
        case terminal(
            reason: TerminalReason,
            event: PrivateDeploymentEvent,
            relayEndpointIdentifiers: [String],
            exactEvidenceBytes: Data
        )
    }
}
#endif

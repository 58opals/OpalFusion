// OpalFusion+MosaicPrivateAlphaRuntime+ManifestRecoveryState.swift

#if os(macOS)
import Foundation

extension OpalFusion.MosaicPrivateAlphaRuntime {
    enum ManifestRecoveryState: Equatable, Sendable {
        case forming
        case validated(
            privateManifestProposalBytes: Data,
            completeManifestBytes: Data
        )
    }
}
#endif

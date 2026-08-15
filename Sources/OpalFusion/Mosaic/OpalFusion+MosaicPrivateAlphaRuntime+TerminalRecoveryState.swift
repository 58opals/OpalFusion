// OpalFusion+MosaicPrivateAlphaRuntime+TerminalRecoveryState.swift

#if os(macOS)
import Foundation

extension OpalFusion.MosaicPrivateAlphaRuntime {
    enum TerminalRecoveryState: Equatable, Sendable {
        case active
        case authorized(
            TerminalReason,
            exactEvidenceBytes: Data
        )
    }
}
#endif

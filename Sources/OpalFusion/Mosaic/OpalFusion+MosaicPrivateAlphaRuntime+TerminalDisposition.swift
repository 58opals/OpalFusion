// OpalFusion+MosaicPrivateAlphaRuntime+TerminalDisposition.swift

#if os(macOS)
import Foundation

extension OpalFusion.MosaicPrivateAlphaRuntime {
    @_spi(MosaicPrivateAlpha)
    public enum TerminalDisposition: Equatable, Sendable {
        case cleanupAuthorized(
            TerminalReason,
            evidenceIdentifier: Data,
            recoveryRevision: UInt64
        )
    }
}
#endif

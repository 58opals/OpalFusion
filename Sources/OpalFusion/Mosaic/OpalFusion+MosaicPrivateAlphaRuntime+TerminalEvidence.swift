// OpalFusion+MosaicPrivateAlphaRuntime+TerminalEvidence.swift

#if os(macOS)
import Foundation

extension OpalFusion.MosaicPrivateAlphaRuntime {
    /// One-use exact Fusion protocol-terminal evidence minted by the sole terminal owner.
    ///
    /// This proves only signed protocol terminal authority plus canonical, drained Fusion
    /// admission and publication state. OpalBase separately proves wallet and chain disposition;
    /// the app's atomic outer owner must combine both before physically deleting material.
    @_spi(MosaicPrivateAlpha)
    public struct TerminalEvidence: ~Copyable, Sendable {
        @_spi(MosaicPrivateAlpha) public let binding: Binding
        @_spi(MosaicPrivateAlpha) public let evidenceIdentifier: Data
        @_spi(MosaicPrivateAlpha) public let recoveryRevision: UInt64
        @_spi(MosaicPrivateAlpha) public let recoverySnapshotDigest: Data

        init(
            binding: Binding,
            evidenceIdentifier: Data,
            recoveryRevision: UInt64,
            recoverySnapshotDigest: Data
        ) {
            self.binding = binding
            self.evidenceIdentifier = evidenceIdentifier
            self.recoveryRevision = recoveryRevision
            self.recoverySnapshotDigest = recoverySnapshotDigest
        }
    }
}
#endif

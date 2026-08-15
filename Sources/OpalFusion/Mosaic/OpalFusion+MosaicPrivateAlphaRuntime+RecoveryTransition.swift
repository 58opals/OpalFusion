// OpalFusion+MosaicPrivateAlphaRuntime+RecoveryTransition.swift

#if os(macOS)
import Foundation

extension OpalFusion.MosaicPrivateAlphaRuntime {
    /// Exact package-field replacement for the app's atomically replaced outer attempt record.
    @_spi(MosaicPrivateAlpha)
    public struct RecoveryTransition: Equatable, Sendable {
        @_spi(MosaicPrivateAlpha) public let binding: Binding
        @_spi(MosaicPrivateAlpha) public let expectedSnapshot: Data?
        @_spi(MosaicPrivateAlpha) public let replacementSnapshot: Data
        @_spi(MosaicPrivateAlpha) public let replacementDigest: Data
        @_spi(MosaicPrivateAlpha) public let replacementRevision: UInt64
        @_spi(MosaicPrivateAlpha) public let transitionIdentifier: Data

        init(
            binding: Binding,
            expectedSnapshot: Data?,
            replacementSnapshot: Data,
            replacementDigest: Data,
            replacementRevision: UInt64,
            transitionIdentifier: Data
        ) {
            self.binding = binding
            self.expectedSnapshot = expectedSnapshot
            self.replacementSnapshot = replacementSnapshot
            self.replacementDigest = replacementDigest
            self.replacementRevision = replacementRevision
            self.transitionIdentifier = transitionIdentifier
        }
    }
}
#endif

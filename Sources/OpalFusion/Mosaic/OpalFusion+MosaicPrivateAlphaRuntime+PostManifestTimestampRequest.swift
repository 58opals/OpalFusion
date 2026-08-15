// OpalFusion+MosaicPrivateAlphaRuntime+PostManifestTimestampRequest.swift

#if os(macOS)
import Foundation

extension OpalFusion.MosaicPrivateAlphaRuntime {
    /// Package-derived timing request for one exact signed post-manifest envelope.
    @_spi(MosaicPrivateAlpha)
    public struct PostManifestTimestampRequest: Sendable, Equatable {
        @_spi(MosaicPrivateAlpha) public let recipientEventIdentity: Data?
        @_spi(MosaicPrivateAlpha) public let phase: Phase
        @_spi(MosaicPrivateAlpha) public let sequence: UInt64
        @_spi(MosaicPrivateAlpha) public let expiryUnixSeconds: UInt64

        init(
            recipientEventIdentity: Data?,
            phase: Phase,
            sequence: UInt64,
            expiryUnixSeconds: UInt64
        ) {
            self.recipientEventIdentity = recipientEventIdentity
            self.phase = phase
            self.sequence = sequence
            self.expiryUnixSeconds = expiryUnixSeconds
        }
    }
}
#endif

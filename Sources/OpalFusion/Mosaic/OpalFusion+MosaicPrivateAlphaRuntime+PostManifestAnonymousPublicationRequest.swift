// OpalFusion+MosaicPrivateAlphaRuntime+PostManifestAnonymousPublicationRequest.swift

#if os(macOS)
import Foundation

extension OpalFusion.MosaicPrivateAlphaRuntime {
    /// Package-derived scheduling request for an already-bound anonymous publication.
    @_spi(MosaicPrivateAlpha)
    public struct PostManifestAnonymousPublicationRequest:
        Sendable,
        Equatable {
        @_spi(MosaicPrivateAlpha) public let kind:
            PostManifestPublicationKind
        @_spi(MosaicPrivateAlpha) public let recipientEventIdentity: Data

        init(
            kind: PostManifestPublicationKind,
            recipientEventIdentity: Data
        ) {
            self.kind = kind
            self.recipientEventIdentity = recipientEventIdentity
        }
    }
}
#endif

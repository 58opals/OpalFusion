// OpalFusion+MosaicPrivateAlphaRuntime+PostManifestRelayCapabilities.swift

#if os(macOS)
import Foundation

extension OpalFusion.MosaicPrivateAlphaRuntime {
    /// App-owned Tor route capabilities bound by Fusion to the manifest's exact relay set.
    @_spi(MosaicPrivateAlpha)
    public struct PostManifestRelayCapabilities: Sendable {
        static let maximumAllowedSubscriptionIdentifierByteCount = 256
        static let maximumAllowedPendingCount = 4_096

        let provisionRoutes: @Sendable ([PostManifestRouteRequest]) async throws
            -> [PostManifestProvisionedRouteGroup]
        let makeSubscriptionIdentifier: @Sendable (
            PostManifestRouteRequest,
            String
        ) throws -> String
        let awaitAnonymousPublicationPermit: @Sendable (
            PostManifestAnonymousPublicationRequest
        ) async throws -> Void
        let maximumSubscriptionIdentifierByteCount: Int
        let maximumPendingEventCount: Int
        let maximumPendingRelayOutputCount: Int

        @_spi(MosaicPrivateAlpha)
        public init(
            provisionRoutes: @escaping @Sendable (
                [PostManifestRouteRequest]
            ) async throws -> [PostManifestProvisionedRouteGroup],
            makeSubscriptionIdentifier: @escaping @Sendable (
                PostManifestRouteRequest,
                String
            ) throws -> String,
            awaitAnonymousPublicationPermit: @escaping @Sendable (
                PostManifestAnonymousPublicationRequest
            ) async throws -> Void = { _ in },
            maximumSubscriptionIdentifierByteCount: Int,
            maximumPendingEventCount: Int = 256,
            maximumPendingRelayOutputCount: Int = 64
        ) {
            self.provisionRoutes = provisionRoutes
            self.makeSubscriptionIdentifier = makeSubscriptionIdentifier
            self.awaitAnonymousPublicationPermit =
                awaitAnonymousPublicationPermit
            self.maximumSubscriptionIdentifierByteCount =
                maximumSubscriptionIdentifierByteCount
            self.maximumPendingEventCount = maximumPendingEventCount
            self.maximumPendingRelayOutputCount =
                maximumPendingRelayOutputCount
        }

        func validateResourceLimits() throws {
            guard (1 ... Self.maximumAllowedSubscriptionIdentifierByteCount)
                    .contains(maximumSubscriptionIdentifierByteCount),
                  (1 ... Self.maximumAllowedPendingCount)
                    .contains(maximumPendingEventCount),
                  (1 ... Self.maximumAllowedPendingCount)
                    .contains(maximumPendingRelayOutputCount) else {
                throw Failure.invalidStateTransition
            }
        }
    }
}
#endif

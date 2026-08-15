// OpalFusion+MosaicPrivateAlphaRuntime+Creation.swift

#if os(macOS)
import Foundation

extension OpalFusion.MosaicPrivateAlphaRuntime {
    /// Creates one move-only fresh attempt bound to the frozen private-deployment epoch policy.
    @_spi(MosaicPrivateAlpha)
    public static func createFreshAttempt(
        boundTo binding: Binding,
        discoveryEpochStartUnixSeconds: UInt64
    ) throws -> FreshAttempt {
        do {
            _ = try OpalFusion.Mosaic.OpalMainnetAlpha.PrivateDeploymentPolicy
                .frozen.preManifestDeadlines(
                    forEpochStartingAt: discoveryEpochStartUnixSeconds
                )
        } catch {
            throw Failure.invalidDiscoveryEpoch
        }
        return .init(
            state: .initial(
                binding: binding,
                discoveryEpochStartUnixSeconds:
                    discoveryEpochStartUnixSeconds
            )
        )
    }

    /// Decodes one complete canonical snapshot and consumes it only as loaded recovery.
    @_spi(MosaicPrivateAlpha)
    public static func loadRecovery(
        from canonicalSnapshot: Data,
        expectedBinding: Binding
    ) throws -> LoadedRecovery {
        .init(
            state: try .decode(
                from: canonicalSnapshot,
                expectedBinding: expectedBinding
            )
        )
    }
}
#endif

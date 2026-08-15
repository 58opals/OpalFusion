// OpalFusion+MosaicPrivateAlphaRuntime+PostManifestPublicationPersistence.swift

#if os(macOS)
import Foundation

extension OpalFusion.MosaicPrivateAlphaRuntime {
    /// Atomic app-owned storage for Fusion's canonical outbound publication journal.
    @_spi(MosaicPrivateAlpha)
    public struct PostManifestPublicationPersistence: Sendable {
        let load: @Sendable (Binding) throws -> Data?
        let compareAndSwap: @Sendable (
            Binding,
            Data?,
            Data
        ) throws -> Data

        @_spi(MosaicPrivateAlpha)
        public init(
            load: @escaping @Sendable (Binding) throws -> Data?,
            compareAndSwap: @escaping @Sendable (
                Binding,
                Data?,
                Data
            ) throws -> Data
        ) {
            self.load = load
            self.compareAndSwap = compareAndSwap
        }
    }
}
#endif

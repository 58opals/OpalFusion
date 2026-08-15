// OpalFusion+MosaicPrivateAlphaRuntime+LoadedRecovery.swift

#if os(macOS)
extension OpalFusion.MosaicPrivateAlphaRuntime {
    /// One-use ownership of a complete, canonical, binding-validated recovery snapshot.
    @_spi(MosaicPrivateAlpha)
    public struct LoadedRecovery: ~Copyable, Sendable {
        let state: RecoveryState

        @_spi(MosaicPrivateAlpha)
        public var binding: Binding { state.binding }

        init(state: RecoveryState) {
            self.state = state
        }
    }
}
#endif

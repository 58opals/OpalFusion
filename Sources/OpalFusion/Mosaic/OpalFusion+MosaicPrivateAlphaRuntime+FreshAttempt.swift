// OpalFusion+MosaicPrivateAlphaRuntime+FreshAttempt.swift

#if os(macOS)
extension OpalFusion.MosaicPrivateAlphaRuntime {
    /// One-use ownership of a fresh attempt before its initial snapshot is durably installed.
    @_spi(MosaicPrivateAlpha)
    public struct FreshAttempt: ~Copyable, Sendable {
        let state: RecoveryState

        @_spi(MosaicPrivateAlpha)
        public var binding: Binding { state.binding }

        init(state: RecoveryState) {
            self.state = state
        }
    }
}
#endif

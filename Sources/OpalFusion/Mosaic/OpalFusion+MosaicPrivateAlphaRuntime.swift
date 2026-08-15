// OpalFusion+MosaicPrivateAlphaRuntime.swift

#if os(macOS)
extension OpalFusion {
    /// Private composition and recovery boundary for the frozen mainnet-alpha proposal.
    ///
    /// This SPI does not enable the generic public Mosaic runtime. The application retains
    /// ownership of atomic outer persistence, keys, scheduling, transport capabilities, and
    /// physical deletion.
    @_spi(MosaicPrivateAlpha)
    public enum MosaicPrivateAlphaRuntime {}
}
#endif

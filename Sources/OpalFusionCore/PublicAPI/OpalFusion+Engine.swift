// OpalFusion+Engine.swift

public extension OpalFusion {
    /// A protocol engine available beneath the Opal Fusion facade.
    enum Engine: CaseIterable, Sendable, Hashable {
        /// The coordinator-based Electron Cash compatibility protocol.
        case cashFusion
        /// The draft peer-conducted Mosaic protocol.
        case mosaic
    }
}

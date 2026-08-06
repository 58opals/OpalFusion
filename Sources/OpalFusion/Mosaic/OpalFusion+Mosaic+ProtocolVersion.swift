// OpalFusion+Mosaic+ProtocolVersion.swift

public extension OpalFusion.Mosaic {
    /// A Mosaic protocol identity.
    enum ProtocolVersion: String, CaseIterable, Sendable {
        /// The non-interoperability draft described by the repository specification.
        case draft1 = "Mosaic/1-draft.1"
    }
}

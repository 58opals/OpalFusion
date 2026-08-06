// OpalFusion+Mosaic+LocalAttempt+GenerationIdentifier.swift

extension OpalFusion.Mosaic.LocalAttempt {
    /// An opaque local generation guard for one attempt instance.
    struct GenerationIdentifier: Sendable, Hashable {
        let opaqueBytes: [UInt8]

        init(opaqueBytes: [UInt8]) {
            self.opaqueBytes = opaqueBytes
        }
    }
}

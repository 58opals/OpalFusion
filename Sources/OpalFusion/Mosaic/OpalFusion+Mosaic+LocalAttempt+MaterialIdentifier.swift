// OpalFusion+Mosaic+LocalAttempt+MaterialIdentifier.swift

extension OpalFusion.Mosaic.LocalAttempt {
    /// An opaque identity for the local peer's attempt-scoped wallet and protocol material.
    struct MaterialIdentifier: Sendable, Hashable {
        let opaqueBytes: [UInt8]

        init(opaqueBytes: [UInt8]) {
            self.opaqueBytes = opaqueBytes
        }
    }
}

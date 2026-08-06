// OpalFusion+Mosaic+LocalAttempt+AttemptIdentifier.swift

extension OpalFusion.Mosaic.LocalAttempt {
    /// An opaque identifier for one semantic attempt instance.
    ///
    /// Canonicalization and wire layers own validation of the represented identifier.
    struct AttemptIdentifier: Sendable, Hashable {
        let validatedBytes: [UInt8]

        init(validatedBytes: [UInt8]) {
            self.validatedBytes = validatedBytes
        }
    }
}

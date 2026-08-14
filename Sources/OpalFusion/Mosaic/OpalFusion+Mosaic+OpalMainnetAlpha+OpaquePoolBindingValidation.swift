// OpalFusion+Mosaic+OpalMainnetAlpha+OpaquePoolBindingValidation.swift

extension OpalFusion.Mosaic.OpalMainnetAlpha {
    /// Proof that a canonical pool document supplies one expected opaque identifier.
    struct OpaquePoolBindingValidation: Sendable, Equatable {
        enum ValidationError: Error, Sendable, Equatable {
            case identifierMismatch
        }

        let document: OpaquePoolDocument

        init(
            validating document: OpaquePoolDocument,
            expectedOpaqueIdentifier: [UInt8]
        ) throws(ValidationError) {
            guard document.opaqueIdentifier == expectedOpaqueIdentifier else {
                throw .identifierMismatch
            }
            self.document = document
        }
    }
}

// OpalFusion+Mosaic+Attempt+ManifestBinding.swift

extension OpalFusion.Mosaic.Attempt {
    /// The two distinct manifest identities established by an upstream canonical-document seam.
    ///
    /// Control identities sign `roundIdentifier`, which identifies the manifest core. The
    /// transcript commits to `manifestDigest`, which identifies the complete signed manifest.
    /// This semantic type deliberately does not define the still-unresolved manifest wire schema.
    struct ManifestBinding: Sendable, Hashable {
        enum ValidationError: Error, Sendable, Equatable {
            case invalidRoundIdentifierByteCount(actual: Int)
            case invalidManifestDigestByteCount(actual: Int)
        }

        let roundIdentifier: [UInt8]
        let manifestDigest: [UInt8]

        init(
            validatedRoundIdentifier: [UInt8],
            validatedManifestDigest: [UInt8]
        ) throws {
            guard validatedRoundIdentifier.count == 32 else {
                throw ValidationError.invalidRoundIdentifierByteCount(
                    actual: validatedRoundIdentifier.count
                )
            }
            guard validatedManifestDigest.count == 32 else {
                throw ValidationError.invalidManifestDigestByteCount(
                    actual: validatedManifestDigest.count
                )
            }

            self.roundIdentifier = Array(validatedRoundIdentifier)
            self.manifestDigest = Array(validatedManifestDigest)
        }
    }

    /// One control signature that an upstream cryptographic seam validated over a round identifier.
    ///
    /// The seam must also prove that the signature belongs to the complete manifest represented by
    /// `binding.manifestDigest`; this value only carries that already-validated semantic result.
    struct ManifestSignatureValidation: Sendable, Equatable {
        let signer: ControlIdentity
        let binding: ManifestBinding

        init(
            signer: ControlIdentity,
            binding: ManifestBinding
        ) {
            self.signer = signer
            self.binding = binding
        }
    }
}

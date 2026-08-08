// OpalFusion+Mosaic+Attempt+ManifestBinding.swift

extension OpalFusion.Mosaic.Attempt {
    /// The two distinct manifest identities established by an upstream canonical-document seam.
    ///
    /// Control identities sign `roundIdentifier`, which identifies the manifest core. A future
    /// canonical-document seam must derive `manifestDigest` from the complete signed manifest
    /// before the transcript commits to it. This type validates width and semantic agreement only.
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
}

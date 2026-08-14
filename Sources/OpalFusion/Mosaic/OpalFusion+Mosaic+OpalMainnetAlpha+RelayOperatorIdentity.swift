// OpalFusion+Mosaic+OpalMainnetAlpha+RelayOperatorIdentity.swift

extension OpalFusion.Mosaic.OpalMainnetAlpha {
    /// Canonical app-reviewed registry identity used for configured relay diversity.
    ///
    /// Distinct labels assert only that the application configured three registry entries. They
    /// do not cryptographically prove corporate, jurisdictional, infrastructure, network-path, or
    /// Tor-circuit independence. The application owns that review before supplying each label.
    struct RelayOperatorIdentity: Sendable, Hashable {
        enum ValidationError: Error, Sendable, Equatable {
            case emptyRegistryLabel
            case registryLabelTooLong(actual: Int)
            case nonPrintableASCIIRegistryLabel
            case surroundingWhitespace
            case invalidCanonicalDigestByteCount(actual: Int)
        }

        static let maximumRegistryLabelByteCount = 128

        let canonicalDigest: [UInt8]

        init(appReviewedRegistryLabel: String) throws(ValidationError) {
            let labelBytes = Array(appReviewedRegistryLabel.utf8)
            guard !labelBytes.isEmpty else { throw .emptyRegistryLabel }
            guard labelBytes.count <= Self.maximumRegistryLabelByteCount else {
                throw .registryLabelTooLong(actual: labelBytes.count)
            }
            guard labelBytes.allSatisfy({ (0x20 ... 0x7E).contains($0) }) else {
                throw .nonPrintableASCIIRegistryLabel
            }
            guard labelBytes.first != 0x20, labelBytes.last != 0x20 else {
                throw .surroundingWhitespace
            }
            let normalizedBytes = labelBytes.map { byte in
                (0x41 ... 0x5A).contains(byte) ? byte + 0x20 : byte
            }
            canonicalDigest = RoleSeedValidator.hash(
                domainSuffix: "private-deployment/relay-operator-registry-label",
                fields: [
                    PrivateDeploymentNostrSelector.identifierBytes,
                    normalizedBytes,
                ]
            )
        }

        init(decodedCanonicalDigest: [UInt8]) throws(ValidationError) {
            guard decodedCanonicalDigest.count == 32 else {
                throw .invalidCanonicalDigestByteCount(
                    actual: decodedCanonicalDigest.count
                )
            }
            canonicalDigest = Array(decodedCanonicalDigest)
        }
    }
}

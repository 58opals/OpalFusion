// OpalFusion+Mosaic+OpalMainnetAlpha+OpaquePoolDocument.swift

extension OpalFusion.Mosaic.OpalMainnetAlpha {
    /// Canonical non-wallet-identifying pool selection for one private deployment.
    ///
    /// The application must generate a fresh, deployment-scoped 32-byte identifier independently
    /// of wallet keys, amounts, outpoints, addresses, and reusable wallet identifiers. It must also
    /// prevent reuse across concurrently active discovery contexts; those facts are not inferable
    /// from the opaque bytes and remain caller-owned preconditions.
    struct OpaquePoolDocument: Sendable, Equatable {
        enum ValidationError: Error, Sendable, Equatable {
            case invalidSelector
            case invalidProtocolIdentifier
            case invalidNetworkGenesisHash
            case invalidOpaqueIdentifierByteCount(actual: Int)
        }

        let opaqueIdentifier: [UInt8]

        var canonicalBytes: [UInt8] {
            var encoder = OpalFusion.Mosaic.CanonicalEncoder()
            do {
                try encoder.writeText(PrivateDeploymentNostrSelector.identifier)
                try encoder.writeText(OpalFusion.Mosaic.Profile.opalMainnetAlpha.rawValue)
                try encoder.writeFixedBytes(
                    OpalFusion.Mosaic.OpalMainnetAlpha.mainnetGenesisHash,
                    byteCount: 32
                )
                try encoder.writeFixedBytes(
                    opaqueIdentifier,
                    byteCount: OpalFusion.Mosaic.OpalMainnetAlpha
                        .opaquePoolIdentifierByteCount
                )
                return encoder.encodedBytes
            } catch {
                preconditionFailure("A validated opaque pool document must encode.")
            }
        }

        var digest: [UInt8] {
            RoleSeedValidator.hash(
                domainSuffix: "private-deployment/opaque-pool",
                fields: [
                    PrivateDeploymentNostrSelector.identifierBytes,
                    canonicalBytes,
                ]
            )
        }

        init(appGeneratedOpaqueIdentifier opaqueIdentifier: [UInt8]) throws(ValidationError) {
            guard opaqueIdentifier.count
                    == OpalFusion.Mosaic.OpalMainnetAlpha
                        .opaquePoolIdentifierByteCount else {
                throw .invalidOpaqueIdentifierByteCount(
                    actual: opaqueIdentifier.count
                )
            }
            self.opaqueIdentifier = Array(opaqueIdentifier)
        }

        static func decode(
            from encodedBytes: [UInt8]
        ) throws -> Self {
            try OpalFusion.Mosaic.CanonicalDecoder.decode(
                from: encodedBytes
            ) { decoder in
                guard try decoder.readText()
                        == PrivateDeploymentNostrSelector.identifier else {
                    throw ValidationError.invalidSelector
                }
                let protocolIdentifier = try decoder.readText()
                guard protocolIdentifier
                        == OpalFusion.Mosaic.Profile.opalMainnetAlpha.rawValue else {
                    throw ValidationError.invalidProtocolIdentifier
                }
                let genesisHash = try decoder.readFixedBytes(byteCount: 32)
                guard genesisHash
                        == OpalFusion.Mosaic.OpalMainnetAlpha.mainnetGenesisHash else {
                    throw ValidationError.invalidNetworkGenesisHash
                }
                return try .init(
                    appGeneratedOpaqueIdentifier: decoder.readFixedBytes(
                        byteCount: OpalFusion.Mosaic.OpalMainnetAlpha
                            .opaquePoolIdentifierByteCount
                    )
                )
            }
        }
    }
}

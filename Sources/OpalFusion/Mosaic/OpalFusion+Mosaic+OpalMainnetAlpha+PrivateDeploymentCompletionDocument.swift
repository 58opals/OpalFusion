// OpalFusion+Mosaic+OpalMainnetAlpha+PrivateDeploymentCompletionDocument.swift

extension OpalFusion.Mosaic.OpalMainnetAlpha {
    /// Canonical completion notice bound to one already validated complete transaction payload.
    struct PrivateDeploymentCompletionDocument: Sendable, Equatable {
        enum ValidationError: Error, Sendable, Equatable {
            case invalidSelector
            case invalidProtocolIdentifier
            case invalidNetworkGenesisHash
            case invalidDiscoveryEpoch
            case roundIdentifierMismatch
            case manifestRoundMismatch
            case completeTransactionDigestMismatch
        }

        let discoveryEpochStartUnixSeconds: UInt64
        let roundIdentifier: [UInt8]
        let completeTransactionDigest: [UInt8]

        var canonicalBytes: [UInt8] {
            var encoder = OpalFusion.Mosaic.CanonicalEncoder()
            do {
                try encoder.writeText(PrivateDeploymentNostrSelector.identifier)
                try encoder.writeText(
                    OpalFusion.Mosaic.Profile.opalMainnetAlpha.rawValue
                )
                try encoder.writeFixedBytes(
                    OpalFusion.Mosaic.OpalMainnetAlpha.mainnetGenesisHash,
                    byteCount: 32
                )
                encoder.writeUInt64(discoveryEpochStartUnixSeconds)
                try encoder.writeFixedBytes(roundIdentifier, byteCount: 32)
                try encoder.writeFixedBytes(
                    completeTransactionDigest,
                    byteCount: 32
                )
                return encoder.encodedBytes
            } catch {
                preconditionFailure("A validated private-deployment completion must encode.")
            }
        }

        init(validation: PrivateDeploymentCompletionValidation) {
            discoveryEpochStartUnixSeconds =
                validation.manifest.discoveryEpochStartUnixSeconds
            roundIdentifier = validation.roundManifest.core.roundIdentifier
            completeTransactionDigest = validation.completedPayload.digest
        }

        static func decode(
            from encodedBytes: [UInt8],
            validation: PrivateDeploymentCompletionValidation
        ) throws -> Self {
            try OpalFusion.Mosaic.CanonicalDecoder.decode(
                from: encodedBytes
            ) { decoder in
                guard try decoder.readText()
                        == PrivateDeploymentNostrSelector.identifier else {
                    throw ValidationError.invalidSelector
                }
                guard try decoder.readText()
                        == OpalFusion.Mosaic.Profile.opalMainnetAlpha.rawValue else {
                    throw ValidationError.invalidProtocolIdentifier
                }
                guard try decoder.readFixedBytes(byteCount: 32)
                        == OpalFusion.Mosaic.OpalMainnetAlpha.mainnetGenesisHash else {
                    throw ValidationError.invalidNetworkGenesisHash
                }
                let epochStart = try decoder.readUInt64()
                guard epochStart
                        == validation.manifest
                            .discoveryEpochStartUnixSeconds else {
                    throw ValidationError.invalidDiscoveryEpoch
                }
                let roundIdentifier = try decoder.readFixedBytes(byteCount: 32)
                guard roundIdentifier
                        == validation.completedPayload.roundIdentifier else {
                    throw ValidationError.roundIdentifierMismatch
                }
                guard roundIdentifier
                        == validation.roundManifest.core.roundIdentifier else {
                    throw ValidationError.manifestRoundMismatch
                }
                let transactionDigest = try decoder.readFixedBytes(byteCount: 32)
                guard transactionDigest
                        == validation.completedPayload.digest else {
                    throw ValidationError.completeTransactionDigestMismatch
                }
                return .init(validation: validation)
            }
        }
    }
}

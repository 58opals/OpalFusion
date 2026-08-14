// OpalFusion+Mosaic+OpalMainnetAlpha+PrivateDeploymentAbortContext.swift

extension OpalFusion.Mosaic.OpalMainnetAlpha {
    /// Exact latest-agreed context to which a terminal abort applies.
    struct PrivateDeploymentAbortContext: Sendable, Equatable {
        enum Kind: UInt8, Sendable, Equatable {
            case discovery = 0
            case candidateSet = 1
            case controlRoster = 2
            case manifest = 3
        }

        enum ValidationError: Error, Sendable, Equatable {
            case invalidSelector
            case invalidDiscoveryEpoch
            case unknownKind(UInt8)
        }

        let kind: Kind
        let digest: [UInt8]

        var canonicalBytes: [UInt8] {
            var encoder = OpalFusion.Mosaic.CanonicalEncoder()
            do {
                try encoder.writeText(PrivateDeploymentNostrSelector.identifier)
                encoder.writeUInt8(kind.rawValue)
                try encoder.writeFixedBytes(digest, byteCount: 32)
            } catch {
                preconditionFailure("A validated abort context must encode.")
            }
            return encoder.encodedBytes
        }

        static func makeDiscoveryContext(
            discoveryEpochStartUnixSeconds: UInt64,
            opaquePool: OpaquePoolDocument,
            relaySet: RelaySetDocument
        ) throws(ValidationError) -> Self {
            do {
                try PrivateDeploymentPolicy.frozen.validate(
                    epochStart: discoveryEpochStartUnixSeconds
                )
            } catch {
                throw .invalidDiscoveryEpoch
            }
            var encoder = OpalFusion.Mosaic.CanonicalEncoder()
            encoder.writeUInt64(discoveryEpochStartUnixSeconds)
            do {
                try encoder.writeFixedBytes(opaquePool.digest, byteCount: 32)
                try encoder.writeFixedBytes(relaySet.digest, byteCount: 32)
            } catch {
                preconditionFailure("Validated discovery documents have fixed digests.")
            }
            return .init(
                kind: .discovery,
                digest: RoleSeedValidator.hash(
                    domainSuffix: "private-deployment/discovery-context",
                    fields: [
                        PrivateDeploymentNostrSelector.identifierBytes,
                        encoder.encodedBytes,
                    ]
                )
            )
        }

        static func makeCandidateSetContext(
            _ selection: CandidateSelectionValidation
        ) -> Self {
            .init(kind: .candidateSet, digest: selection.candidateSetDigest)
        }

        static func makeControlRosterContext(
            _ validation: ControlRosterValidation
        ) -> Self {
            .init(kind: .controlRoster, digest: validation.controlRosterDigest)
        }

        static func makeControlRosterContext(
            _ binding: OpalFusion.Mosaic.Attempt.ControlRosterBinding
        ) -> Self {
            .init(kind: .controlRoster, digest: binding.controlRosterDigest)
        }

        static func makeManifestContext(
            _ binding: OpalFusion.Mosaic.Attempt.ManifestBinding
        ) -> Self {
            .init(
                kind: .manifest,
                digest: RoleSeedValidator.hash(
                    domainSuffix: "private-deployment/manifest-context",
                    fields: [
                        PrivateDeploymentNostrSelector.identifierBytes,
                        binding.roundIdentifier,
                        binding.manifestDigest,
                    ]
                )
            )
        }

        static func decode(from encodedBytes: [UInt8]) throws -> Self {
            try OpalFusion.Mosaic.CanonicalDecoder.decode(
                from: encodedBytes
            ) { decoder in
                guard try decoder.readText()
                        == PrivateDeploymentNostrSelector.identifier else {
                    throw ValidationError.invalidSelector
                }
                let rawKind = try decoder.readUInt8()
                guard let kind = Kind(rawValue: rawKind) else {
                    throw ValidationError.unknownKind(rawKind)
                }
                return .init(
                    kind: kind,
                    digest: try decoder.readFixedBytes(byteCount: 32)
                )
            }
        }

        private init(
            kind: Kind,
            digest: [UInt8]
        ) {
            precondition(digest.count == 32, "Abort context digests are fixed-width.")
            self.kind = kind
            self.digest = Array(digest)
        }
    }
}

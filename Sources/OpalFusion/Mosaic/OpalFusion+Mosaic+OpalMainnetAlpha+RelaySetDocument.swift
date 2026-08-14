// OpalFusion+Mosaic+OpalMainnetAlpha+RelaySetDocument.swift

extension OpalFusion.Mosaic.OpalMainnetAlpha {
    /// Canonical exact-three relay selection with distinct endpoint and operator identities.
    struct RelaySetDocument: Sendable, Equatable {
        enum ValidationError: Error, Sendable, Equatable {
            case invalidSelector
            case invalidProtocolIdentifier
            case invalidNetworkGenesisHash
            case invalidRelayCount(actual: Int)
            case duplicateEndpoint(PrivateRelayEndpoint)
            case duplicateOperator(RelayOperatorIdentity)
            case manifestDigestMismatch
        }

        let registrations: [RelayRegistrationDocument]

        var canonicalBytes: [UInt8] {
            var encoder = OpalFusion.Mosaic.CanonicalEncoder()
            do {
                try encoder.writeText(PrivateDeploymentNostrSelector.identifier)
                try encoder.writeText(OpalFusion.Mosaic.Profile.opalMainnetAlpha.rawValue)
                try encoder.writeFixedBytes(
                    OpalFusion.Mosaic.OpalMainnetAlpha.mainnetGenesisHash,
                    byteCount: 32
                )
                try encoder.writeVector(registrations) { encoder, registration in
                    try encoder.writeBytes(registration.canonicalBytes)
                }
                return encoder.encodedBytes
            } catch {
                preconditionFailure("A validated relay set must encode.")
            }
        }

        var digest: [UInt8] {
            RoleSeedValidator.hash(
                domainSuffix: "private-deployment/relay-set",
                fields: [
                    PrivateDeploymentNostrSelector.identifierBytes,
                    canonicalBytes,
                ]
            )
        }

        init(
            registrations: [RelayRegistrationDocument]
        ) throws(ValidationError) {
            guard registrations.count
                    == OpalFusion.Mosaic.OpalMainnetAlpha.relayCount else {
                throw .invalidRelayCount(actual: registrations.count)
            }
            var endpoints: Set<PrivateRelayEndpoint> = []
            var operators: Set<RelayOperatorIdentity> = []
            for registration in registrations {
                guard endpoints.insert(registration.endpoint).inserted else {
                    throw .duplicateEndpoint(registration.endpoint)
                }
                guard operators.insert(registration.operatorIdentity).inserted else {
                    throw .duplicateOperator(registration.operatorIdentity)
                }
            }
            self.registrations = registrations.sorted {
                $0.canonicalBytes.lexicographicallyPrecedes($1.canonicalBytes)
            }
        }

        func validate(manifestRelaySetDigest: [UInt8]) throws(ValidationError) {
            guard digest == manifestRelaySetDigest else {
                throw .manifestDigestMismatch
            }
        }

        static func decode(from encodedBytes: [UInt8]) throws -> Self {
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
                let registrations = try decoder.readVector { decoder in
                    try RelayRegistrationDocument.decode(
                        from: decoder.readBytes()
                    )
                }
                let document = try Self(registrations: registrations)
                guard document.registrations == registrations else {
                    throw OpalFusion.Mosaic.CanonicalCodingError
                        .nonCanonicalSetOrdering
                }
                return document
            }
        }
    }
}

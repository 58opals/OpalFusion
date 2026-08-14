// OpalFusion+Mosaic+OpalMainnetAlpha+RelayRegistrationDocument.swift

extension OpalFusion.Mosaic.OpalMainnetAlpha {
    /// One canonical relay endpoint and its configured independent operator identity.
    struct RelayRegistrationDocument: Sendable, Equatable {
        enum ValidationError: Error, Sendable, Equatable {
            case invalidSelector
            case nip42AuthenticationRequired
            case proofOfWorkRequired
            case nonCanonicalEndpoint
        }

        let endpoint: PrivateRelayEndpoint
        let operatorIdentity: RelayOperatorIdentity

        var requiresNIP42Authentication: Bool { false }
        var requiresProofOfWork: Bool { false }

        var canonicalBytes: [UInt8] {
            var encoder = OpalFusion.Mosaic.CanonicalEncoder()
            do {
                try encoder.writeText(PrivateDeploymentNostrSelector.identifier)
                try encoder.writeText(endpoint.normalizedURL)
                try encoder.writeFixedBytes(
                    operatorIdentity.canonicalDigest,
                    byteCount: 32
                )
                encoder.writeBool(requiresNIP42Authentication)
                encoder.writeBool(requiresProofOfWork)
                return encoder.encodedBytes
            } catch {
                preconditionFailure("A validated relay registration must encode.")
            }
        }

        init(
            endpoint: PrivateRelayEndpoint,
            operatorIdentity: RelayOperatorIdentity,
            requiresNIP42Authentication: Bool,
            requiresProofOfWork: Bool
        ) throws(ValidationError) {
            guard !requiresNIP42Authentication else {
                throw .nip42AuthenticationRequired
            }
            guard !requiresProofOfWork else { throw .proofOfWorkRequired }
            self.endpoint = endpoint
            self.operatorIdentity = operatorIdentity
        }

        static func decode(from encodedBytes: [UInt8]) throws -> Self {
            try OpalFusion.Mosaic.CanonicalDecoder.decode(
                from: encodedBytes
            ) { decoder in
                guard try decoder.readText()
                        == PrivateDeploymentNostrSelector.identifier else {
                    throw ValidationError.invalidSelector
                }
                let encodedEndpoint = try decoder.readText()
                let endpoint = try PrivateRelayEndpoint(
                    normalizing: encodedEndpoint
                )
                guard endpoint.normalizedURL == encodedEndpoint else {
                    throw ValidationError.nonCanonicalEndpoint
                }
                let operatorIdentity = try RelayOperatorIdentity(
                    decodedCanonicalDigest:
                        decoder.readFixedBytes(byteCount: 32)
                )
                return try .init(
                    endpoint: endpoint,
                    operatorIdentity: operatorIdentity,
                    requiresNIP42Authentication: decoder.readBool(),
                    requiresProofOfWork: decoder.readBool()
                )
            }
        }
    }
}

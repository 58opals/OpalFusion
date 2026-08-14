// OpalFusion+Mosaic+OpalMainnetAlpha+PrivateDeploymentRelaySelectionValidation.swift

extension OpalFusion.Mosaic.OpalMainnetAlpha {
    /// Binds manifest relay identifiers to one canonical private-deployment relay set.
    ///
    /// This validation does not provision connections or prove operator or Tor-path independence.
    /// The application remains responsible for binding each accepted identifier to a concrete,
    /// Tor-only capability from the reviewed operator registry.
    struct PrivateDeploymentRelaySelectionValidation:
        PostManifestRelaySelectionValidating,
        Sendable
    {
        enum ValidationError: Error, Sendable, Equatable {
            case relaySetDigestMismatch
            case invalidEndpoint
            case nonCanonicalEndpoint
            case endpointSetMismatch
        }

        let relaySet: RelaySetDocument

        init(relaySet: RelaySetDocument) {
            self.relaySet = relaySet
        }

        func validateRelaySelection(
            manifestRelaySetDigest: [UInt8],
            endpoints: [PostManifestRelayEndpoint]
        ) throws {
            guard manifestRelaySetDigest == relaySet.digest else {
                throw ValidationError.relaySetDigestMismatch
            }
            var suppliedEndpoints: Set<PrivateRelayEndpoint> = []
            for endpoint in endpoints {
                let normalizedEndpoint: PrivateRelayEndpoint
                do {
                    normalizedEndpoint = try .init(
                        normalizing: endpoint.validatedIdentifier
                    )
                } catch {
                    throw ValidationError.invalidEndpoint
                }
                guard normalizedEndpoint.normalizedURL
                        == endpoint.validatedIdentifier else {
                    throw ValidationError.nonCanonicalEndpoint
                }
                suppliedEndpoints.insert(normalizedEndpoint)
            }
            let expectedEndpoints = Set(
                relaySet.registrations.map(\.endpoint)
            )
            guard suppliedEndpoints == expectedEndpoints else {
                throw ValidationError.endpointSetMismatch
            }
        }
    }
}

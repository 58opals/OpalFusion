// OpalFusion+Mosaic+OpalMainnetAlpha+PostManifestRelaySelection.swift

extension OpalFusion.Mosaic.OpalMainnetAlpha {
    typealias PostManifestRelayEndpoint = OpalFusion.Mosaic
        .RelayPublicationTracker.Endpoint

    /// One externally supplied opaque relay and its already Tor-routed connection.
    struct PostManifestRelayRoute: Sendable {
        let endpoint: PostManifestRelayEndpoint
        let connection: any OpalFusion.Mosaic.TorWebSocketConnectioning

        init(
            endpoint: PostManifestRelayEndpoint,
            connection: any OpalFusion.Mosaic.TorWebSocketConnectioning
        ) {
            self.endpoint = endpoint
            self.connection = connection
        }
    }

    /// An injected authority that binds opaque relay endpoint identifiers to one manifest.
    ///
    /// Endpoint parsing, canonicalization, provisioning, and operator-independence checks remain
    /// outside this transport slice. The validator must establish that the exact three opaque
    /// endpoint identifiers are the selection committed by `manifestRelaySetDigest`. The route
    /// owner separately binds each validated identifier to its injected Tor capability.
    protocol PostManifestRelaySelectionValidating: Sendable {
        func validateRelaySelection(
            manifestRelaySetDigest: [UInt8],
            endpoints: [PostManifestRelayEndpoint]
        ) throws
    }

    /// Seals the manifest-selected endpoint identifiers used by post-manifest relay adapters.
    struct PostManifestRelaySelectionValidation: Sendable, Equatable {
        enum ValidationError: Error, Sendable, Equatable {
            case invalidRelaySetDigest(actual: Int)
            case invalidRelayCount(actual: Int)
            case duplicateRelay(PostManifestRelayEndpoint)
            case rejected
        }

        let manifestRelaySetDigest: [UInt8]
        let endpoints: [PostManifestRelayEndpoint]

        init(
            manifestRelaySetDigest: [UInt8],
            endpoints: [PostManifestRelayEndpoint],
            using validator: some PostManifestRelaySelectionValidating
        ) throws(ValidationError) {
            guard manifestRelaySetDigest.count == 32 else {
                throw .invalidRelaySetDigest(
                    actual: manifestRelaySetDigest.count
                )
            }
            guard endpoints.count == OpalFusion.Mosaic.OpalMainnetAlpha
                .relayCount else {
                throw .invalidRelayCount(actual: endpoints.count)
            }
            var uniqueEndpoints: Set<PostManifestRelayEndpoint> = []
            for endpoint in endpoints {
                guard uniqueEndpoints.insert(endpoint).inserted else {
                    throw .duplicateRelay(endpoint)
                }
            }
            do {
                try validator.validateRelaySelection(
                    manifestRelaySetDigest: manifestRelaySetDigest,
                    endpoints: endpoints
                )
            } catch {
                throw .rejected
            }
            self.manifestRelaySetDigest = Array(manifestRelaySetDigest)
            self.endpoints = endpoints
        }
    }
}

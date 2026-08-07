// OpalFusion+Mosaic+RelayPublicationTracker.swift

extension OpalFusion.Mosaic {
    /// Tracks the draft transport profile's three-relay/two-acceptance rule.
    ///
    /// Endpoint parsing, relay-set canonicalization, Tor routing, event kinds,
    /// and wire acknowledgements remain adapter-owned release blockers.
    struct RelayPublicationTracker: Sendable {
        let endpoints: [Endpoint]
        private var attemptedEndpoints: Set<Endpoint> = []
        private var responses: [Endpoint: Response] = [:]

        init(endpoints: [Endpoint]) throws {
            guard endpoints.count >= 3 else {
                throw ValidationError.fewerThanThreeRelays(
                    actual: endpoints.count
                )
            }
            var uniqueEndpoints: Set<Endpoint> = []
            for endpoint in endpoints {
                guard uniqueEndpoints.insert(endpoint).inserted else {
                    throw ValidationError.duplicateRelay(endpoint)
                }
            }
            self.endpoints = endpoints
        }

        var status: Status {
            guard attemptedEndpoints.count == endpoints.count else {
                return .awaitingResponses
            }
            let acceptanceCount = responses.values.reduce(into: 0) {
                count, response in
                if response == .accepted { count += 1 }
            }
            if acceptanceCount >= 2 { return .accepted }
            let unresolvedCount = endpoints.count - responses.count
            return acceptanceCount + unresolvedCount < 2
                ? .failed
                : .awaitingResponses
        }

        mutating func markAttempted(_ endpoint: Endpoint) throws {
            guard endpoints.contains(endpoint) else {
                throw RecordError.unknownRelay(endpoint)
            }
            attemptedEndpoints.insert(endpoint)
        }

        mutating func record(
            _ response: Response,
            from endpoint: Endpoint
        ) throws {
            guard endpoints.contains(endpoint) else {
                throw RecordError.unknownRelay(endpoint)
            }
            guard attemptedEndpoints.contains(endpoint) else {
                throw RecordError.relayNotAttempted(endpoint)
            }
            if let existingResponse = responses[endpoint] {
                guard existingResponse == response else {
                    throw RecordError.conflictingResponse(endpoint)
                }
                return
            }
            responses[endpoint] = response
        }
    }
}

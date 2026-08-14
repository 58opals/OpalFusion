// MosaicMainnetAlphaPrivateRelayContractValidator.swift

import Testing
@testable import OpalFusion

@Suite("Mosaic mainnet-alpha private relay contract validation")
struct MosaicMainnetAlphaPrivateRelayContractValidator {
    typealias Alpha = OpalFusion.Mosaic.OpalMainnetAlpha
    typealias Tracker = OpalFusion.Mosaic.RelayPublicationTracker

    @Test("Normalize DNS relay endpoints and default TLS port")
    func normalizeDNSRelayEndpointsAndDefaultTLSPort() throws {
        let implicit = try Alpha.PrivateRelayEndpoint(
            normalizing: "wss://relay-a.example"
        )
        let explicit = try Alpha.PrivateRelayEndpoint(
            normalizing: "WSS://RELAY-A.EXAMPLE:443/"
        )

        #expect(implicit == explicit)
        #expect(implicit.normalizedURL == "wss://relay-a.example/")
    }

    @Test(
        "Reject credentials paths queries fragments IP addresses and invalid DNS",
        arguments: [
            "ws://relay.example/",
            "wss://user@relay.example/",
            "wss://relay.example/private",
            "wss://relay.example/?x=1",
            "wss://relay.example/#fragment",
            "wss://127.0.0.1/",
            "wss://127.1/",
            "wss://0x7f000001/",
            "wss://[::1]/",
            "wss://localhost/",
            "wss://relay.example:444/",
            "wss://rélais.example/",
            "wss://bad_host.example/",
            "wss://double..example/",
            "wss:///",
        ]
    )
    func rejectUnsafeRelayEndpoints(_ suppliedURL: String) {
        #expect(throws: (any Error).self) {
            _ = try Alpha.PrivateRelayEndpoint(normalizing: suppliedURL)
        }
    }

    @Test("Derive canonical operator identities without proving independence")
    func deriveCanonicalOperatorIdentitiesWithoutProvingIndependence() throws {
        let uppercase = try Alpha.RelayOperatorIdentity(
            appReviewedRegistryLabel: "Operator A"
        )
        let lowercase = try Alpha.RelayOperatorIdentity(
            appReviewedRegistryLabel: "operator a"
        )
        let other = try Alpha.RelayOperatorIdentity(
            appReviewedRegistryLabel: "operator b"
        )

        #expect(uppercase == lowercase)
        #expect(uppercase.canonicalDigest.count == 32)
        #expect(uppercase.canonicalDigest != other.canonicalDigest)
        #expect(throws: (any Error).self) {
            _ = try Alpha.RelayOperatorIdentity(
                appReviewedRegistryLabel: " operator a"
            )
        }
        #expect(throws: (any Error).self) {
            _ = try Alpha.RelayOperatorIdentity(
                appReviewedRegistryLabel: "operator\nname"
            )
        }
    }

    @Test("Bind exactly three canonical endpoints and configured operators")
    func bindExactlyThreeCanonicalEndpointsAndConfiguredOperators() throws {
        let relaySet = try makeRelaySet()
        let reversedRelaySet = try Alpha.RelaySetDocument(
            registrations: Array(relaySet.registrations.reversed())
        )

        #expect(relaySet == reversedRelaySet)
        #expect(
            !String(decoding: relaySet.canonicalBytes, as: UTF8.self)
                .contains("operator 1")
        )
        #expect(relaySet.digest == reversedRelaySet.digest)
        #expect(try Alpha.RelaySetDocument.decode(from: relaySet.canonicalBytes) == relaySet)
        #expect(throws: OpalFusion.Mosaic.CanonicalCodingError.trailingBytes(1)) {
            _ = try Alpha.RelaySetDocument.decode(
                from: relaySet.canonicalBytes + [0x00]
            )
        }

        let binding = Alpha.PrivateDeploymentRelaySelectionValidation(
            relaySet: relaySet
        )
        let endpoints = relaySet.registrations.map {
            Tracker.Endpoint(validatedIdentifier: $0.endpoint.normalizedURL)
        }
        _ = try Alpha.PostManifestRelaySelectionValidation(
            manifestRelaySetDigest: relaySet.digest,
            endpoints: endpoints,
            using: binding
        )
        #expect(
            throws: Alpha.PostManifestRelaySelectionValidation.ValidationError
                .rejected
        ) {
            _ = try Alpha.PostManifestRelaySelectionValidation(
                manifestRelaySetDigest: relaySet.digest,
                endpoints: [
                    Tracker.Endpoint(
                        validatedIdentifier: "wss://relay-a.example:443/"
                    ),
                    endpoints[1],
                    endpoints[2],
                ],
                using: binding
            )
        }
    }

    @Test("Reject relay capability and diversity policy violations")
    func rejectRelayCapabilityAndDiversityPolicyViolations() throws {
        let first = try makeRegistration(index: 1)
        let second = try makeRegistration(index: 2)

        #expect(
            throws: Alpha.RelaySetDocument.ValidationError
                .invalidRelayCount(actual: 2)
        ) {
            _ = try Alpha.RelaySetDocument(registrations: [first, second])
        }
        #expect(throws: (any Error).self) {
            _ = try Alpha.RelaySetDocument(
                registrations: [first, first, try makeRegistration(index: 3)]
            )
        }
        let duplicateOperator = try Alpha.RelayRegistrationDocument(
            endpoint: Alpha.PrivateRelayEndpoint(
                normalizing: "wss://relay-c.example/"
            ),
            operatorIdentity: first.operatorIdentity,
            requiresNIP42Authentication: false,
            requiresProofOfWork: false
        )
        #expect(throws: (any Error).self) {
            _ = try Alpha.RelaySetDocument(
                registrations: [first, second, duplicateOperator]
            )
        }
        #expect(
            throws: Alpha.RelayRegistrationDocument.ValidationError
                .nip42AuthenticationRequired
        ) {
            _ = try Alpha.RelayRegistrationDocument(
                endpoint: first.endpoint,
                operatorIdentity: first.operatorIdentity,
                requiresNIP42Authentication: true,
                requiresProofOfWork: false
            )
        }
        #expect(
            throws: Alpha.RelayRegistrationDocument.ValidationError
                .proofOfWorkRequired
        ) {
            _ = try Alpha.RelayRegistrationDocument(
                endpoint: first.endpoint,
                operatorIdentity: first.operatorIdentity,
                requiresNIP42Authentication: false,
                requiresProofOfWork: true
            )
        }
    }

}

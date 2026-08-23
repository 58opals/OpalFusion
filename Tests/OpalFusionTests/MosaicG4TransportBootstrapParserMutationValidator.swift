// MosaicG4TransportBootstrapParserMutationValidator.swift

#if os(macOS)
import Foundation
import Testing
@_spi(MosaicPrivateAlpha) @testable import OpalFusion

@Suite("Mosaic G4 transport-bootstrap parser mutation", .serialized)
struct MosaicG4TransportBootstrapParserMutationValidator {
    typealias Runtime = OpalFusion.MosaicPrivateAlphaRuntime

    private struct Fixture {
        let values: MosaicG4PinnedParserFixture.Values
        let proof: Runtime.PrivateDeploymentProof
        let authorizationKey:
            Runtime.TransportBootstrapAuthorizationKeyDocument
        let claimSet: Runtime.TransportBootstrapControlMailboxClaimSet
        let responseSet: Runtime.TransportBootstrapBlindResponseSet
        let registration:
            Runtime.TransportBootstrapAnonymousMailboxRegistration
        let registrationSet:
            Runtime.TransportBootstrapAnonymousMailboxRegistrationSet
        let assignment:
            Runtime.TransportBootstrapAnonymousMailboxAssignment
        let acknowledgementSet:
            Runtime.TransportBootstrapRegistrationSetAcknowledgementSet

        static func load() throws -> Self {
            let values = try MosaicG4PinnedParserFixture.load()
            let proof = try MosaicG4PinnedParserFixture.restoreProof()
            let mailbox = values.postManifestMailbox
            let authorizationKey = try Runtime
                .loadTransportBootstrapAuthorizationKeyDocument(
                    from: mailbox.authorizationKey,
                    proof: proof,
                    currentUnixSeconds: mailbox.currentUnixSeconds
                )
            let claimSet = try Runtime
                .loadTransportBootstrapControlMailboxClaimSet(
                    from: mailbox.controlClaimSet,
                    proof: proof,
                    authorizationKey: authorizationKey,
                    currentUnixSeconds: mailbox.currentUnixSeconds
                )
            let responseSet = try Runtime
                .loadTransportBootstrapBlindResponseSet(
                    from: mailbox.blindResponseSet,
                    proof: proof,
                    authorizationKey: authorizationKey,
                    claimSet: claimSet,
                    currentUnixSeconds: mailbox.currentUnixSeconds
                )
            let registration = try Runtime
                .loadTransportBootstrapAnonymousMailboxRegistration(
                    from: mailbox.registration,
                    proof: proof,
                    authorizationKey: authorizationKey,
                    claimSet: claimSet,
                    responseSet: responseSet,
                    currentUnixSeconds: mailbox.currentUnixSeconds
                )
            let registrationSet = try Runtime
                .loadTransportBootstrapAnonymousMailboxRegistrationSet(
                    from: mailbox.registrationSet,
                    proof: proof,
                    authorizationKey: authorizationKey,
                    claimSet: claimSet,
                    responseSet: responseSet,
                    currentUnixSeconds: mailbox.currentUnixSeconds
                )
            let assignment = try Runtime
                .loadTransportBootstrapAnonymousMailboxAssignment(
                    from: mailbox.assignment,
                    proof: proof,
                    authorizationKey: authorizationKey,
                    claimSet: claimSet,
                    responseSet: responseSet,
                    registration: registration,
                    currentUnixSeconds: mailbox.currentUnixSeconds
                )
            let acknowledgementSet = try Runtime
                .loadTransportBootstrapRegistrationSetAcknowledgementSet(
                    from: mailbox.acknowledgementSet,
                    proof: proof,
                    authorizationKey: authorizationKey,
                    claimSet: claimSet,
                    responseSet: responseSet,
                    registrationSet: registrationSet,
                    currentUnixSeconds: mailbox.currentUnixSeconds
                )
            return .init(
                values: values,
                proof: proof,
                authorizationKey: authorizationKey,
                claimSet: claimSet,
                responseSet: responseSet,
                registration: registration,
                registrationSet: registrationSet,
                assignment: assignment,
                acknowledgementSet: acknowledgementSet
            )
        }
    }

    @Test(
        "Mutate authorization-key and control-claim parser roots",
        .timeLimit(.minutes(1))
    )
    func mutateAuthorizationRoots() throws {
        let fixture = try Fixture.load()
        let claim = try #require(fixture.claimSet.claims.first)
        let current = fixture.values.postManifestMailbox.currentUnixSeconds
        let vectors = [
            MosaicDeterministicParserMutationVector(
                name: "transport-bootstrap authorization key",
                seedBytes: Array(fixture.authorizationKey.canonicalDocument)
            ) { bytes in
                let decoded = try Runtime
                    .loadTransportBootstrapAuthorizationKeyDocument(
                        from: Data(bytes),
                        proof: fixture.proof,
                        currentUnixSeconds: current
                    )
                return decoded.canonicalDocument == Data(bytes)
            },
            MosaicDeterministicParserMutationVector(
                name: "transport-bootstrap control claim",
                seedBytes: Array(claim.canonicalDocument)
            ) { bytes in
                let decoded = try Runtime
                    .loadTransportBootstrapControlMailboxClaim(
                        from: Data(bytes),
                        proof: fixture.proof,
                        authorizationKey: fixture.authorizationKey,
                        currentUnixSeconds: current
                    )
                return decoded.canonicalDocument == Data(bytes)
            },
        ]

        try MosaicDeterministicParserMutationCampaign.validate(
            vectors,
            seed: 0x510E_527F_ADE6_82D1,
            seededMutationCount: 16
        )
    }

    @Test(
        "Mutate control-claim-set parser root",
        .timeLimit(.minutes(1))
    )
    func mutateControlClaimSetRoot() throws {
        let fixture = try Fixture.load()
        let current = fixture.values.postManifestMailbox.currentUnixSeconds
        let vectors = [
            MosaicDeterministicParserMutationVector(
                name: "transport-bootstrap control claim set",
                seedBytes: Array(fixture.claimSet.canonicalDocument)
            ) { bytes in
                let decoded = try Runtime
                    .loadTransportBootstrapControlMailboxClaimSet(
                        from: Data(bytes),
                        proof: fixture.proof,
                        authorizationKey: fixture.authorizationKey,
                        currentUnixSeconds: current
                    )
                return decoded.canonicalDocument == Data(bytes)
            },
        ]

        try MosaicDeterministicParserMutationCampaign.validate(
            vectors,
            seed: 0x9B05_688C_2B3E_6C1F,
            seededMutationCount: 16
        )
    }

    @Test(
        "Mutate blind-response-set parser root",
        .timeLimit(.minutes(1))
    )
    func mutateBlindResponseSetRoot() throws {
        let fixture = try Fixture.load()
        let current = fixture.values.postManifestMailbox.currentUnixSeconds
        let vectors = [
            MosaicDeterministicParserMutationVector(
                name: "transport-bootstrap blind response set",
                seedBytes: Array(fixture.responseSet.canonicalDocument)
            ) { bytes in
                let decoded = try Runtime
                    .loadTransportBootstrapBlindResponseSet(
                        from: Data(bytes),
                        proof: fixture.proof,
                        authorizationKey: fixture.authorizationKey,
                        claimSet: fixture.claimSet,
                        currentUnixSeconds: current
                    )
                return decoded.canonicalDocument == Data(bytes)
            },
        ]

        try MosaicDeterministicParserMutationCampaign.validate(
            vectors,
            seed: 0xCBBB_9D5D_C105_9ED8,
            seededMutationCount: 16
        )
    }

    @Test(
        "Mutate anonymous-request parser root",
        .timeLimit(.minutes(1))
    )
    func mutateAnonymousRequestRoot() throws {
        let fixture = try Fixture.load()
        let input = fixture.registration.token.input
        let context = Runtime.TransportBootstrapContract.Context(
            proof: fixture.proof
        )
        let vectors = [
            MosaicDeterministicParserMutationVector(
                name: "transport-bootstrap anonymous request input",
                seedBytes: Array(input.canonicalDocument)
            ) { bytes in
                let decoded = try Runtime
                    .loadTransportBootstrapAnonymousMailboxInput(
                        Data(bytes),
                        context: context,
                        authorizationKey: fixture.authorizationKey
                    )
                return decoded.canonicalDocument == Data(bytes)
            },
        ]

        try MosaicDeterministicParserMutationCampaign.validate(
            vectors,
            seed: 0x1F83_D9AB_FB41_BD6B,
            seededMutationCount: 16
        )
    }

    @Test(
        "Mutate anonymous-registration parser root",
        .timeLimit(.minutes(1))
    )
    func mutateAnonymousRegistrationRoot() throws {
        let fixture = try Fixture.load()
        let current = fixture.values.postManifestMailbox.currentUnixSeconds
        let vectors = [
            MosaicDeterministicParserMutationVector(
                name: "transport-bootstrap anonymous registration",
                seedBytes: Array(fixture.registration.canonicalDocument)
            ) { bytes in
                let decoded = try Runtime
                    .loadTransportBootstrapAnonymousMailboxRegistration(
                        from: Data(bytes),
                        proof: fixture.proof,
                        authorizationKey: fixture.authorizationKey,
                        claimSet: fixture.claimSet,
                        responseSet: fixture.responseSet,
                        currentUnixSeconds: current
                    )
                return decoded.canonicalDocument == Data(bytes)
            },
        ]

        try MosaicDeterministicParserMutationCampaign.validate(
            vectors,
            seed: 0x6A09_E667_F3BC_C908,
            seededMutationCount: 16,
            maximumMutationCount: 12
        )
    }

    @Test(
        "Mutate registration-set parser root",
        .timeLimit(.minutes(1))
    )
    func mutateRegistrationSetRoot() throws {
        let fixture = try Fixture.load()
        let current = fixture.values.postManifestMailbox.currentUnixSeconds
        let vectors = [
            MosaicDeterministicParserMutationVector(
                name: "transport-bootstrap registration set",
                seedBytes: Array(fixture.registrationSet.canonicalDocument)
            ) { bytes in
                let decoded = try Runtime
                    .loadTransportBootstrapAnonymousMailboxRegistrationSet(
                        from: Data(bytes),
                        proof: fixture.proof,
                        authorizationKey: fixture.authorizationKey,
                        claimSet: fixture.claimSet,
                        responseSet: fixture.responseSet,
                        currentUnixSeconds: current
                    )
                return decoded.canonicalDocument == Data(bytes)
            },
        ]

        try MosaicDeterministicParserMutationCampaign.validate(
            vectors,
            seed: 0x5BE0_CD19_137E_2179,
            seededMutationCount: 16,
            maximumMutationCount: 12
        )
    }

    @Test(
        "Mutate anonymous-assignment parser root",
        .timeLimit(.minutes(1))
    )
    func mutateAnonymousAssignmentRoot() throws {
        let fixture = try Fixture.load()
        let current = fixture.values.postManifestMailbox.currentUnixSeconds
        let vectors = [
            MosaicDeterministicParserMutationVector(
                name: "transport-bootstrap anonymous assignment",
                seedBytes: Array(fixture.assignment.canonicalDocument)
            ) { bytes in
                let decoded = try Runtime
                    .loadTransportBootstrapAnonymousMailboxAssignment(
                        from: Data(bytes),
                        proof: fixture.proof,
                        authorizationKey: fixture.authorizationKey,
                        claimSet: fixture.claimSet,
                        responseSet: fixture.responseSet,
                        registration: fixture.registration,
                        currentUnixSeconds: current
                    )
                return decoded.canonicalDocument == Data(bytes)
            },
        ]

        try MosaicDeterministicParserMutationCampaign.validate(
            vectors,
            seed: 0xBB67_AE85_84CA_A73B,
            seededMutationCount: 16,
            maximumMutationCount: 12
        )
    }

    @Test(
        "Mutate acknowledgement parser root",
        .timeLimit(.minutes(1))
    )
    func mutateAcknowledgementRoot() throws {
        let fixture = try Fixture.load()
        let acknowledgement = try #require(
            fixture.acknowledgementSet.acknowledgements.first
        )
        let current = fixture.values.postManifestMailbox.currentUnixSeconds
        let vectors = [
            MosaicDeterministicParserMutationVector(
                name: "transport-bootstrap registration acknowledgement",
                seedBytes: Array(acknowledgement.canonicalDocument)
            ) { bytes in
                let decoded = try Runtime
                    .loadTransportBootstrapRegistrationSetAcknowledgement(
                        from: Data(bytes),
                        proof: fixture.proof,
                        authorizationKey: fixture.authorizationKey,
                        claimSet: fixture.claimSet,
                        responseSet: fixture.responseSet,
                        registrationSet: fixture.registrationSet,
                        currentUnixSeconds: current
                    )
                return decoded.canonicalDocument == Data(bytes)
            },
        ]

        try MosaicDeterministicParserMutationCampaign.validate(
            vectors,
            seed: 0xA54F_F53A_5F1D_36F1,
            seededMutationCount: 16,
            maximumMutationCount: 12
        )
    }

    @Test(
        "Mutate acknowledgement-set parser root",
        .timeLimit(.minutes(1))
    )
    func mutateAcknowledgementSetRoot() throws {
        let fixture = try Fixture.load()
        let current = fixture.values.postManifestMailbox.currentUnixSeconds
        let canonicalDocument = fixture.acknowledgementSet.canonicalDocument
        #expect(
            canonicalDocument
                == fixture.values.postManifestMailbox.acknowledgementSet
        )
        let canonicalBytes = Array(canonicalDocument)
        let vectors = [
            MosaicDeterministicParserMutationVector(
                name: "transport-bootstrap acknowledgement set",
                seedBytes: canonicalBytes
            ) { bytes in
                if bytes == canonicalBytes {
                    return true
                }
                let decoded = try Runtime
                    .loadTransportBootstrapRegistrationSetAcknowledgementSet(
                        from: Data(bytes),
                        proof: fixture.proof,
                        authorizationKey: fixture.authorizationKey,
                        claimSet: fixture.claimSet,
                        responseSet: fixture.responseSet,
                        registrationSet: fixture.registrationSet,
                        currentUnixSeconds: current
                    )
                return decoded.canonicalDocument == Data(bytes)
            },
        ]

        try MosaicDeterministicParserMutationCampaign.validate(
            vectors,
            seed: 0x3C6E_F372_FE94_F82B,
            seededMutationCount: 16,
            maximumMutationCount: 2
        )
    }
}
#endif

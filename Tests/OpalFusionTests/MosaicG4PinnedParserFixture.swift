// MosaicG4PinnedParserFixture.swift

#if os(macOS)
import Foundation
import OpalCrypto
import Testing
@_spi(MosaicPrivateAlpha) @testable import OpalFusion

enum MosaicG4PinnedParserFixture {
    typealias Alpha = OpalFusion.Mosaic.OpalMainnetAlpha
    typealias Runtime = OpalFusion.MosaicPrivateAlphaRuntime

    struct StoredEvent: Decodable, Sendable {
        let acceptedAtUnixSeconds: UInt64
        let canonicalEventBytes: Data

        var recoveryBytes: Data {
            get throws {
                try Runtime.PrivateDeploymentEvent(
                    canonicalEventBytes: canonicalEventBytes,
                    acceptedAtUnixSeconds: acceptedAtUnixSeconds
                ).canonicalRecoveryBytes()
            }
        }
    }

    struct PostManifestMailbox: Decodable, Sendable {
        let currentUnixSeconds: UInt64
        let authorizationKey: Data
        let controlClaimSet: Data
        let blindResponseSet: Data
        let registrationSet: Data
        let acknowledgementSet: Data
        let registration: Data
        let assignment: Data
        let contributorControlIdentity: Data
        let localControlRecipientPrivateKey: Data
    }

    struct Values: Decodable, Sendable {
        let schemaVersion: Int
        let sourceRevision: String
        let sourceFixtureSHA256: String
        let epoch: UInt64
        let componentAuthorizationKey: Data
        let bchSignatureAuthorizationKey: Data
        let opaquePoolDocument: Data
        let relaySetDocument: Data
        let beaconEvents: [StoredEvent]
        let acknowledgementEvents: [StoredEvent]
        let admissionEvents: [StoredEvent]
        let commitmentEvents: [StoredEvent]
        let revealEvents: [StoredEvent]
        let nonceEvent: StoredEvent
        let proposalEvent: StoredEvent
        let signatureEvents: [StoredEvent]
        let postManifestCompletionEvent: StoredEvent
        let postManifestMailbox: PostManifestMailbox

        func restoreProof() throws -> Runtime.PrivateDeploymentProof {
            let prefix = try preManifestPrefix()
            let formation = try Runtime.restorePrivateDeploymentFormation(
                discoveryEpochStartUnixSeconds: epoch,
                phase: .manifestAgreement,
                canonicalDocuments: prefix
            )
            guard case let .manifestSignatures(
                proposal,
                _,
                signatures
            ) = formation else {
                throw Failure.invalidFormation
            }
            let completeManifest = try Alpha.RoundManifest(
                core: proposal.manifest.core,
                signatures: signatures.map(\.signature)
            )
            let proof = try Runtime.restorePrivateDeploymentProof(
                discoveryEpochStartUnixSeconds: epoch,
                canonicalDocuments: prefix
                    + [Data(completeManifest.canonicalBytes)]
            )
            guard Data(
                proof.completeManifest.core
                    .componentAuthorizationVerificationKey
                    .subjectPublicKeyInfo
            ) == componentAuthorizationKey,
            Data(
                proof.completeManifest.core
                    .bchSignatureAuthorizationVerificationKey
                    .subjectPublicKeyInfo
            ) == bchSignatureAuthorizationKey else {
                throw Failure.invalidFormation
            }
            return proof
        }

        private func preManifestPrefix() throws -> [Data] {
            [opaquePoolDocument, relaySetDocument]
                + (try beaconEvents.map { try $0.recoveryBytes })
                + (try acknowledgementEvents.map {
                    try $0.recoveryBytes
                })
                + (try admissionEvents.map { try $0.recoveryBytes })
                + (try commitmentEvents.map { try $0.recoveryBytes })
                + (try revealEvents.map { try $0.recoveryBytes })
                + [
                    try nonceEvent.recoveryBytes,
                    try proposalEvent.recoveryBytes,
                ]
                + (try signatureEvents.map { try $0.recoveryBytes })
        }
    }

    enum Failure: Error {
        case invalidFixtureDigest
        case invalidFixtureMetadata
        case invalidFormation
    }

    static func load() throws -> Values {
        try cachedValues.get()
    }

    static func restoreProof() throws -> Runtime.PrivateDeploymentProof {
        try cachedProof.get()
    }

    private static let cachedValues = Result {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures")
            .appendingPathComponent("MosaicG4PinnedParserFixture.json")
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        guard OpalCrypto.Hashing.sha256(data) == fixtureSHA256 else {
            throw Failure.invalidFixtureDigest
        }
        let values = try JSONDecoder().decode(Values.self, from: data)
        guard values.schemaVersion == 1,
              values.sourceRevision == sourceRevision,
              values.sourceFixtureSHA256 == sourceFixtureSHA256 else {
            throw Failure.invalidFixtureMetadata
        }
        return values
    }

    private static let cachedProof = Result {
        try cachedValues.get().restoreProof()
    }

    private static let sourceRevision =
        "79ba5f91449b2c0d5cd6ec73c38fafd58cae0b46"
    private static let sourceFixtureSHA256 =
        "ec6755c6cf6a736ddf8538d32e0fa48afc247342fe6a4a424d826a0a62f2ee7a"
    private static let fixtureSHA256 = Data([
        0x06, 0x1a, 0xe1, 0x1c, 0xc5, 0x41, 0x5b, 0xbe,
        0x41, 0x4a, 0xb6, 0x74, 0x5f, 0x65, 0x38, 0x9b,
        0x2e, 0xab, 0x00, 0x94, 0x24, 0xc8, 0x93, 0x89,
        0xea, 0xc4, 0x5e, 0xda, 0x57, 0x7a, 0x30, 0x7f,
    ])
}

@Suite("Mosaic G4 pinned parser fixture")
struct MosaicG4PinnedParserFixtureValidator {
    @Test(
        "Restore the exact production-graph proof without regeneration",
        .timeLimit(.minutes(1))
    )
    func restoreExactProof() throws {
        let values = try MosaicG4PinnedParserFixture.load()
        let proof = try MosaicG4PinnedParserFixture.restoreProof()

        #expect(proof.canonicalDocuments.count == 59)
        #expect(proof.controlIdentities.count == 9)
        #expect(proof.contributorControlIdentities.count == 8)
        #expect(values.postManifestMailbox.authorizationKey.isEmpty == false)
        #expect(values.postManifestMailbox.assignment.isEmpty == false)
    }
}
#endif

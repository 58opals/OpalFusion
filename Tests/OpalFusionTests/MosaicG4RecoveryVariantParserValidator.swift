// MosaicG4RecoveryVariantParserValidator.swift

#if os(macOS)
import Foundation
import OpalCrypto
import Testing
@_spi(MosaicPrivateAlpha) @testable import OpalFusion

@Suite("Mosaic G4 recovery-variant parser validation", .serialized)
struct MosaicG4RecoveryVariantParserValidator {
    typealias Alpha = OpalFusion.Mosaic.OpalMainnetAlpha
    typealias Runtime = OpalFusion.MosaicPrivateAlphaRuntime

    private struct PinnedEvents: Decodable, Sendable {
        let schemaVersion: Int
        let sourceRevision: String
        let sourceFixtureSHA256: String
        let conflictingAdmissionRecoveryBytes: Data
        let localAbortRecoveryBytes: Data

        static func load() throws -> Self {
            try cached.get()
        }

        private static let cached = Result {
            let url = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("Fixtures")
                .appendingPathComponent(
                    "MosaicG4PinnedRecoveryEvents.json"
                )
            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            guard OpalCrypto.Hashing.sha256(data) == fixtureSHA256 else {
                throw Failure.invalidFixtureDigest
            }
            let values = try JSONDecoder().decode(Self.self, from: data)
            guard values.schemaVersion == 1,
                  values.sourceRevision == sourceRevision,
                  values.sourceFixtureSHA256 == sourceFixtureSHA256 else {
                throw Failure.invalidFixtureMetadata
            }
            return values
        }

        private static let sourceRevision =
            "79ba5f91449b2c0d5cd6ec73c38fafd58cae0b46"
        private static let sourceFixtureSHA256 =
            "061ae11cc5415bbe414ab6745f65389b2eab009424c89389eac45eda577a307f"
        private static let fixtureSHA256 = Data([
            0x12, 0x70, 0xa4, 0xfb, 0xa5, 0x75, 0x49, 0xd3,
            0xa8, 0x45, 0x67, 0xcb, 0xef, 0x42, 0x68, 0xb9,
            0xcb, 0xfa, 0xa4, 0x63, 0xb5, 0xd9, 0xc3, 0xa3,
            0x23, 0x43, 0xad, 0x0f, 0xc7, 0xb0, 0x7f, 0x53,
        ])
    }

    private enum Failure: Error {
        case invalidFixtureDigest
        case invalidFixtureMetadata
    }

    private enum PostManifestVariant {
        case published
        case authorized
    }

    @Test(
        "Restore pre-manifest abort publication and terminal variants",
        .timeLimit(.minutes(1))
    )
    func restorePreManifestRecoveryVariants() throws {
        let values = try MosaicG4PinnedParserFixture.load()
        let pinnedEvents = try PinnedEvents.load()
        let binding = try makeBinding(seed: 0x74)
        let storedAdmission = try Runtime.PrivateDeploymentEvent
            .decodeRecoveryBytes(
                try #require(values.admissionEvents.first).recoveryBytes
            )
        let conflictingAdmission = try Runtime.PrivateDeploymentEvent
            .decodeRecoveryBytes(
                pinnedEvents.conflictingAdmissionRecoveryBytes
            )
        let admissionDocuments = try baseDocuments(values)
            + values.beaconEvents.map { try $0.recoveryBytes }
            + values.acknowledgementEvents.map { try $0.recoveryBytes }
            + [storedAdmission.canonicalRecoveryBytes()]
        let equivocation = Runtime.RecoveryState(
            binding: binding,
            revision: 20,
            discoveryEpochStartUnixSeconds: values.epoch,
            phase: .admission,
            preManifestDocuments: admissionDocuments,
            preManifestAbortCause:
                .equivocation(conflictingAdmission),
            manifestState: .forming,
            postManifestJournalState: .uninitialized,
            publicationState: .none,
            terminalState: .active
        )

        let invalidEvent = try Runtime.PrivateDeploymentEvent
            .decodeRecoveryBytes(
                try #require(values.signatureEvents.first).recoveryBytes
            )
        let roleElectionDocuments = try baseDocuments(values)
            + values.beaconEvents.map { try $0.recoveryBytes }
            + values.acknowledgementEvents.map { try $0.recoveryBytes }
            + values.admissionEvents.map { try $0.recoveryBytes }
            + values.commitmentEvents.map { try $0.recoveryBytes }
        let invalidAuthenticatedMessage = Runtime.RecoveryState(
            binding: binding,
            revision: 21,
            discoveryEpochStartUnixSeconds: values.epoch,
            phase: .roleElection,
            preManifestDocuments: roleElectionDocuments,
            preManifestAbortCause:
                .invalidAuthenticatedMessage(invalidEvent),
            manifestState: .forming,
            postManifestJournalState: .uninitialized,
            publicationState: .none,
            terminalState: .active
        )

        let endpoints = try relayEndpoints(values)
        let formationPublication = Runtime.RecoveryState(
            binding: binding,
            revision: 22,
            discoveryEpochStartUnixSeconds: values.epoch,
            phase: .admission,
            preManifestDocuments: admissionDocuments,
            preManifestAbortCause: .none,
            manifestState: .forming,
            postManifestJournalState: .uninitialized,
            publicationState: .formation(
                event: storedAdmission,
                relayEndpointIdentifiers: endpoints
            ),
            terminalState: .active
        )

        let abortEvent = try Runtime.PrivateDeploymentEvent
            .decodeRecoveryBytes(pinnedEvents.localAbortRecoveryBytes)
        let evidence = try Runtime.RecoveryState
            .makePreManifestTerminalEvidence(
                binding: binding,
                phase: .admission,
                event: abortEvent,
                wasLocallyPublished: true,
                predecessorRevision: equivocation.revision,
                priorSnapshotDigest: equivocation.digest()
            )
        var terminalPublication = equivocation
        terminalPublication.revision += 1
        terminalPublication.publicationState = .terminal(
            reason: .aborted,
            event: abortEvent,
            relayEndpointIdentifiers: endpoints,
            exactEvidenceBytes: evidence
        )
        var authorizedTerminal = equivocation
        authorizedTerminal.revision += 2
        authorizedTerminal.terminalState = .authorized(
            .aborted,
            exactEvidenceBytes: evidence
        )

        for state in [
            equivocation,
            invalidAuthenticatedMessage,
            formationPublication,
            terminalPublication,
            authorizedTerminal,
        ] {
            try expectCanonicalRoundTrip(state)
        }
    }

    @Test(
        "Restore post-manifest publication-terminal variant",
        .timeLimit(.minutes(1))
    )
    func restorePostManifestPublicationTerminalVariant() throws {
        try expectCanonicalRoundTrip(
            makePostManifestTerminalState(.published)
        )
    }

    @Test(
        "Restore post-manifest authorized-terminal variant",
        .timeLimit(.minutes(1))
    )
    func restorePostManifestAuthorizedTerminalVariant() throws {
        try expectCanonicalRoundTrip(
            makePostManifestTerminalState(.authorized)
        )
    }

    private func makePostManifestTerminalState(
        _ variant: PostManifestVariant
    ) throws -> Runtime.RecoveryState {
        let values = try MosaicG4PinnedParserFixture.load()
        let proof = try MosaicG4PinnedParserFixture.restoreProof()
        let binding = try makeBinding(seed: 0x84)
        let predecessor = Runtime.RecoveryState(
            binding: binding,
            revision: 50,
            discoveryEpochStartUnixSeconds: values.epoch,
            phase: .walletReservation,
            preManifestDocuments: proof.canonicalDocuments,
            preManifestAbortCause: .none,
            manifestState: .validated(
                privateManifestProposalBytes: Data(
                    proof.proposalValidation.canonicalBody
                ),
                completeManifestBytes: Data(
                    proof.completeManifest.canonicalBytes
                )
            ),
            postManifestJournalState: .initialized,
            publicationState: .none,
            terminalState: .active
        )
        let completionEvent = try Runtime.PrivateDeploymentEvent
            .decodeRecoveryBytes(
                values.postManifestCompletionEvent.recoveryBytes
            )
        let nostrEvent = try completionEvent.decodeCanonicalNostrEvent()
        let payload = try Alpha.PreManifestNostrCodec
            .decodeCanonicalEnvelope(nostrEvent)
        var authorityEncoder = OpalFusion.Mosaic.CanonicalEncoder()
        authorityEncoder.writeUInt8(0)
        try authorityEncoder.writeBytes(payload.body)
        let admissionSnapshotDigest = Data(repeating: 0xA1, count: 32)
        let publicationSnapshotDigest = Data(repeating: 0xA2, count: 32)
        let terminalIdentity = try Runtime.PostManifestExecution
            .makeTerminalIdentity(
                binding: binding,
                kind: .completed,
                authorityIdentityBytes:
                    Data(authorityEncoder.encodedBytes),
                admissionSnapshotDigest: admissionSnapshotDigest,
                publicationSnapshotDigest: publicationSnapshotDigest,
                receivedTerminalEvent: nil
            )
        let evidence = try Runtime.PostManifestTerminalEvidence(
            binding: binding,
            reason: .completed,
            wasReceived: false,
            predecessorRevision: predecessor.revision,
            predecessorSnapshotDigest: predecessor.digest(),
            localControlIdentity: nostrEvent.publicKey.rawRepresentation,
            terminalIdentity: terminalIdentity,
            event: completionEvent,
            admissionSnapshotDigest: admissionSnapshotDigest,
            publicationSnapshotDigest: publicationSnapshotDigest
        ).canonicalBytes()
        var state = predecessor
        switch variant {
        case .published:
            state.revision += 1
            state.publicationState = .terminal(
                reason: .completed,
                event: completionEvent,
                relayEndpointIdentifiers: try relayEndpoints(values),
                exactEvidenceBytes: evidence
            )
        case .authorized:
            state.revision += 2
            state.terminalState = .authorized(
                .completed,
                exactEvidenceBytes: evidence
            )
        }
        return state
    }

    private func expectCanonicalRoundTrip(
        _ state: Runtime.RecoveryState
    ) throws {
        let bytes = try state.canonicalBytes()
        let decoded = try Runtime.RecoveryState.decode(
            from: bytes,
            expectedBinding: state.binding
        )
        #expect(decoded == state)
        #expect(try decoded.canonicalBytes() == bytes)
    }

    private func baseDocuments(
        _ values: MosaicG4PinnedParserFixture.Values
    ) -> [Data] {
        [values.opaquePoolDocument, values.relaySetDocument]
    }

    private func relayEndpoints(
        _ values: MosaicG4PinnedParserFixture.Values
    ) throws -> [String] {
        try Alpha.RelaySetDocument.decode(
            from: Array(values.relaySetDocument)
        ).registrations.map { $0.endpoint.normalizedURL }
    }

    private func makeBinding(seed: UInt8) throws -> Runtime.Binding {
        try .init(
            attemptIdentifier: Data(repeating: seed, count: 32),
            generationIdentifier: Data(repeating: seed &+ 1, count: 32),
            materialIdentifier: Data(repeating: seed &+ 2, count: 32)
        )
    }
}
#endif

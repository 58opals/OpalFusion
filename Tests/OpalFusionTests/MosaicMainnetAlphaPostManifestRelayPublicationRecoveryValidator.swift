// MosaicMainnetAlphaPostManifestRelayPublicationRecoveryValidator.swift

import Foundation
import OpalCrypto
import Testing
@_spi(MosaicPrivateAlpha) @testable import OpalFusion

@Suite("Mosaic mainnet-alpha durable post-manifest relay continuation", .serialized)
struct MosaicMainnetAlphaPostManifestRelayPublicationRecoveryValidator {
    typealias Alpha = OpalFusion.Mosaic.OpalMainnetAlpha
    typealias Bridge = Alpha.PostManifestControlPublicationBridge
    typealias Fixture = MosaicMainnetAlphaAdmissionLedgerFixtures
    typealias Journal = Alpha.PostManifestRelayPublicationJournal
    typealias Nostr = OpalFusion.Mosaic.NostrNamespace
    typealias Publisher = Alpha.PostManifestRelayPublisher
    typealias PublicationJournalFixture =
        MosaicMainnetAlphaRelayPublicationJournalFixture
    typealias Runtime = OpalFusion.MosaicPrivateAlphaRuntime
    typealias Tracker = OpalFusion.Mosaic.RelayPublicationTracker
    typealias Transport = Alpha.PostManifestNIP59Transport

    private struct ExactRelaySelectionValidator:
        Alpha.PostManifestRelaySelectionValidating
    {
        let digest: [UInt8]
        let endpoints: Set<Tracker.Endpoint>

        func validateRelaySelection(
            manifestRelaySetDigest: [UInt8],
            endpoints: [Tracker.Endpoint]
        ) throws {
            guard manifestRelaySetDigest == digest,
                  Set(endpoints) == self.endpoints else {
                throw ProbeFailure.invalidSelection
            }
        }
    }

    private struct SharedFixture: Sendable {
        let publicationContext: Bridge.Context
        let relaySelection: Alpha.PostManifestRelaySelectionValidation
        let journalContext: Journal.Context
        let giftWrap: Publisher.GiftWrap
        let binding: Journal.PublicationBinding
        let codingLimits: Nostr.RelayMessageCodingLimits
    }

    private enum ProbeFailure: Error {
        case invalidSelection
    }

    private enum AppendBoundary: CaseIterable, Equatable, Sendable {
        case preparedBatch
        case publicationPermit
        case relayAttempt
        case relayAcknowledgement
        case completion

        var appendKind: PublicationJournalFixture.AppendKind {
            switch self {
            case .preparedBatch:
                .prepared
            case .publicationPermit:
                .publicationPermitted
            case .relayAttempt:
                .attempted
            case .relayAcknowledgement:
                .acknowledged
            case .completion:
                .completed
            }
        }
    }

    private static let sharedFixtureTask = Task {
        try makeSharedFixture()
    }

    @Test("Reject an oversized publication recovery snapshot before replay")
    func rejectOversizedRecoverySnapshot() async throws {
        let fixture = try await Self.sharedFixtureTask.value
        let context = fixture.journalContext
        let binding = try Runtime.Binding(
            attemptIdentifier: Data(
                context.attemptIdentifier.validatedBytes
            ),
            generationIdentifier: Data(
                context.generationIdentifier.opaqueBytes
            ),
            materialIdentifier: Data(
                context.materialIdentifier.opaqueBytes
            )
        )
        let store = MosaicPrivateAlphaRuntimePersistenceStore()
        let oversized = Data(
            count: Journal.maximumRecoverySnapshotByteCount + 1
        )
        _ = try store.compareAndSwap(binding, nil, oversized)
        let persistence = Runtime.PostManifestPublicationPersistence(
            load: store.load,
            compareAndSwap: store.compareAndSwap
        )

        #expect(throws: (any Error).self) {
            try Journal.initializeRecoverySnapshot(
                binding: binding,
                persistence: persistence,
                context: context,
                requireExisting: true
            )
        }
        #expect(store.recordedCompareAndSwapCallCount == 1)
    }

    @Test("Fail closed at every durable publication boundary")
    func failClosedAtEveryWriteAheadBoundary() async throws {
        let fixture = try await Self.sharedFixtureTask.value
        for failureKind in [
            MosaicMainnetAlphaRelayPublicationJournalFixture.AppendKind
                .prepared,
            .attempted,
            .acknowledged,
            .completed,
        ] {
            let persistence =
                MosaicMainnetAlphaRelayPublicationJournalFixture()
            persistence.failNextAppend(
                of: failureKind,
                leaving: .priorSnapshot
            )
            let journal = try Journal(
                context: fixture.journalContext,
                persistence: persistence.persistence
            )
            let connections = makeConnections()
            let publisher = try makePublisher(
                fixture: fixture,
                journal: journal,
                connections: connections
            )
            let publication = Task {
                try await publisher.publish(
                    fixture.giftWrap,
                    binding: fixture.binding
                )
            }

            switch failureKind {
            case .prepared, .publicationPermitted, .attempted:
                break
            case .acknowledged:
                for connection in connections {
                    await connection.waitUntilSentTextCount(1)
                }
                await connections[0].receive(
                    acknowledgement(
                        for: fixture.giftWrap,
                        accepted: true
                    )
                )
            case .completed:
                for connection in connections {
                    await connection.waitUntilSentTextCount(1)
                }
                await connections[0].receive(
                    acknowledgement(
                        for: fixture.giftWrap,
                        accepted: true
                    )
                )
                await connections[1].receive(
                    acknowledgement(
                        for: fixture.giftWrap,
                        accepted: true
                    )
                )
            }

            await #expect(throws: Publisher.Failure.journalFailed) {
                try await publication.value
            }
            for connection in connections {
                #expect(await connection.closeCount == 1)
            }
            if failureKind == .prepared || failureKind == .attempted {
                for connection in connections {
                    #expect(await connection.openCount == 0)
                    #expect(await connection.sentTexts.isEmpty)
                }
            }
        }
    }

    @Test(
        "Reconcile exact durable state after every append error",
        arguments: AppendBoundary.allCases,
        [
            PublicationJournalFixture.AppendFailureDurability.appendedRecord,
            .priorSnapshot,
        ]
    )
    private func reconcileIndeterminateAppend(
        boundary: AppendBoundary,
        durability: PublicationJournalFixture.AppendFailureDurability
    ) async throws {
        let fixture = try await Self.sharedFixtureTask.value
        try verifyAppendReconciliation(
            boundary: boundary,
            durability: durability,
            fixture: fixture
        )
    }

    @Test("Reject a divergent durable snapshot after an append error")
    func rejectDivergentAppendSnapshot() async throws {
        let fixture = try await Self.sharedFixtureTask.value
        let persistence = PublicationJournalFixture()
        let journal = try Journal(
            context: fixture.journalContext,
            persistence: persistence.persistence
        )
        persistence.failNextAppend(
            of: .prepared,
            leaving: .duplicatedRecord
        )

        #expect(throws: Journal.RecordingError.staleOrCorruptSnapshot) {
            _ = try journal.prepare(
                fixture.giftWrap,
                binding: fixture.binding
            )
        }
        #expect(throws: Journal.InitializationError.invalidSnapshot) {
            _ = try Journal(
                context: fixture.journalContext,
                persistence: persistence.persistence
            )
        }
    }

    @Test("Restore byte-identical publication through unresolved fresh routes")
    func restoreByteIdenticalPublication() async throws {
        let fixture = try await Self.sharedFixtureTask.value
        let persistence = MosaicMainnetAlphaRelayPublicationJournalFixture()
        let firstJournal = try Journal(
            context: fixture.journalContext,
            persistence: persistence.persistence
        )
        let firstConnections = makeConnections()
        await firstConnections[1].failNextOpen()
        await firstConnections[2].failNextOpen()
        let firstPublisher = try makePublisher(
            fixture: fixture,
            journal: firstJournal,
            connections: firstConnections
        )
        let firstPublication = Task {
            try await firstPublisher.publish(
                fixture.giftWrap,
                binding: fixture.binding
            )
        }
        await firstConnections[0].waitUntilSentTextCount(1)
        await firstConnections[0].receive(
            acknowledgement(for: fixture.giftWrap, accepted: true)
        )
        await #expect(throws: Publisher.Failure.publicationInterrupted) {
            try await firstPublication.value
        }

        let durableSnapshot = try #require(persistence.snapshot)
        let prepared = try #require(
            durableSnapshot.records.compactMap { record -> Journal.Publication? in
                guard case let .prepared(batch) = record else {
                    return nil
                }
                return batch.publications.first
            }.first
        )
        #expect(
            durableSnapshot.context.attemptIdentifier
                == fixture.publicationContext.attemptIdentifier
        )
        #expect(
            durableSnapshot.context.generationIdentifier
                == fixture.publicationContext.generationIdentifier
        )
        #expect(
            durableSnapshot.context.materialIdentifier
                == fixture.publicationContext.materialIdentifier
        )
        #expect(
            durableSnapshot.context.roundIdentifier
                == Data(fixture.publicationContext.roundIdentifier)
        )
        #expect(
            durableSnapshot.context.manifestRelaySetDigest
                == Data(fixture.relaySelection.manifestRelaySetDigest)
        )
        #expect(prepared.binding == fixture.binding)
        #expect(
            prepared.eventIdentifier
                == fixture.giftWrap.event.identifier.rawRepresentation
        )
        #expect(prepared.endpoints == fixture.journalContext.endpoints)

        let restoredJournal = try Journal(
            context: fixture.journalContext,
            persistence: persistence.persistence
        )
        let continuation = try #require(
            restoredJournal.pendingContinuations(for: .control).first
        )
        #expect(continuation.relayAcknowledgements.count == 1)
        #expect(continuation.unresolvedEndpoints.count == 2)

        let restoredConnections = makeConnections()
        let restoredPublisher = try makePublisher(
            fixture: fixture,
            journal: restoredJournal,
            connections: restoredConnections
        )
        let restoration = Task {
            try await restoredPublisher.resume(continuation)
        }
        await restoredConnections[1].waitUntilSentTextCount(1)
        await restoredConnections[2].waitUntilSentTextCount(1)
        await restoredConnections[1].receive(
            acknowledgement(for: fixture.giftWrap, accepted: true)
        )
        try await restoration.value

        #expect(await restoredConnections[0].openCount == 0)
        let originalFrame = try #require(
            await firstConnections[0].sentTexts.first
        )
        #expect(
            await restoredConnections[1].sentTexts.first == originalFrame
        )
        #expect(
            await restoredConnections[2].sentTexts.first == originalFrame
        )

        let finalJournal = try Journal(
            context: fixture.journalContext,
            persistence: persistence.persistence
        )
        #expect(finalJournal.pendingContinuations(for: .control).isEmpty)
        let finalSnapshot = try #require(persistence.snapshot)
        #expect(finalSnapshot.records.contains {
            guard case let .completed(
                eventIdentifier,
                .transportAccepted
            ) = $0 else {
                return false
            }
            return eventIdentifier == prepared.eventIdentifier
        })
    }

    @Test("Replay a drained terminal publication without routes or journal mutation")
    func replayDrainedTerminalPublicationWithoutRoutes() async throws {
        let fixture = try await Self.sharedFixtureTask.value
        let persistence = MosaicMainnetAlphaRelayPublicationJournalFixture()
        let journal = try Journal(
            context: fixture.journalContext,
            persistence: persistence.persistence
        )
        let continuation = try journal.prepare(
            fixture.giftWrap,
            binding: fixture.binding
        )
        for endpoint in fixture.journalContext.endpoints.prefix(2) {
            try journal.recordAttempt(
                eventIdentifier:
                    continuation.publication.eventIdentifier,
                endpoint: endpoint
            )
            try journal.recordAcknowledgement(
                .accepted,
                eventIdentifier:
                    continuation.publication.eventIdentifier,
                endpoint: endpoint
            )
        }
        try journal.recordCompletion(
            .transportAccepted,
            eventIdentifier: continuation.publication.eventIdentifier
        )
        let snapshotBeforeReplay = try #require(persistence.snapshot)
        let recovery = try Journal.TerminalRecovery(journal: journal)

        await #expect(
            throws: Journal.TerminalRecovery.Failure.journalMismatch
        ) {
            try await recovery.replay(
                batchCount: 1,
                on: .control,
                to: [fixture.binding.recipientEventIdentity],
                expiringAt: fixture.binding.expiryUnixSeconds + 1
            )
        }
        #expect(await recovery.isComplete == false)

        try await recovery.replay(
            batchCount: 1,
            on: .control,
            to: [fixture.binding.recipientEventIdentity],
            expiringAt: fixture.binding.expiryUnixSeconds
        )
        #expect(await recovery.isComplete)
        #expect(persistence.snapshot == snapshotBeforeReplay)

        let partialPersistence =
            MosaicMainnetAlphaRelayPublicationJournalFixture()
        let partialJournal = try Journal(
            context: fixture.journalContext,
            persistence: partialPersistence.persistence
        )
        _ = try partialJournal.prepare(
            fixture.giftWrap,
            binding: fixture.binding
        )
        #expect(
            throws: Journal.TerminalRecovery.Failure.journalNotDrained
        ) {
            _ = try Journal.TerminalRecovery(journal: partialJournal)
        }
    }

    @Test("Reject mismatched context and invalid restored transitions")
    func rejectInvalidRestoredState() async throws {
        let fixture = try await Self.sharedFixtureTask.value
        let persistence = MosaicMainnetAlphaRelayPublicationJournalFixture()
        let journal = try Journal(
            context: fixture.journalContext,
            persistence: persistence.persistence
        )
        let continuation = try journal.prepare(
            fixture.giftWrap,
            binding: fixture.binding
        )
        let preparedSnapshot = try #require(persistence.snapshot)
        persistence.replaceSnapshot(
            .init(
                context: fixture.journalContext,
                records: preparedSnapshot.records + [
                    .acknowledged(
                        eventIdentifier:
                            continuation.publication.eventIdentifier,
                        endpoint: fixture.journalContext.endpoints[0],
                        .accepted
                    ),
                ]
            )
        )
        #expect(throws: Journal.InitializationError.invalidSnapshot) {
            _ = try Journal(
                context: fixture.journalContext,
                persistence: persistence.persistence
            )
        }

        persistence.replaceSnapshot(preparedSnapshot)
        let foreignContext = try Self.makePublicationContext(
            attemptByte: 0xA7
        )
        let foreignJournalContext = try Journal.Context(
            publicationContext: foreignContext,
            relaySelection: fixture.relaySelection
        )
        #expect(throws: Journal.InitializationError.loadFailed) {
            _ = try Journal(
                context: foreignJournalContext,
                persistence: persistence.persistence
            )
        }
    }

    @Test(
        "Mutate the durable publication recovery parser",
        .timeLimit(.minutes(1))
    )
    func mutateDurablePublicationRecoveryParser() async throws {
        let fixture = try await Self.sharedFixtureTask.value
        let context = fixture.journalContext
        let binding = try Runtime.Binding(
            attemptIdentifier: Data(
                context.attemptIdentifier.validatedBytes
            ),
            generationIdentifier: Data(
                context.generationIdentifier.opaqueBytes
            ),
            materialIdentifier: Data(
                context.materialIdentifier.opaqueBytes
            )
        )
        let persistenceStore = MosaicPrivateAlphaRuntimePersistenceStore()
        let persistence = Runtime.PostManifestPublicationPersistence(
            load: persistenceStore.load,
            compareAndSwap: persistenceStore.compareAndSwap
        )
        try Journal.initializeRecoverySnapshot(
            binding: binding,
            persistence: persistence,
            context: context,
            requireExisting: false
        )
        let journal = try Journal(
            context: context,
            persistence: Journal.recoveryPersistence(
                binding: binding,
                persistence: persistence
            )
        )
        let continuation = try journal.prepare(
            fixture.giftWrap,
            binding: fixture.binding
        )
        for endpoint in context.endpoints.prefix(2) {
            try journal.recordAttempt(
                eventIdentifier: continuation.publication.eventIdentifier,
                endpoint: endpoint
            )
            try journal.recordAcknowledgement(
                .accepted,
                eventIdentifier: continuation.publication.eventIdentifier,
                endpoint: endpoint
            )
        }
        try journal.recordCompletion(
            .transportAccepted,
            eventIdentifier: continuation.publication.eventIdentifier
        )
        let snapshot = try #require(persistenceStore.load(binding))

        try MosaicDeterministicParserMutationCampaign.validate(
            [
                .init(
                    name: "post-manifest publication journal snapshot",
                    seedBytes: Array(snapshot)
                ) { bytes in
                    try Journal.validateDrainedRecoveryReadback(
                        Data(bytes),
                        expectedContext: context
                    )
                },
            ],
            seed: 0x510E_527F_ADE6_82D2,
            seededMutationCount: 64
        )
    }

    private func verifyAppendReconciliation(
        boundary: AppendBoundary,
        durability: PublicationJournalFixture.AppendFailureDurability,
        fixture: SharedFixture
    ) throws {
        let persistence = PublicationJournalFixture()
        let journal = try Journal(
            context: fixture.journalContext,
            persistence: persistence.persistence
        )
        let eventIdentifier = fixture.giftWrap.event.identifier
            .rawRepresentation
        let endpoint = try #require(fixture.journalContext.endpoints.first)
        var baselineContinuation: Journal.Continuation?

        switch boundary {
        case .preparedBatch:
            break

        case .publicationPermit:
            baselineContinuation = try journal.prepare(
                fixture.giftWrap,
                binding: .init(
                    channelPurpose: .anonymousComponents,
                    recipientEventIdentity:
                        fixture.binding.recipientEventIdentity,
                    expiryUnixSeconds: fixture.binding.expiryUnixSeconds
                )
            )

        case .relayAttempt:
            baselineContinuation = try journal.prepare(
                fixture.giftWrap,
                binding: fixture.binding
            )

        case .relayAcknowledgement:
            let continuation = try journal.prepare(
                fixture.giftWrap,
                binding: fixture.binding
            )
            try journal.recordAttempt(
                eventIdentifier: eventIdentifier,
                endpoint: endpoint
            )
            baselineContinuation = try journal.currentContinuation(
                matching: continuation
            )

        case .completion:
            let continuation = try journal.prepare(
                fixture.giftWrap,
                binding: fixture.binding
            )
            for completionEndpoint in fixture.journalContext.endpoints.prefix(2) {
                try journal.recordAttempt(
                    eventIdentifier: eventIdentifier,
                    endpoint: completionEndpoint
                )
                try journal.recordAcknowledgement(
                    .accepted,
                    eventIdentifier: eventIdentifier,
                    endpoint: completionEndpoint
                )
            }
            baselineContinuation = try journal.currentContinuation(
                matching: continuation
            )
        }

        persistence.failNextAppend(
            of: boundary.appendKind,
            leaving: durability
        )
        var appendError: Journal.RecordingError?
        do {
            switch boundary {
            case .preparedBatch:
                _ = try journal.prepare(
                    fixture.giftWrap,
                    binding: fixture.binding
                )
            case .publicationPermit:
                try journal.recordPublicationPermit(
                    eventIdentifier: eventIdentifier
                )
            case .relayAttempt:
                try journal.recordAttempt(
                    eventIdentifier: eventIdentifier,
                    endpoint: endpoint
                )
            case .relayAcknowledgement:
                try journal.recordAcknowledgement(
                    .accepted,
                    eventIdentifier: eventIdentifier,
                    endpoint: endpoint
                )
            case .completion:
                try journal.recordCompletion(
                    .transportAccepted,
                    eventIdentifier: eventIdentifier
                )
            }
        } catch {
            appendError = error
        }

        let wasCommitted = durability == .appendedRecord
        #expect(appendError == (wasCommitted ? nil : .appendFailed))
        #expect(
            try hasInstalledTransition(
                boundary,
                in: journal,
                matching: baselineContinuation,
                eventIdentifier: eventIdentifier,
                endpoint: endpoint
            ) == wasCommitted
        )

        let restoredJournal = try Journal(
            context: fixture.journalContext,
            persistence: persistence.persistence
        )
        #expect(
            try hasInstalledTransition(
                boundary,
                in: restoredJournal,
                matching: baselineContinuation,
                eventIdentifier: eventIdentifier,
                endpoint: endpoint
            ) == wasCommitted
        )
    }

    private func hasInstalledTransition(
        _ boundary: AppendBoundary,
        in journal: Journal,
        matching baselineContinuation: Journal.Continuation?,
        eventIdentifier: Data,
        endpoint: Journal.Endpoint
    ) throws -> Bool {
        if boundary == .preparedBatch {
            return journal.pendingBatchContinuation(for: .control)?
                .batch.publications.contains {
                    $0.eventIdentifier == eventIdentifier
                } == true
        }
        let baseline = try #require(baselineContinuation)
        let current = try journal.currentContinuation(matching: baseline)
        switch boundary {
        case .preparedBatch:
            return false
        case .publicationPermit:
            return current.hasPublicationPermit
        case .relayAttempt:
            return current.attemptedEndpoints.contains(endpoint)
        case .relayAcknowledgement:
            return current.relayAcknowledgements[endpoint] == .accepted
        case .completion:
            return current.completion == .transportAccepted
        }
    }

    private static func makeSharedFixture() throws -> SharedFixture {
        let publicationContext = try makePublicationContext(attemptByte: 0xA1)
        let endpoints = selectedEndpoints
        let digest = publicationContext.manifest.core.relaySetDigest
        let relaySelection = try Alpha.PostManifestRelaySelectionValidation(
            manifestRelaySetDigest: digest,
            endpoints: endpoints,
            using: ExactRelaySelectionValidator(
                digest: digest,
                endpoints: Set(endpoints)
            )
        )
        let giftWrap = try makeGiftWrap()
        let recipientIdentity = try Nostr.EventCodec.decodeHexadecimal(
            giftWrap.event.template.tags[0][1],
            field: "p"
        )
        return try .init(
            publicationContext: publicationContext,
            relaySelection: relaySelection,
            journalContext: .init(
                publicationContext: publicationContext,
                relaySelection: relaySelection
            ),
            giftWrap: giftWrap,
            binding: .init(
                channelPurpose: .control,
                recipientEventIdentity: recipientIdentity,
                expiryUnixSeconds: 1_700_000_200
            ),
            codingLimits: relayLimits
        )
    }

    private static func makePublicationContext(
        attemptByte: UInt8
    ) throws -> Bridge.Context {
        let harness = try Fixture.makeHarness(localRole: .conductor)
        let bootstrap = Alpha.PostManifestRuntimeDriver.Bootstrap(
            validatedAttempt: Fixture.makeValidatedAttempt(
                election: harness.election
            ),
            attemptIdentifier: .init(
                validatedBytes: [UInt8](repeating: attemptByte, count: 32)
            ),
            generationIdentifier: .init(
                opaqueBytes: [UInt8](repeating: 0xA2, count: 32)
            ),
            materialIdentifier: .init(
                opaqueBytes: [UInt8](repeating: 0xA3, count: 32)
            ),
            localControlIdentity: harness.localControlIdentity,
            proposalValidation: harness.proposalValidation
        )
        return try .init(validating: harness.manifest, against: bootstrap)
    }

    private func makePublisher(
        fixture: SharedFixture,
        journal: Journal,
        connections: [ScriptedMosaicTorWebSocketConnection]
    ) throws -> Publisher {
        try .init(
            routes: zip(Self.selectedEndpoints, connections).map {
                .init(endpoint: $0.0, connection: $0.1)
            },
            relaySelection: fixture.relaySelection,
            publicationJournal: journal,
            codingLimits: fixture.codingLimits,
            maximumPendingRelayOutputCount: 4
        )
    }

    private func makeConnections()
        -> [ScriptedMosaicTorWebSocketConnection] {
        (0 ..< Alpha.relayCount).map { _ in
            ScriptedMosaicTorWebSocketConnection()
        }
    }

    private static var selectedEndpoints: [Tracker.Endpoint] {
        (1 ... Alpha.relayCount).map {
            .init(validatedIdentifier: "relay-\($0)")
        }
    }

    private static var relayLimits: Nostr.RelayMessageCodingLimits {
        get throws {
            try .init(
                maximumFrameByteCount:
                    Alpha.nip59MaximumPublicationFrameByteCount,
                maximumFiltersPerRequest: 1,
                maximumValuesPerFilter: 1,
                maximumMessageStringByteCount: 256,
                event: (try Transport.codingLimits).event
            )
        }
    }

    private static func makeGiftWrap() throws -> Publisher.GiftWrap {
        let sender = try signingKey(11)
        let recipient = try signingKey(12)
        let limits = try Transport.codingLimits
        let content = try OpalFusion.Mosaic.PaddedEnvelopeCodec.encode([0x01])
        let rumorTemplate = try Nostr.EventTemplate(
            createdAt: 1_700_000_100,
            kind: Alpha.nip59RumorKind,
            tags: [[
                "d",
                OpalFusion.Mosaic.TransportProfile
                    .nostrTorOpalMainnetAlpha.rawValue,
            ]],
            content: content,
            limits: limits.event
        )
        let rumor = try Nostr.UnsignedEvent(
            publicKey: sender.bip340VerificationKey,
            template: rumorTemplate,
            limits: limits.event
        )
        let seal = try Nostr.NIP59EnvelopeCodec.seal(
            rumor,
            createdAt: 1_700_000_090,
            senderSigningKey: sender,
            recipientPublicKey: recipient.bip340VerificationKey,
            limits: limits
        )
        return try .init(
            validating: Nostr.NIP59EnvelopeCodec.wrap(
                seal,
                deliveryKind: .regular,
                createdAt: 1_700_000_091,
                limits: limits
            )
        )
    }

    private static func signingKey(
        _ value: UInt8
    ) throws -> OpalCrypto.Secp256k1.SigningKey {
        try .init(
            rawRepresentation: Data(repeating: 0, count: 31) + Data([value])
        )
    }

    private func acknowledgement(
        for giftWrap: Publisher.GiftWrap,
        accepted: Bool
    ) -> OpalFusion.Mosaic.TorWebSocketMessage {
        let identifier = Nostr.EventCodec.hexadecimal(
            giftWrap.event.identifier.rawRepresentation
        )
        return .text(
            Data(
                ("[\"OK\",\"" + identifier + "\"," + String(accepted)
                    + ",\"relay\"]").utf8
            )
        )
    }
}

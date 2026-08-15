// MosaicMainnetAlphaPostManifestControlBatchPublisherValidator.swift

import Foundation
import OpalCrypto
import Testing
@testable import OpalFusion

@Suite("Mosaic mainnet-alpha control batch relay publication", .serialized)
struct MosaicMainnetAlphaPostManifestControlBatchPublisherValidator {
    typealias Alpha = OpalFusion.Mosaic.OpalMainnetAlpha
    typealias Attempt = OpalFusion.Mosaic.Attempt
    typealias Bridge = Alpha.PostManifestControlPublicationBridge
    typealias Journal = Alpha.PostManifestRelayPublicationJournal
    typealias ControlIdentity = Attempt.ControlIdentity
    typealias Fixture = MosaicMainnetAlphaAdmissionLedgerFixtures
    typealias Nostr = OpalFusion.Mosaic.NostrNamespace
    typealias Publisher = Alpha.PostManifestControlBatchPublisher
    typealias Tracker = OpalFusion.Mosaic.RelayPublicationTracker
    typealias Transport = Alpha.PostManifestNIP59Transport

    private static let currentUnixSeconds: UInt64 = 1_800_000_100
    private static let expiryUnixSeconds: UInt64 = 1_800_000_200

    private enum ProbeFailure: Error {
        case captured
        case injected
        case invalidRequests
        case missingBatch
    }

    private struct ExactRelaySelectionValidator:
        Alpha.PostManifestRelaySelectionValidating
    {
        let expectedDigest: [UInt8]
        let expectedEndpoints: Set<Tracker.Endpoint>

        func validateRelaySelection(
            manifestRelaySetDigest: [UInt8],
            endpoints: [Tracker.Endpoint]
        ) throws {
            guard manifestRelaySetDigest == expectedDigest,
                  Set(endpoints) == expectedEndpoints else {
                throw ProbeFailure.injected
            }
        }
    }

    private struct BridgeHarness {
        let context: Bridge.Context
        let controlSigningKey: OpalCrypto.Secp256k1.SigningKey
        let eventSigningKey: OpalCrypto.Secp256k1.SigningKey
        let recipients: [Bridge.Recipient]
    }

    private struct SharedFixture: Sendable {
        let harness: BridgeHarness
        let batch: Bridge.GiftWrapBatch
        let foreignBatches: [Bridge.GiftWrapBatch]
    }

    private static let sharedFixtureTask = Task {
        let harness = try Self.makeHarness()
        let foreignRecipients = try Self.makeRecipients(
            roster: harness.context.roster,
            scalarBase: 60
        )
        async let batch = Self.captureFirstBatch(harness: harness)
        async let foreignBatch = Self.captureFirstBatch(
            harness: harness,
            recipients: foreignRecipients
        )
        let foreignHarnesses = try [
            Self.makeHarness(attemptByte: 0xB1),
            Self.makeHarness(generationByte: 0xB2),
            Self.makeHarness(materialByte: 0xB3),
            Self.makeHarness(manifestAuxiliaryRandomnessByte: 0x5A),
        ]
        let foreignContextBatches = try await withThrowingTaskGroup(
            of: Bridge.GiftWrapBatch.self,
            returning: [Bridge.GiftWrapBatch].self
        ) { group in
            for foreignHarness in foreignHarnesses {
                group.addTask {
                    try await Self.captureFirstBatch(harness: foreignHarness)
                }
            }
            var batches: [Bridge.GiftWrapBatch] = []
            for try await capturedBatch in group {
                batches.append(capturedBatch)
            }
            return batches
        }
        return SharedFixture(
            harness: harness,
            batch: try await batch,
            foreignBatches: [try await foreignBatch] + foreignContextBatches
        )
    }

    private struct RouteAllocation {
        let groups: [Publisher.RecipientRouteGroup]
        let connections: [
            ControlIdentity: [ScriptedMosaicTorWebSocketConnection]
        ]
    }

    private actor BatchCapture {
        private var batches: [Bridge.GiftWrapBatch] = []

        func handoff(_ batch: Bridge.GiftWrapBatch) throws {
            batches.append(batch)
            throw ProbeFailure.captured
        }

        func first() -> Bridge.GiftWrapBatch? {
            batches.first
        }
    }

    private actor CompletionProbe {
        private(set) var isCompleted = false

        func markCompleted() {
            isCompleted = true
        }
    }

    private actor RouteProviderProbe {
        enum Behavior: Sendable {
            case provide
            case fail
            case throwCancellation
            case suspendUntilCancelled
        }

        private let expectedRequests: [Publisher.RecipientRouteRequest]
        private let groups: [Publisher.RecipientRouteGroup]
        private let behavior: Behavior
        private let suspension: MosaicRuntimeCoordinatorSuspensionProbe?
        private(set) var callCount = 0

        init(
            expectedRequests: [Publisher.RecipientRouteRequest],
            groups: [Publisher.RecipientRouteGroup],
            behavior: Behavior = .provide,
            suspension: MosaicRuntimeCoordinatorSuspensionProbe? = nil
        ) {
            self.expectedRequests = expectedRequests
            self.groups = groups
            self.behavior = behavior
            self.suspension = suspension
        }

        func provide(
            _ requests: [Publisher.RecipientRouteRequest]
        ) async throws -> [Publisher.RecipientRouteGroup] {
            callCount += 1
            guard requests == expectedRequests else {
                throw ProbeFailure.invalidRequests
            }
            switch behavior {
            case .provide:
                return groups
            case .fail:
                await Self.close(groups)
                throw ProbeFailure.injected
            case .throwCancellation:
                await Self.close(groups)
                throw CancellationError()
            case .suspendUntilCancelled:
                await suspension?.suspendIfArmed()
                guard !Task.isCancelled else {
                    await Self.close(groups)
                    throw CancellationError()
                }
                return groups
            }
        }

        private static func close(
            _ groups: [Publisher.RecipientRouteGroup]
        ) async {
            await withTaskGroup(of: Void.self) { group in
                for route in groups.flatMap(\.routes) {
                    group.addTask {
                        await route.connection.close()
                    }
                }
            }
        }
    }

    @Test("Reject incompatible manifest, recipient, and coding configuration")
    func rejectInvalidConfiguration() throws {
        let harness = try Self.makeHarness()
        let relaySelection = try makeRelaySelection(context: harness.context)
        let publicationJournal = try makePublicationJournal(
            context: harness.context,
            relaySelection: relaySelection
        )
        let provider: Publisher.RouteProvider = { _ in [] }

        #expect(
            throws: Publisher.InitializationError
                .manifestRelaySelectionMismatch
        ) {
            _ = try Publisher(
                context: harness.context,
                recipients: harness.recipients,
                relaySelection: makeRelaySelection(
                    context: harness.context,
                    digest: [UInt8](repeating: 0xFE, count: 32)
                ),
                publicationJournal: publicationJournal,
                codingLimits: relayLimits,
                maximumPendingRelayOutputCount: 4,
                provideRoutes: provider
            )
        }
        #expect(
            throws: Publisher.InitializationError.invalidRecipientCount(
                actual: harness.recipients.count - 1
            )
        ) {
            _ = try Publisher(
                context: harness.context,
                recipients: Array(harness.recipients.dropLast()),
                relaySelection: relaySelection,
                publicationJournal: publicationJournal,
                codingLimits: relayLimits,
                maximumPendingRelayOutputCount: 4,
                provideRoutes: provider
            )
        }

        var duplicateRecipient = harness.recipients
        duplicateRecipient[1] = .init(
            controlIdentity: duplicateRecipient[0].controlIdentity,
            eventVerificationKey: duplicateRecipient[1].eventVerificationKey
        )
        #expect(
            throws: Publisher.InitializationError.duplicateRecipient(
                duplicateRecipient[0].controlIdentity
            )
        ) {
            _ = try Publisher(
                context: harness.context,
                recipients: duplicateRecipient,
                relaySelection: relaySelection,
                publicationJournal: publicationJournal,
                codingLimits: relayLimits,
                maximumPendingRelayOutputCount: 4,
                provideRoutes: provider
            )
        }

        var foreignRecipient = harness.recipients
        foreignRecipient[foreignRecipient.count - 1] = .init(
            controlIdentity: Self.controlIdentity(
                signingKey: try Self.signingKey(90)
            ),
            eventVerificationKey: foreignRecipient.last!.eventVerificationKey
        )
        #expect(throws: Publisher.InitializationError.recipientSetMismatch) {
            _ = try Publisher(
                context: harness.context,
                recipients: foreignRecipient,
                relaySelection: relaySelection,
                publicationJournal: publicationJournal,
                codingLimits: relayLimits,
                maximumPendingRelayOutputCount: 4,
                provideRoutes: provider
            )
        }

        var duplicateEventIdentity = harness.recipients
        duplicateEventIdentity[1] = .init(
            controlIdentity: duplicateEventIdentity[1].controlIdentity,
            eventVerificationKey:
                duplicateEventIdentity[0].eventVerificationKey
        )
        #expect(
            throws: Publisher.InitializationError
                .duplicateRecipientEventIdentity
        ) {
            _ = try Publisher(
                context: harness.context,
                recipients: duplicateEventIdentity,
                relaySelection: relaySelection,
                publicationJournal: publicationJournal,
                codingLimits: relayLimits,
                maximumPendingRelayOutputCount: 4,
                provideRoutes: provider
            )
        }

        var reusedControlIdentity = harness.recipients
        reusedControlIdentity[0] = .init(
            controlIdentity: reusedControlIdentity[0].controlIdentity,
            eventVerificationKey: try .init(
                rawRepresentation: Data(
                    harness.context.roster.controlIdentities[1]
                        .validatedBytes
                )
            )
        )
        #expect(
            throws: Publisher.InitializationError
                .recipientEventIdentityReusesRosterControlIdentity
        ) {
            _ = try Publisher(
                context: harness.context,
                recipients: reusedControlIdentity,
                relaySelection: relaySelection,
                publicationJournal: publicationJournal,
                codingLimits: relayLimits,
                maximumPendingRelayOutputCount: 4,
                provideRoutes: provider
            )
        }

        #expect(throws: Publisher.InitializationError.invalidOutputBufferLimit) {
            _ = try Publisher(
                context: harness.context,
                recipients: harness.recipients,
                relaySelection: relaySelection,
                publicationJournal: publicationJournal,
                codingLimits: relayLimits,
                maximumPendingRelayOutputCount: 0,
                provideRoutes: provider
            )
        }
        let incompatibleEventLimits = try Nostr.EventCodingLimits(
            maximumEventJSONByteCount: Alpha.nip59MaximumGiftWrapJSONByteCount,
            maximumTagCount: 2,
            maximumTagElementCount: 2,
            maximumStringByteCount: Alpha.nip59GiftWrapContentByteCount
        )
        let incompatibleLimits = try Nostr.RelayMessageCodingLimits(
            maximumFrameByteCount: Alpha.nip59MaximumPublicationFrameByteCount,
            maximumFiltersPerRequest: 1,
            maximumValuesPerFilter: 1,
            maximumMessageStringByteCount: 256,
            event: incompatibleEventLimits
        )
        #expect(throws: Publisher.InitializationError.incompatibleCodingLimits) {
            _ = try Publisher(
                context: harness.context,
                recipients: harness.recipients,
                relaySelection: relaySelection,
                publicationJournal: publicationJournal,
                codingLimits: incompatibleLimits,
                maximumPendingRelayOutputCount: 4,
                provideRoutes: provider
            )
        }
    }

    @Test(
        "Preflight all routes and await every recipient closure",
        .timeLimit(.minutes(1))
    )
    func publishCompleteBatch() async throws {
        let fixture = try await Self.sharedFixtureTask.value
        let harness = fixture.harness
        let batch = fixture.batch
        let allocation = makeRouteAllocation(recipients: harness.recipients)
        let requests = routeRequests(harness.recipients)
        let probe = RouteProviderProbe(
            expectedRequests: requests,
            groups: allocation.groups.reversed()
        )
        let relaySelection = try makeRelaySelection(context: harness.context)
        let persistence =
            MosaicMainnetAlphaRelayPublicationJournalFixture()
        let publicationJournal = try Journal(
            context: .init(
                publicationContext: harness.context,
                relaySelection: relaySelection
            ),
            persistence: persistence.persistence
        )
        let publisher = try makePublisher(
            harness: harness,
            probe: probe,
            publicationJournal: publicationJournal
        )
        let completion = CompletionProbe()
        let finalConnection = try #require(
            allocation.connections[batch.recipients.last!.controlIdentity]?.last
        )
        await finalConnection.suspendNextClose()

        let publication = Task {
            try await publisher.publish(batch)
            await completion.markCompleted()
        }
        for recipient in batch.recipients {
            for connection in try #require(
                allocation.connections[recipient.controlIdentity]
            ) {
                await connection.waitUntilSentTextCount(1)
            }
        }

        let durableBatch = try #require(persistence.preparedBatches.first)
        #expect(persistence.preparedBatches.count == 1)
        #expect(durableBatch.channelPurpose == .control)
        #expect(durableBatch.publications.count == batch.recipients.count)
        #expect(
            Set(durableBatch.publications.map {
                $0.binding.recipientEventIdentity
            }) == Set(harness.recipients.map {
                $0.eventVerificationKey.rawRepresentation
            })
        )

        for recipient in batch.recipients {
            let connections = try #require(
                allocation.connections[recipient.controlIdentity]
            )
            await connections[0].receive(
                acknowledgement(for: recipient.giftWrap, accepted: true)
            )
            await connections[1].receive(
                acknowledgement(for: recipient.giftWrap, accepted: true)
            )
        }
        await finalConnection.waitUntilCloseSuspends()
        #expect(await completion.isCompleted == false)
        await finalConnection.resumeClose()
        try await publication.value

        #expect(await probe.callCount == 1)
        var firstFrames: Set<String> = []
        for recipient in batch.recipients {
            let connections = try #require(
                allocation.connections[recipient.controlIdentity]
            )
            var frames: [String] = []
            for connection in connections {
                let sent = await connection.sentTexts
                #expect(sent.count == 1)
                frames.append(try #require(sent.first))
                #expect(await connection.openCount == 1)
                #expect(await connection.closeCount == 1)
            }
            #expect(Set(frames).count == 1)
            firstFrames.insert(try #require(frames.first))
        }
        #expect(firstFrames.count == batch.recipients.count)

        let replayAllocation = makeRouteAllocation(
            recipients: harness.recipients
        )
        let replayProbe = RouteProviderProbe(
            expectedRequests: requests,
            groups: replayAllocation.groups
        )
        let replayPublisher = try makePublisher(
            harness: harness,
            probe: replayProbe,
            publicationJournal: publicationJournal
        )
        try await replayPublisher.publish(batch)
        #expect(await replayProbe.callCount == 0)
        for connections in replayAllocation.connections.values {
            for connection in connections {
                #expect(await connection.openCount == 0)
                #expect(await connection.closeCount == 0)
                #expect(await connection.sentTexts.isEmpty)
            }
        }
    }

    @Test("Reject an atomic batch append before any route opens")
    func rejectBatchAppendFailureBeforeRouteOpening() async throws {
        let fixture = try await Self.sharedFixtureTask.value
        let harness = fixture.harness
        let allocation = makeRouteAllocation(recipients: harness.recipients)
        let probe = RouteProviderProbe(
            expectedRequests: routeRequests(harness.recipients),
            groups: allocation.groups
        )
        let relaySelection = try makeRelaySelection(context: harness.context)
        let persistence =
            MosaicMainnetAlphaRelayPublicationJournalFixture()
        persistence.failNextAppend(
            of: .prepared,
            leaving: .priorSnapshot
        )
        let journal = try Journal(
            context: .init(
                publicationContext: harness.context,
                relaySelection: relaySelection
            ),
            persistence: persistence.persistence
        )
        let publisher = try makePublisher(
            harness: harness,
            probe: probe,
            publicationJournal: journal
        )

        await #expect(throws: Publisher.Failure.publicationJournalFailed) {
            try await publisher.publish(fixture.batch)
        }

        #expect(persistence.snapshot == nil)
        #expect(await probe.callCount == 0)
        for connections in allocation.connections.values {
            for connection in connections {
                #expect(await connection.openCount == 0)
                #expect(await connection.sentTexts.isEmpty)
                #expect(await connection.closeCount == 0)
            }
        }
    }

    @Test("Resume one durable control publication through fresh routes")
    func resumeDurableControlPublication() async throws {
        let fixture = try await Self.sharedFixtureTask.value
        let harness = fixture.harness
        let batch = fixture.batch
        let recipient = try #require(batch.recipients.first)
        let recipientEventIdentity = try #require(
            harness.recipients.first {
                $0.controlIdentity == recipient.controlIdentity
            }
        ).eventVerificationKey.rawRepresentation
        let relaySelection = try makeRelaySelection(context: harness.context)
        let persistence =
            MosaicMainnetAlphaRelayPublicationJournalFixture()
        let firstJournal = try Journal(
            context: .init(
                publicationContext: harness.context,
                relaySelection: relaySelection
            ),
            persistence: persistence.persistence
        )
        let durableBatch = try firstJournal.prepareBatch(
            try batch.recipients.map { batchRecipient in
                let eventIdentity = try #require(
                    harness.recipients.first {
                        $0.controlIdentity
                            == batchRecipient.controlIdentity
                    }
                ).eventVerificationKey.rawRepresentation
                return try .init(
                    giftWrap: batchRecipient.giftWrap,
                    binding: .init(
                        channelPurpose: .control,
                        recipientEventIdentity: eventIdentity,
                        expiryUnixSeconds:
                            batch.envelope.expiryUnixSeconds
                    )
                )
            }
        )
        for continuation in durableBatch.continuations
            where continuation.publication.binding.recipientEventIdentity
                != recipientEventIdentity {
            try firstJournal.recordCompletion(
                .cancelled,
                eventIdentifier: continuation.publication.eventIdentifier
            )
        }
        #expect(persistence.preparedBatches.count == 1)

        let restoredJournal = try Journal(
            context: .init(
                publicationContext: harness.context,
                relaySelection: relaySelection
            ),
            persistence: persistence.persistence
        )
        let allocation = makeRouteAllocation(recipients: harness.recipients)
        let probe = RouteProviderProbe(
            expectedRequests: routeRequests(harness.recipients),
            groups: allocation.groups
        )
        let publisher = try makePublisher(
            harness: harness,
            probe: probe,
            publicationJournal: restoredJournal
        )
        let restoration = Task {
            try await publisher.resumePendingPublications()
        }
        let recipientConnections = try #require(
            allocation.connections[recipient.controlIdentity]
        )
        for connection in recipientConnections {
            await connection.waitUntilSentTextCount(1)
        }
        await recipientConnections[0].receive(
            acknowledgement(for: recipient.giftWrap, accepted: true)
        )
        await recipientConnections[1].receive(
            acknowledgement(for: recipient.giftWrap, accepted: true)
        )
        try await restoration.value

        #expect(await probe.callCount == 1)
        for other in harness.recipients
            where other.controlIdentity != recipient.controlIdentity {
            for connection in try #require(
                allocation.connections[other.controlIdentity]
            ) {
                #expect(await connection.openCount == 0)
                #expect(await connection.closeCount == 1)
                #expect(await connection.sentTexts.isEmpty)
            }
        }
        #expect(
            restoredJournal.pendingContinuations(for: .control).isEmpty
        )
    }

    @Test(
        "Complete acknowledgement-derived recovery before routing",
        arguments: [
            Journal.Completion.transportAccepted,
            .transportRejected,
            .cancelled,
        ]
    )
    func completeAcknowledgementDerivedRecoveryBeforeRouting(
        completion: Journal.Completion
    ) async throws {
        let fixture = try await Self.sharedFixtureTask.value
        let harness = fixture.harness
        let relaySelection = try makeRelaySelection(context: harness.context)
        let persistence =
            MosaicMainnetAlphaRelayPublicationJournalFixture()
        let firstJournal = try Journal(
            context: .init(
                publicationContext: harness.context,
                relaySelection: relaySelection
            ),
            persistence: persistence.persistence
        )
        let durableBatch = try firstJournal.prepareBatch(
            try fixture.batch.recipients.map { recipient in
                let eventIdentity = try #require(
                    harness.recipients.first {
                        $0.controlIdentity == recipient.controlIdentity
                    }
                ).eventVerificationKey.rawRepresentation
                return try .init(
                    giftWrap: recipient.giftWrap,
                    binding: .init(
                        channelPurpose: .control,
                        recipientEventIdentity: eventIdentity,
                        expiryUnixSeconds:
                            fixture.batch.envelope.expiryUnixSeconds
                    )
                )
            }
        )
        let target = try #require(durableBatch.continuations.first)
        if completion == .cancelled {
            for continuation in durableBatch.continuations {
                try firstJournal.recordCompletion(
                    .cancelled,
                    eventIdentifier:
                        continuation.publication.eventIdentifier
                )
            }
        } else {
            let acknowledgement: Journal.RelayAcknowledgement =
                completion == .transportAccepted ? .accepted : .rejected
            for continuation in durableBatch.continuations {
                for endpoint in continuation.publication.endpoints.prefix(2) {
                    try firstJournal.recordAttempt(
                        eventIdentifier:
                            continuation.publication.eventIdentifier,
                        endpoint: endpoint
                    )
                    try firstJournal.recordAcknowledgement(
                        acknowledgement,
                        eventIdentifier:
                            continuation.publication.eventIdentifier,
                        endpoint: endpoint
                    )
                }
            }
        }

        let restoredJournal = try Journal(
            context: .init(
                publicationContext: harness.context,
                relaySelection: relaySelection
            ),
            persistence: persistence.persistence
        )
        let allocation = makeRouteAllocation(recipients: harness.recipients)
        let probe = RouteProviderProbe(
            expectedRequests: routeRequests(harness.recipients),
            groups: allocation.groups
        )
        let publisher = try makePublisher(
            harness: harness,
            probe: probe,
            publicationJournal: restoredJournal
        )

        if completion == .transportAccepted {
            try await publisher.publish(fixture.batch)
        } else {
            await #expect(
                throws: Publisher.Failure.recipientPublicationFailed
            ) {
                try await publisher.publish(fixture.batch)
            }
        }

        #expect(await probe.callCount == 0)
        for connections in allocation.connections.values {
            for connection in connections {
                #expect(await connection.openCount == 0)
                #expect(await connection.closeCount == 0)
                #expect(await connection.sentTexts.isEmpty)
            }
        }
        #expect(
            restoredJournal.pendingContinuations(for: .control).isEmpty
        )
        let snapshot = try #require(persistence.snapshot)
        #expect(snapshot.records.contains { record in
            guard case let .completed(eventIdentifier, durableCompletion) =
                    record else {
                return false
            }
            return eventIdentifier == target.publication.eventIdentifier
                && durableCompletion == completion
        })
    }

    @Test("Reject a restored control record with partial batch membership")
    func rejectPartialRestoredBatchBeforeRouting() async throws {
        let fixture = try await Self.sharedFixtureTask.value
        let harness = fixture.harness
        let batch = fixture.batch
        let relaySelection = try makeRelaySelection(context: harness.context)
        let journalContext = try Journal.Context(
            publicationContext: harness.context,
            relaySelection: relaySelection
        )
        let persistence =
            MosaicMainnetAlphaRelayPublicationJournalFixture()
        let journal = try Journal(
            context: journalContext,
            persistence: persistence.persistence
        )
        _ = try journal.prepareBatch(
            try batch.recipients.map { recipient in
                let eventIdentity = try #require(
                    harness.recipients.first {
                        $0.controlIdentity == recipient.controlIdentity
                    }
                ).eventVerificationKey.rawRepresentation
                return try .init(
                    giftWrap: recipient.giftWrap,
                    binding: .init(
                        channelPurpose: .control,
                        recipientEventIdentity: eventIdentity,
                        expiryUnixSeconds:
                            batch.envelope.expiryUnixSeconds
                    )
                )
            }
        )
        let durableBatch = try #require(persistence.preparedBatches.first)
        persistence.replaceSnapshot(.init(
            context: journalContext,
            records: [
                .prepared(.init(
                    channelPurpose: .control,
                    publications: Array(
                        durableBatch.publications.dropLast()
                    )
                )),
            ]
        ))

        let restoredJournal = try Journal(
            context: journalContext,
            persistence: persistence.persistence
        )
        let allocation = makeRouteAllocation(recipients: harness.recipients)
        let probe = RouteProviderProbe(
            expectedRequests: routeRequests(harness.recipients),
            groups: allocation.groups
        )
        let publisher = try makePublisher(
            harness: harness,
            probe: probe,
            publicationJournal: restoredJournal
        )

        await #expect(throws: Publisher.Failure.invalidContinuationSet) {
            try await publisher.resumePendingPublications()
        }
        #expect(await probe.callCount == 0)
        for connections in allocation.connections.values {
            for connection in connections {
                #expect(await connection.openCount == 0)
                #expect(await connection.closeCount == 0)
            }
        }
    }

    @Test("Reject foreign bridge batches before routing")
    func rejectForeignBatches() async throws {
        let fixture = try await Self.sharedFixtureTask.value
        let harness = fixture.harness
        let allocation = makeRouteAllocation(recipients: harness.recipients)
        let probe = RouteProviderProbe(
            expectedRequests: routeRequests(harness.recipients),
            groups: allocation.groups
        )
        let publisher = try makePublisher(harness: harness, probe: probe)

        for foreignBatch in fixture.foreignBatches {
            await #expect(throws: Publisher.Failure.batchContextMismatch) {
                try await publisher.publish(foreignBatch)
            }
        }
        #expect(await probe.callCount == 0)
        for connections in allocation.connections.values {
            for connection in connections {
                #expect(await connection.openCount == 0)
                #expect(await connection.closeCount == 0)
            }
        }
    }

    @Test("Reject cross-recipient connection reuse before sending")
    func rejectConnectionReuse() async throws {
        let fixture = try await Self.sharedFixtureTask.value
        let harness = fixture.harness
        let batch = fixture.batch
        let allocation = makeRouteAllocation(recipients: harness.recipients)
        var groups = allocation.groups
        let reusedConnection = try #require(
            allocation.connections[harness.recipients[0].controlIdentity]?.first
        )
        let secondIdentity = harness.recipients[1].controlIdentity
        let replacedConnection = try #require(
            allocation.connections[secondIdentity]?.first
        )
        var secondRoutes = groups[1].routes
        secondRoutes[0] = .init(
            endpoint: secondRoutes[0].endpoint,
            connection: reusedConnection
        )
        groups[1] = .init(
            recipientEventIdentity: harness.recipients[1]
                .eventVerificationKey.rawRepresentation,
            routes: secondRoutes
        )
        let probe = RouteProviderProbe(
            expectedRequests: routeRequests(harness.recipients),
            groups: groups
        )
        let publisher = try makePublisher(harness: harness, probe: probe)

        await #expect(throws: Publisher.Failure.duplicateConnection) {
            try await publisher.publish(batch)
        }
        for connections in allocation.connections.values {
            for connection in connections {
                #expect(await connection.openCount == 0)
                #expect(
                    await connection.closeCount
                        == (connection === replacedConnection ? 0 : 1)
                )
            }
        }
    }

    @Test("Close every returned route when one publisher cannot be constructed")
    func rejectInvalidRecipientRoutes() async throws {
        let fixture = try await Self.sharedFixtureTask.value
        let harness = fixture.harness
        let batch = fixture.batch

        let incompleteAllocation = makeRouteAllocation(
            recipients: harness.recipients
        )
        let incompleteGroups = Array(incompleteAllocation.groups.dropLast())
        let incompleteProbe = RouteProviderProbe(
            expectedRequests: routeRequests(harness.recipients),
            groups: incompleteGroups
        )
        let incompletePublisher = try makePublisher(
            harness: harness,
            probe: incompleteProbe
        )
        await #expect(throws: Publisher.Failure.routeAllocationMismatch) {
            try await incompletePublisher.publish(batch)
        }
        let returnedEventIdentities = Set(
            incompleteGroups.map(\.recipientEventIdentity)
        )
        for (identity, connections) in incompleteAllocation.connections {
            let recipient = try #require(
                harness.recipients.first { $0.controlIdentity == identity }
            )
            for connection in connections {
                #expect(await connection.openCount == 0)
                #expect(
                    await connection.closeCount
                        == (returnedEventIdentities.contains(
                            recipient.eventVerificationKey.rawRepresentation
                        ) ? 1 : 0)
                )
            }
        }

        let allocation = makeRouteAllocation(recipients: harness.recipients)
        var groups = allocation.groups
        let last = groups.removeLast()
        let omittedConnection = try #require(
            allocation.connections[harness.recipients.last!.controlIdentity]?
                .last
        )
        groups.append(
            .init(
                recipientEventIdentity: last.recipientEventIdentity,
                routes: Array(last.routes.dropLast())
            )
        )
        let probe = RouteProviderProbe(
            expectedRequests: routeRequests(harness.recipients),
            groups: groups
        )
        let publisher = try makePublisher(harness: harness, probe: probe)

        await #expect(throws: Publisher.Failure.publisherConstructionFailed) {
            try await publisher.publish(batch)
        }
        for connections in allocation.connections.values {
            for connection in connections {
                #expect(await connection.openCount == 0)
                #expect(
                    await connection.closeCount
                        == (connection === omittedConnection ? 0 : 1)
                )
            }
        }
    }

    @Test("Map provider failure without exposing publishable events")
    func rejectRouteProvisioningFailure() async throws {
        let fixture = try await Self.sharedFixtureTask.value
        let harness = fixture.harness
        let batch = fixture.batch
        let allocation = makeRouteAllocation(recipients: harness.recipients)
        let requests = routeRequests(harness.recipients)
        let failingProbe = RouteProviderProbe(
            expectedRequests: requests,
            groups: allocation.groups,
            behavior: .fail
        )
        let failingPublisher = try makePublisher(
            harness: harness,
            probe: failingProbe
        )

        await #expect(throws: Publisher.Failure.routeProvisioningFailed) {
            try await failingPublisher.publish(batch)
        }
        for connections in allocation.connections.values {
            for connection in connections {
                #expect(await connection.openCount == 0)
                #expect(await connection.closeCount == 1)
            }
        }

        let cancellationAllocation = makeRouteAllocation(
            recipients: harness.recipients
        )
        let localCancellationProbe = RouteProviderProbe(
            expectedRequests: requests,
            groups: cancellationAllocation.groups,
            behavior: .throwCancellation
        )
        let localCancellationPublisher = try makePublisher(
            harness: harness,
            probe: localCancellationProbe
        )
        await #expect(throws: Publisher.Failure.routeProvisioningFailed) {
            try await localCancellationPublisher.publish(batch)
        }
    }

    @Test(
        "Cancel responsive route provisioning without sending",
        .timeLimit(.minutes(1))
    )
    func cancelRouteProvisioning() async throws {
        let fixture = try await Self.sharedFixtureTask.value
        let harness = fixture.harness
        let batch = fixture.batch
        let allocation = makeRouteAllocation(recipients: harness.recipients)
        let suspension = MosaicRuntimeCoordinatorSuspensionProbe()
        await suspension.arm()
        let probe = RouteProviderProbe(
            expectedRequests: routeRequests(harness.recipients),
            groups: allocation.groups,
            behavior: .suspendUntilCancelled,
            suspension: suspension
        )
        let publisher = try makePublisher(harness: harness, probe: probe)
        let publication = Task { try await publisher.publish(batch) }
        await suspension.waitUntilSuspended()

        publication.cancel()
        await #expect(throws: Publisher.Failure.cancelled) {
            try await publication.value
        }
        for connections in allocation.connections.values {
            for connection in connections {
                #expect(await connection.openCount == 0)
                #expect(await connection.closeCount == 1)
                #expect(await connection.sentTexts.isEmpty)
            }
        }
    }

    @Test("Cancellation before control publication writes no durable batch")
    func cancelBeforeDurableControlBatch() async throws {
        let fixture = try await Self.sharedFixtureTask.value
        let harness = fixture.harness
        let allocation = makeRouteAllocation(recipients: harness.recipients)
        let probe = RouteProviderProbe(
            expectedRequests: routeRequests(harness.recipients),
            groups: allocation.groups
        )
        let relaySelection = try makeRelaySelection(context: harness.context)
        let persistence =
            MosaicMainnetAlphaRelayPublicationJournalFixture()
        let journal = try Journal(
            context: .init(
                publicationContext: harness.context,
                relaySelection: relaySelection
            ),
            persistence: persistence.persistence
        )
        let publisher = try makePublisher(
            harness: harness,
            probe: probe,
            publicationJournal: journal
        )
        let suspension = MosaicRuntimeCoordinatorSuspensionProbe()
        await suspension.arm()
        let publication = Task {
            await suspension.suspendIfArmed()
            try await publisher.publish(fixture.batch)
        }
        await suspension.waitUntilSuspended()
        publication.cancel()
        await suspension.resume()

        await #expect(throws: Publisher.Failure.cancelled) {
            try await publication.value
        }
        #expect(persistence.snapshot == nil)
        #expect(await probe.callCount == 0)
        for connections in allocation.connections.values {
            for connection in connections {
                #expect(await connection.openCount == 0)
                #expect(await connection.closeCount == 0)
                #expect(await connection.sentTexts.isEmpty)
            }
        }
    }

    @Test(
        "Cancel sibling recipients when one cannot reach quorum",
        .timeLimit(.minutes(1))
    )
    func rejectRecipientQuorumFailure() async throws {
        let fixture = try await Self.sharedFixtureTask.value
        let harness = fixture.harness
        let batch = fixture.batch
        let allocation = makeRouteAllocation(recipients: harness.recipients)
        let probe = RouteProviderProbe(
            expectedRequests: routeRequests(harness.recipients),
            groups: allocation.groups
        )
        let publisher = try makePublisher(harness: harness, probe: probe)
        let completion = CompletionProbe()
        let publication = Task { () -> Publisher.Failure? in
            do {
                try await publisher.publish(batch)
                await completion.markCompleted()
                return nil
            } catch let failure as Publisher.Failure {
                await completion.markCompleted()
                return failure
            } catch {
                await completion.markCompleted()
                Issue.record("Unexpected publication error: \(error)")
                return nil
            }
        }

        for recipient in batch.recipients {
            for connection in try #require(
                allocation.connections[recipient.controlIdentity]
            ) {
                await connection.waitUntilSentTextCount(1)
            }
        }
        let rejectedRecipient = batch.recipients[0]
        let rejectedConnections = try #require(
            allocation.connections[rejectedRecipient.controlIdentity]
        )
        let suspendedSiblingConnection = try #require(
            allocation.connections[batch.recipients[1].controlIdentity]?.first
        )
        await suspendedSiblingConnection.suspendNextClose()
        await rejectedConnections[0].receive(
            acknowledgement(for: rejectedRecipient.giftWrap, accepted: true)
        )
        await rejectedConnections[1].receive(
            acknowledgement(for: rejectedRecipient.giftWrap, accepted: false)
        )
        await rejectedConnections[2].receive(
            acknowledgement(for: rejectedRecipient.giftWrap, accepted: false)
        )

        await suspendedSiblingConnection.waitUntilCloseSuspends()
        #expect(await completion.isCompleted == false)
        await suspendedSiblingConnection.resumeClose()
        #expect(
            await publication.value
                == Publisher.Failure.recipientPublicationFailed
        )
        for connections in allocation.connections.values {
            for connection in connections {
                #expect(await connection.closeCount == 1)
            }
        }
    }

    @Test(
        "Cancel active recipient publications and drain all closures",
        .timeLimit(.minutes(1))
    )
    func cancelActivePublication() async throws {
        let fixture = try await Self.sharedFixtureTask.value
        let harness = fixture.harness
        let batch = fixture.batch
        let allocation = makeRouteAllocation(recipients: harness.recipients)
        let probe = RouteProviderProbe(
            expectedRequests: routeRequests(harness.recipients),
            groups: allocation.groups
        )
        let publisher = try makePublisher(harness: harness, probe: probe)
        let publication = Task { try await publisher.publish(batch) }
        for recipient in batch.recipients {
            for connection in try #require(
                allocation.connections[recipient.controlIdentity]
            ) {
                await connection.waitUntilSentTextCount(1)
            }
        }

        publication.cancel()
        await #expect(throws: Publisher.Failure.cancelled) {
            try await publication.value
        }
        for connections in allocation.connections.values {
            for connection in connections {
                #expect(await connection.closeCount == 1)
            }
        }
    }

    private var relayLimits: Nostr.RelayMessageCodingLimits {
        get throws {
            try .init(
                maximumFrameByteCount: Alpha.nip59MaximumPublicationFrameByteCount,
                maximumFiltersPerRequest: 1,
                maximumValuesPerFilter: 1,
                maximumMessageStringByteCount: 256,
                event: (try Transport.codingLimits).event
            )
        }
    }

    private func makePublisher(
        harness: BridgeHarness,
        probe: RouteProviderProbe,
        publicationJournal: Journal? = nil
    ) throws -> Publisher {
        let relaySelection = try makeRelaySelection(context: harness.context)
        return try .init(
            context: harness.context,
            recipients: harness.recipients,
            relaySelection: relaySelection,
            publicationJournal: publicationJournal
                ?? makePublicationJournal(
                    context: harness.context,
                    relaySelection: relaySelection
                ),
            codingLimits: relayLimits,
            maximumPendingRelayOutputCount: 4,
            provideRoutes: { requests in
                try await probe.provide(requests)
            }
        )
    }

    private func makePublicationJournal(
        context: Bridge.Context,
        relaySelection: Alpha.PostManifestRelaySelectionValidation
    ) throws -> Journal {
        try .init(
            context: .init(
                publicationContext: context,
                relaySelection: relaySelection
            ),
            persistence: .init(
                loadSnapshot: { _ in nil },
                appendRecord: { _, _, _ in }
            )
        )
    }

    private static func makeHarness(
        attemptByte: UInt8 = 0xA1,
        generationByte: UInt8 = 0xA2,
        materialByte: UInt8 = 0xA3,
        manifestAuxiliaryRandomnessByte: UInt8? = nil
    ) throws -> BridgeHarness {
        let ledgerHarness = try Fixture.makeHarness(localRole: .conductor)
        let scalar = try #require(
            MosaicMainnetAlphaFixtures.scalarByte(
                for: ledgerHarness.localControlIdentity
            )
        )
        let controlSigningKey = try Self.signingKey(scalar)
        let eventSigningKey = try Self.signingKey(20)
        let manifest: Alpha.RoundManifest
        if let manifestAuxiliaryRandomnessByte {
            let temporaryBinding = try Attempt.ManifestBinding(
                validatedRoundIdentifier:
                    ledgerHarness.manifest.core.roundIdentifier,
                validatedManifestDigest: [UInt8](repeating: 0, count: 32)
            )
            manifest = try .init(
                core: ledgerHarness.manifest.core,
                signatures: MosaicManifestSignatureFixtures.manifestSignatures(
                    for: ledgerHarness.manifest.core.roster,
                    binding: temporaryBinding,
                    auxiliaryRandomnessByte:
                        manifestAuxiliaryRandomnessByte
                )
            )
        } else {
            manifest = ledgerHarness.manifest
        }
        let bootstrap = Alpha.PostManifestRuntimeDriver.Bootstrap(
            validatedAttempt: Fixture.makeValidatedAttempt(
                election: ledgerHarness.election
            ),
            attemptIdentifier: .init(
                validatedBytes: [UInt8](repeating: attemptByte, count: 32)
            ),
            generationIdentifier: .init(
                opaqueBytes: [UInt8](repeating: generationByte, count: 32)
            ),
            materialIdentifier: .init(
                opaqueBytes: [UInt8](repeating: materialByte, count: 32)
            ),
            localControlIdentity: ledgerHarness.localControlIdentity,
            proposalValidation: ledgerHarness.proposalValidation
        )
        let context = try Bridge.Context(
            validating: manifest,
            against: bootstrap
        )
        return .init(
            context: context,
            controlSigningKey: controlSigningKey,
            eventSigningKey: eventSigningKey,
            recipients: try Self.makeRecipients(
                roster: context.roster,
                scalarBase: 30
            )
        )
    }

    private static func makeRecipients(
        roster: Attempt.Roster,
        scalarBase: UInt8
    ) throws -> [Bridge.Recipient] {
        try roster.controlIdentities.enumerated().map { index, identity in
            .init(
                controlIdentity: identity,
                eventVerificationKey: try Self.signingKey(
                    scalarBase + UInt8(index)
                ).bip340VerificationKey
            )
        }
    }

    private static func captureFirstBatch(
        harness: BridgeHarness,
        recipients: [Bridge.Recipient]? = nil
    ) async throws -> Bridge.GiftWrapBatch {
        let capture = BatchCapture()
        let bridge = try Bridge(
            context: harness.context,
            controlSigningKey: harness.controlSigningKey,
            eventSigningKey: harness.eventSigningKey,
            recipients: recipients ?? harness.recipients,
            dependencies: .init(
                makeLayerTimestamps: { _ in
                    try .init(
                        phaseStartUnixSeconds:
                            harness.context.phaseStartUnixSeconds,
                        currentUnixSeconds: Self.currentUnixSeconds,
                        sealCreatedAt: Self.currentUnixSeconds - 2,
                        giftWrapCreatedAt: Self.currentUnixSeconds - 1
                    )
                },
                makeSignatureAuxiliaryRandomness: {
                    try .init(
                        rawRepresentation: Data(repeating: 0xA5, count: 32)
                    )
                },
                handoffGiftWrapBatch: { batch in
                    try await capture.handoff(batch)
                }
            )
        )
        do {
            try await bridge.publishManifest(
                expiryUnixSeconds: Self.expiryUnixSeconds
            )
        } catch let failure as Bridge.Failure {
            guard failure == .handoffFailed else {
                throw failure
            }
        }
        guard let batch = await capture.first() else {
            throw ProbeFailure.missingBatch
        }
        return batch
    }

    private func routeRequests(
        _ recipients: [Bridge.Recipient]
    ) -> [Publisher.RecipientRouteRequest] {
        recipients.map {
            .init(
                recipientEventIdentity:
                    $0.eventVerificationKey.rawRepresentation
            )
        }.sorted {
            $0.recipientEventIdentity.lexicographicallyPrecedes(
                $1.recipientEventIdentity
            )
        }
    }

    private func makeRouteAllocation(
        recipients: [Bridge.Recipient]
    ) -> RouteAllocation {
        var connectionsByIdentity: [
            ControlIdentity: [ScriptedMosaicTorWebSocketConnection]
        ] = [:]
        let groups = recipients.map { recipient in
            let connections = (0 ..< Alpha.relayCount).map { _ in
                ScriptedMosaicTorWebSocketConnection()
            }
            connectionsByIdentity[recipient.controlIdentity] = connections
            return Publisher.RecipientRouteGroup(
                recipientEventIdentity:
                    recipient.eventVerificationKey.rawRepresentation,
                routes: zip(selectedEndpoints, connections).map {
                    .init(endpoint: $0.0, connection: $0.1)
                }
            )
        }
        return .init(groups: groups, connections: connectionsByIdentity)
    }

    private func makeRelaySelection(
        context: Bridge.Context,
        digest: [UInt8]? = nil
    ) throws -> Alpha.PostManifestRelaySelectionValidation {
        let effectiveDigest = digest ?? context.manifest.core.relaySetDigest
        return try .init(
            manifestRelaySetDigest: effectiveDigest,
            endpoints: selectedEndpoints,
            using: ExactRelaySelectionValidator(
                expectedDigest: effectiveDigest,
                expectedEndpoints: Set(selectedEndpoints)
            )
        )
    }

    private var selectedEndpoints: [Tracker.Endpoint] {
        (1 ... Alpha.relayCount).map {
            .init(validatedIdentifier: "relay-\($0)")
        }
    }

    private func acknowledgement(
        for giftWrap: Alpha.PostManifestRelayPublisher.GiftWrap,
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

    private static func signingKey(
        _ scalarByte: UInt8
    ) throws -> OpalCrypto.Secp256k1.SigningKey {
        try .init(
            rawRepresentation: Data(repeating: 0, count: 31)
                + Data([scalarByte])
        )
    }

    private static func controlIdentity(
        signingKey: OpalCrypto.Secp256k1.SigningKey
    ) -> ControlIdentity {
        .init(
            validatedBytes: Array(
                signingKey.bip340VerificationKey.rawRepresentation
            )
        )
    }
}

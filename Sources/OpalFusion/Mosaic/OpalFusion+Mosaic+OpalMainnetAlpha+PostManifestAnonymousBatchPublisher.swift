// OpalFusion+Mosaic+OpalMainnetAlpha+PostManifestAnonymousBatchPublisher.swift

import Foundation

extension OpalFusion.Mosaic.OpalMainnetAlpha {
    /// Publishes one material-bound anonymous phase batch through injected Tor-only routes.
    ///
    /// The value obtains and validates the complete route allocation and durably prepares the
    /// complete batch in one journal append before opening any route. Each recipient still awaits
    /// and durably records its caller-owned publication permit before its route opens. Endpoint
    /// and Tor provisioning, timing policy, durable-storage implementation, retry policy, and
    /// semantic loopback remain external.
    struct PostManifestAnonymousBatchPublisher: Sendable {
        typealias Batch = PostManifestAnonymousPublicationBridge.GiftWrapBatch
        typealias Context = PostManifestAnonymousPublicationBridge.Context
        typealias MaterialBinding = PostManifestAnonymousPublicationBridge
            .MaterialBinding
        typealias PublicationKind = PostManifestAnonymousPublicationBridge
            .PublicationKind
        typealias Nostr = OpalFusion.Mosaic.NostrNamespace
        typealias PublicationJournal = PostManifestRelayPublicationJournal
        typealias RecipientRouteRequest =
            PostManifestPublicationRouteAllocation.RecipientRouteRequest
        typealias RecipientRouteGroup =
            PostManifestPublicationRouteAllocation.RecipientRouteGroup

        struct PublicationPermitRequest: Sendable, Equatable {
            let kind: PublicationKind
            let recipientEventIdentity: Data
        }

        enum InitializationError: Error, Sendable, Equatable {
            case localPeerIsNotContributor
            case localMaterialMismatch
            case manifestRelaySelectionMismatch
            case publicationJournalMismatch
            case incompatibleCodingLimits
            case invalidOutputBufferLimit
        }

        enum Failure: Error, Sendable, Equatable {
            case batchContextMismatch
            case routeProvisioningFailed
            case routeAllocationMismatch
            case duplicateConnection
            case publisherConstructionFailed
            case publicationJournalFailed
            case invalidContinuationSet
            case publicationPermitFailed
            case recipientPublicationFailed
            case cancelled
        }

        /// Provides one complete route allocation without receiving publishable event bytes.
        ///
        /// The provider must promptly honor cancellation and close any partially allocated routes
        /// before throwing. Every completed invocation must supply fresh anonymous capabilities
        /// that do not reuse control, component, or signature circuits. This value can enforce
        /// only in-process connection-object uniqueness within the returned batch. Once a complete
        /// allocation is returned, it owns every route.
        typealias RouteProvider = @Sendable (
            [RecipientRouteRequest]
        ) async throws -> [RecipientRouteGroup]

        /// Purpose-aware route allocation used by the attempt transport owner.
        ///
        /// The publication kind lets one peer-local owner reject circuit reuse across its
        /// component and BCH-signature branches without exposing signed event bytes.
        typealias PurposefulRouteProvider = @Sendable (
            PublicationKind,
            [RecipientRouteRequest]
        ) async throws -> [RecipientRouteGroup]

        /// Supplies caller-owned timing authority for one already-bound anonymous recipient.
        ///
        /// The provider must promptly honor cancellation. A permit defines neither a scheduling
        /// policy nor a privacy guarantee; callers retain both responsibilities.
        typealias PublicationPermitProvider = @Sendable (
            PublicationPermitRequest
        ) async throws -> Void

        private struct PublicationPreparation: Sendable {
            let permitRequest: PublicationPermitRequest
            let giftWrap: PostManifestRelayPublisher.GiftWrap
            let binding: PublicationJournal.PublicationBinding
            let publisher: PostManifestRelayPublisher
        }

        private struct PreparedPublication: Sendable {
            let permitRequest: PublicationPermitRequest
            let continuation: PublicationJournal.Continuation
            let publisher: PostManifestRelayPublisher
        }

        private enum PublicationTaskResult: Sendable, Equatable {
            case completed
            case permitFailed
            case journalFailed
            case recipientFailed
            case cancelled
        }

        private let context: Context
        private let expectedMaterialBinding: MaterialBinding
        private let componentRecipientIdentities: [Data]
        private let signatureRecipientIdentities: [Data]
        private let relaySelection: PostManifestRelaySelectionValidation
        private let publicationJournal: PublicationJournal
        private let codingLimits: Nostr.RelayMessageCodingLimits
        private let maximumPendingRelayOutputCount: Int
        private let provideRoutes: PurposefulRouteProvider
        private let awaitPublicationPermit: PublicationPermitProvider

        init(
            context: Context,
            material: LocalContributionMaterial,
            relaySelection: PostManifestRelaySelectionValidation,
            publicationJournal: PublicationJournal,
            codingLimits: Nostr.RelayMessageCodingLimits,
            maximumPendingRelayOutputCount: Int,
            provideRoutes: @escaping RouteProvider,
            awaitPublicationPermit: @escaping PublicationPermitProvider
        ) throws(InitializationError) {
            try self.init(
                context: context,
                material: material,
                relaySelection: relaySelection,
                publicationJournal: publicationJournal,
                codingLimits: codingLimits,
                maximumPendingRelayOutputCount:
                    maximumPendingRelayOutputCount,
                provideRoutesForPublication: { _, requests in
                    try await provideRoutes(requests)
                },
                awaitPublicationPermit: awaitPublicationPermit
            )
        }

        init(
            context: Context,
            material: LocalContributionMaterial,
            relaySelection: PostManifestRelaySelectionValidation,
            publicationJournal: PublicationJournal,
            codingLimits: Nostr.RelayMessageCodingLimits,
            maximumPendingRelayOutputCount: Int,
            provideRoutesForPublication: @escaping PurposefulRouteProvider,
            awaitPublicationPermit: @escaping PublicationPermitProvider
        ) throws(InitializationError) {
            guard context.roster.contributors.contains(
                context.localControlIdentity
            ) else {
                throw .localPeerIsNotContributor
            }
            guard context.attemptIdentifier == material.attemptIdentifier,
                  context.generationIdentifier
                    == material.generationIdentifier,
                  context.materialIdentifier == material.materialIdentifier,
                  context.localControlIdentity == material.contributor,
                  context.manifest == material.manifest else {
                throw .localMaterialMismatch
            }
            guard relaySelection.manifestRelaySetDigest
                    == context.manifest.core.relaySetDigest else {
                throw .manifestRelaySelectionMismatch
            }
            guard publicationJournal.isBound(
                to: context,
                relaySelection: relaySelection
            ) else {
                throw .publicationJournalMismatch
            }
            guard maximumPendingRelayOutputCount > 0 else {
                throw .invalidOutputBufferLimit
            }
            do {
                let transportLimits = try PostManifestNIP59Transport
                    .codingLimits
                guard codingLimits.event == transportLimits.event,
                      codingLimits.maximumFrameByteCount
                        >= nip59MaximumPublicationFrameByteCount else {
                    throw InitializationError.incompatibleCodingLimits
                }
            } catch let error as InitializationError {
                throw error
            } catch {
                throw .incompatibleCodingLimits
            }

            self.context = context
            expectedMaterialBinding = .init(material: material)
            componentRecipientIdentities = material.slots.map {
                Data($0.recipientEventIdentity)
            }
            signatureRecipientIdentities = material.slots.compactMap { slot in
                guard case .input = slot.component.payload else { return nil }
                return Data(slot.recipientEventIdentity)
            }
            self.relaySelection = relaySelection
            self.publicationJournal = publicationJournal
            self.codingLimits = codingLimits
            self.maximumPendingRelayOutputCount =
                maximumPendingRelayOutputCount
            provideRoutes = provideRoutesForPublication
            self.awaitPublicationPermit = awaitPublicationPermit
        }

        /// Publishes every sealed wrap after complete route preflight and per-recipient permits.
        func publish(_ batch: Batch) async throws(Failure) {
            let expectedRecipients = try validate(batch)
            guard !Task.isCancelled else { throw .cancelled }
            let routeRequests = PostManifestPublicationRouteAllocation
                .requests(for: expectedRecipients)

            let routeGroups: [RecipientRouteGroup]
            do {
                routeGroups = try await provideRoutes(batch.kind, routeRequests)
            } catch {
                guard !Task.isCancelled else { throw .cancelled }
                throw .routeProvisioningFailed
            }
            let allRoutes = routeGroups.flatMap(\.routes)
            guard !Task.isCancelled else {
                await PostManifestPublicationRouteCloser.close(allRoutes)
                throw .cancelled
            }

            let preparations: [PublicationPreparation]
            do {
                preparations = try prepare(
                    batch,
                    expectedRecipients: expectedRecipients,
                    routeGroups: routeGroups
                )
            } catch {
                await PostManifestPublicationRouteCloser.close(allRoutes)
                throw error
            }

            let prepared: [PreparedPublication]
            do {
                prepared = try recordCompleteBatch(preparations)
            } catch {
                await PostManifestPublicationRouteCloser.close(allRoutes)
                throw error
            }
            let publishers = prepared.map(\.publisher)

            let result: PublicationTaskResult = await withTaskCancellationHandler {
                await withTaskGroup(
                    of: PublicationTaskResult.self
                ) { group in
                    for publication in prepared {
                        group.addTask {
                            await publishPrepared(publication)
                        }
                    }

                    var firstFailure: PublicationTaskResult?
                    for await taskResult in group {
                        switch taskResult {
                        case .completed:
                            continue
                        case .cancelled:
                            if Task.isCancelled, firstFailure == nil {
                                firstFailure = .cancelled
                            }
                        case .permitFailed, .journalFailed, .recipientFailed:
                            guard firstFailure == nil else { continue }
                            firstFailure = taskResult
                            group.cancelAll()
                            await Self.stop(publishers)
                        }
                    }
                    if Task.isCancelled {
                        return .cancelled
                    }
                    return firstFailure ?? .completed
                }
            } onCancel: {
                Task { await Self.stop(publishers) }
            }

            switch result {
            case .completed:
                return
            case .permitFailed:
                await Self.stop(publishers)
                throw .publicationPermitFailed
            case .journalFailed:
                await Self.stop(publishers)
                throw .publicationJournalFailed
            case .recipientFailed:
                await Self.stop(publishers)
                throw .recipientPublicationFailed
            case .cancelled:
                await Self.stop(publishers)
                throw .cancelled
            }
        }

        /// Performs one caller-triggered attempt for pending anonymous continuations of a kind.
        ///
        /// The operation provisions fresh routes, reuses each durable permit, and requests the
        /// caller-owned permit only for a prepared member that did not durably cross it. It
        /// retransmits only stored bytes and invents no reconnect or scheduling policy.
        func resumePendingPublications(
            for kind: PublicationKind
        ) async throws(Failure) {
            let channelPurpose: PublicationJournal.ChannelPurpose
            let expectedRecipients: [Data]
            switch kind {
            case .components:
                channelPurpose = .anonymousComponents
                expectedRecipients = componentRecipientIdentities
            case .bchSignatures:
                channelPurpose = .anonymousBCHSignatures
                expectedRecipients = signatureRecipientIdentities
            }
            guard let durableBatch = publicationJournal
                .pendingBatchContinuation(for: channelPurpose) else {
                return
            }
            let continuations = durableBatch.continuations

            let receivedRecipients = continuations.map {
                $0.publication.binding.recipientEventIdentity
            }
            guard Set(receivedRecipients).count == receivedRecipients.count,
                  Set(receivedRecipients) == Set(expectedRecipients) else {
                throw .invalidContinuationSet
            }
            let reconciledBatch: PublicationJournal.BatchContinuation
            do {
                reconciledBatch = try publicationJournal
                    .reconcileAcknowledgementDerivedCompletions(
                        matching: durableBatch
                    )
            } catch {
                throw .publicationJournalFailed
            }
            guard !reconciledBatch.continuations.contains(where: {
                $0.completion == .transportRejected
            }) else {
                throw .recipientPublicationFailed
            }
            let pendingContinuations = reconciledBatch.pendingContinuations
            guard !pendingContinuations.isEmpty else { return }
            let requests = PostManifestPublicationRouteAllocation.requests(
                for: expectedRecipients
            )

            let routeGroups: [RecipientRouteGroup]
            do {
                routeGroups = try await provideRoutes(kind, requests)
            } catch {
                guard !Task.isCancelled else { throw .cancelled }
                throw .routeProvisioningFailed
            }
            let allRoutes = routeGroups.flatMap(\.routes)
            guard !Task.isCancelled else {
                await PostManifestPublicationRouteCloser.close(allRoutes)
                throw .cancelled
            }

            let allocation: PostManifestPublicationRouteAllocation
            do {
                allocation = try .init(
                    expectedRecipientEventIdentities: expectedRecipients,
                    routeGroups: routeGroups
                )
            } catch {
                await PostManifestPublicationRouteCloser.close(allRoutes)
                throw .routeAllocationMismatch
            }

            let prepared: [PreparedPublication]
            do {
                prepared = try pendingContinuations.map { continuation in
                    let recipient = continuation.publication.binding
                        .recipientEventIdentity
                    guard let routes = allocation.routes(for: recipient) else {
                        throw Failure.routeAllocationMismatch
                    }
                    return try .init(
                        permitRequest: .init(
                            kind: kind,
                            recipientEventIdentity: recipient
                        ),
                        continuation: continuation,
                        publisher: .init(
                            routes: routes,
                            relaySelection: relaySelection,
                            publicationJournal: publicationJournal,
                            codingLimits: codingLimits,
                            maximumPendingRelayOutputCount:
                                maximumPendingRelayOutputCount
                        )
                    )
                }
            } catch let failure as Failure {
                await PostManifestPublicationRouteCloser.close(allRoutes)
                throw failure
            } catch {
                await PostManifestPublicationRouteCloser.close(allRoutes)
                throw .publisherConstructionFailed
            }

            let usedRecipients = Set(pendingContinuations.map {
                $0.publication.binding.recipientEventIdentity
            })
            await PostManifestPublicationRouteCloser.close(
                routeGroups.filter {
                    !usedRecipients.contains($0.recipientEventIdentity)
                }.flatMap(\.routes)
            )
            let publishers = prepared.map(\.publisher)
            let result: PublicationTaskResult = await withTaskCancellationHandler {
                await withTaskGroup(of: PublicationTaskResult.self) { group in
                    for publication in prepared {
                        group.addTask {
                            await publishPrepared(publication)
                        }
                    }
                    var firstFailure: PublicationTaskResult?
                    for await taskResult in group {
                        guard taskResult != .completed,
                              firstFailure == nil else {
                            continue
                        }
                        firstFailure = taskResult
                        group.cancelAll()
                        await Self.stop(publishers)
                    }
                    return Task.isCancelled
                        ? .cancelled : firstFailure ?? .completed
                }
            } onCancel: {
                Task { await Self.stop(publishers) }
            }

            switch result {
            case .completed:
                return
            case .cancelled:
                await Self.stop(publishers)
                throw .cancelled
            case .permitFailed:
                await Self.stop(publishers)
                throw .publicationPermitFailed
            case .journalFailed:
                await Self.stop(publishers)
                throw .publicationJournalFailed
            case .recipientFailed:
                await Self.stop(publishers)
                throw .recipientPublicationFailed
            }
        }

        private func validate(
            _ batch: Batch
        ) throws(Failure) -> [Data] {
            guard batch.isBound(
                to: context,
                materialBinding: expectedMaterialBinding
            ) else {
                throw .batchContextMismatch
            }
            let expectedRecipients: [Data]
            switch batch.kind {
            case .components:
                expectedRecipients = componentRecipientIdentities
            case .bchSignatures:
                expectedRecipients = signatureRecipientIdentities
            }
            guard batch.recipients.count == expectedRecipients.count else {
                throw .batchContextMismatch
            }

            let expectedEventIdentities = Set(expectedRecipients)
            var receivedEventIdentities: Set<Data> = []
            for recipient in batch.recipients {
                let eventIdentity = recipient.recipientEventIdentity
                guard receivedEventIdentities.insert(eventIdentity).inserted,
                      expectedEventIdentities.contains(eventIdentity),
                      recipient.giftWrap.event.template.tags == [[
                        "p",
                        Nostr.EventCodec.hexadecimal(eventIdentity),
                      ]] else {
                    throw .batchContextMismatch
                }
            }
            guard receivedEventIdentities == expectedEventIdentities else {
                throw .batchContextMismatch
            }
            return expectedRecipients
        }

        private func prepare(
            _ batch: Batch,
            expectedRecipients: [Data],
            routeGroups: [RecipientRouteGroup]
        ) throws(Failure) -> [PublicationPreparation] {
            let allocation: PostManifestPublicationRouteAllocation
            do {
                allocation = try .init(
                    expectedRecipientEventIdentities: expectedRecipients,
                    routeGroups: routeGroups
                )
            } catch let error {
                switch error {
                case .routeAllocationMismatch:
                    throw .routeAllocationMismatch
                case .duplicateConnection:
                    throw .duplicateConnection
                }
            }

            do {
                return try batch.recipients.map { recipient in
                    guard let routes = allocation.routes(
                        for: recipient.recipientEventIdentity
                    ) else {
                        throw Failure.routeAllocationMismatch
                    }
                    return try .init(
                        permitRequest: .init(
                            kind: batch.kind,
                            recipientEventIdentity:
                                recipient.recipientEventIdentity
                        ),
                        giftWrap: recipient.giftWrap,
                        binding: .init(
                            channelPurpose: batch.kind == .components
                                ? .anonymousComponents
                                : .anonymousBCHSignatures,
                            recipientEventIdentity:
                                recipient.recipientEventIdentity,
                            expiryUnixSeconds: batch.expiryUnixSeconds
                        ),
                        publisher: PostManifestRelayPublisher(
                            routes: routes,
                            relaySelection: relaySelection,
                            publicationJournal: publicationJournal,
                            codingLimits: codingLimits,
                            maximumPendingRelayOutputCount:
                                maximumPendingRelayOutputCount
                        )
                    )
                }
            } catch let failure as Failure {
                throw failure
            } catch {
                throw .publisherConstructionFailed
            }
        }

        private func publishPrepared(
            _ publication: PreparedPublication
        ) async -> PublicationTaskResult {
            guard !Task.isCancelled else { return .cancelled }
            if !publication.continuation.hasPublicationPermit {
                do {
                    try await awaitPublicationPermit(
                        publication.permitRequest
                    )
                } catch {
                    return Task.isCancelled ? .cancelled : .permitFailed
                }
                guard !Task.isCancelled else { return .cancelled }
                do {
                    try publicationJournal.recordPublicationPermit(
                        eventIdentifier: publication.continuation
                            .publication.eventIdentifier
                    )
                } catch {
                    return .journalFailed
                }
            }
            guard !Task.isCancelled else { return .cancelled }
            do {
                try await publication.publisher.publish(
                    publication.continuation
                )
                return .completed
            } catch {
                return Task.isCancelled ? .cancelled : .recipientFailed
            }
        }

        private func recordCompleteBatch(
            _ preparations: [PublicationPreparation]
        ) throws(Failure) -> [PreparedPublication] {
            let durableBatch: PublicationJournal.BatchContinuation
            do {
                durableBatch = try publicationJournal.prepareBatch(
                    preparations.map { preparation in
                        .init(
                            giftWrap: preparation.giftWrap,
                            binding: preparation.binding
                        )
                    }
                )
            } catch {
                throw .publicationJournalFailed
            }

            var continuationsByEventIdentifier: [
                Data: PublicationJournal.Continuation
            ] = [:]
            for continuation in durableBatch.continuations {
                guard continuationsByEventIdentifier.updateValue(
                    continuation,
                    forKey: continuation.publication.eventIdentifier
                ) == nil else {
                    throw .publicationJournalFailed
                }
            }
            guard continuationsByEventIdentifier.count
                    == preparations.count else {
                throw .publicationJournalFailed
            }
            var preparedPublications: [PreparedPublication] = []
            for preparation in preparations {
                guard let continuation = continuationsByEventIdentifier[
                    preparation.giftWrap.event.identifier.rawRepresentation
                ] else {
                    throw .publicationJournalFailed
                }
                preparedPublications.append(.init(
                    permitRequest: preparation.permitRequest,
                    continuation: continuation,
                    publisher: preparation.publisher
                ))
            }
            return preparedPublications
        }

        private static func stop(
            _ publishers: [PostManifestRelayPublisher]
        ) async {
            await withTaskGroup(of: Void.self) { group in
                for publisher in publishers {
                    group.addTask { await publisher.stop() }
                }
            }
        }
    }
}

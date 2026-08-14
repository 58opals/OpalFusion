// OpalFusion+Mosaic+OpalMainnetAlpha+PostManifestControlBatchPublisher.swift

import Foundation

extension OpalFusion.Mosaic.OpalMainnetAlpha {
    /// Publishes one bridge-minted control-envelope batch to the complete roster.
    ///
    /// The value binds the batch to one manifest, recipient allocation, and relay selection. It
    /// obtains every recipient's already Tor-bound routes, durably prepares the complete batch in
    /// one journal append before opening any route, rejects connection reuse across recipients,
    /// and returns only after every publisher has reached its two-acknowledgement boundary and
    /// closed all routes. Endpoint provisioning, durable-storage implementation, retry policy,
    /// and semantic loopback admission remain caller-owned.
    struct PostManifestControlBatchPublisher: Sendable {
        typealias Batch = PostManifestControlPublicationBridge.GiftWrapBatch
        typealias Recipient = PostManifestControlPublicationBridge.Recipient
        typealias Context = PostManifestControlPublicationBridge.Context
        typealias ControlIdentity = OpalFusion.Mosaic.Attempt.ControlIdentity
        typealias Nostr = OpalFusion.Mosaic.NostrNamespace
        typealias PublicationJournal = PostManifestRelayPublicationJournal
        typealias RecipientRouteRequest =
            PostManifestPublicationRouteAllocation.RecipientRouteRequest
        typealias RecipientRouteGroup =
            PostManifestPublicationRouteAllocation.RecipientRouteGroup

        enum InitializationError: Error, Sendable, Equatable {
            case manifestRelaySelectionMismatch
            case invalidRecipientCount(actual: Int)
            case duplicateRecipient(ControlIdentity)
            case recipientSetMismatch
            case duplicateRecipientEventIdentity
            case recipientEventIdentityReusesRosterControlIdentity
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
            case recipientPublicationFailed
            case cancelled
        }

        /// Provides one complete route allocation without receiving publishable event bytes.
        ///
        /// The provider must promptly honor task cancellation and must close any partially
        /// allocated routes before throwing. Once a complete allocation is returned, this value
        /// owns closure of every route.
        typealias RouteProvider = @Sendable (
            [RecipientRouteRequest]
        ) async throws -> [RecipientRouteGroup]

        private struct PreparedPublication: Sendable {
            let giftWrap: PostManifestRelayPublisher.GiftWrap
            let binding: PublicationJournal.PublicationBinding
            let publisher: PostManifestRelayPublisher
        }

        private struct PreparedContinuation: Sendable {
            let continuation: PublicationJournal.Continuation
            let publisher: PostManifestRelayPublisher
        }

        private let context: Context
        private let relaySelection: PostManifestRelaySelectionValidation
        private let publicationJournal: PublicationJournal
        private let routeRequests: [RecipientRouteRequest]
        private let recipientEventIdentities: [ControlIdentity: Data]
        private let codingLimits: Nostr.RelayMessageCodingLimits
        private let maximumPendingRelayOutputCount: Int
        private let provideRoutes: RouteProvider

        init(
            context: Context,
            recipients: [Recipient],
            relaySelection: PostManifestRelaySelectionValidation,
            publicationJournal: PublicationJournal,
            codingLimits: Nostr.RelayMessageCodingLimits,
            maximumPendingRelayOutputCount: Int,
            provideRoutes: @escaping RouteProvider
        ) throws(InitializationError) {
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

            let rosterIdentities = context.roster.controlIdentities
            guard recipients.count == rosterIdentities.count else {
                throw .invalidRecipientCount(actual: recipients.count)
            }
            let rosterControlIdentities = Set(
                rosterIdentities.map { Data($0.validatedBytes) }
            )
            var recipientsByIdentity: [ControlIdentity: Data] = [:]
            var uniqueEventIdentities: Set<Data> = []
            for recipient in recipients {
                let eventIdentity = recipient.eventVerificationKey
                    .rawRepresentation
                guard recipientsByIdentity.updateValue(
                    eventIdentity,
                    forKey: recipient.controlIdentity
                ) == nil else {
                    throw .duplicateRecipient(recipient.controlIdentity)
                }
                guard !rosterControlIdentities.contains(eventIdentity) else {
                    throw .recipientEventIdentityReusesRosterControlIdentity
                }
                guard uniqueEventIdentities.insert(eventIdentity).inserted else {
                    throw .duplicateRecipientEventIdentity
                }
            }
            guard Set(recipientsByIdentity.keys) == Set(rosterIdentities) else {
                throw .recipientSetMismatch
            }

            self.context = context
            self.relaySelection = relaySelection
            self.publicationJournal = publicationJournal
            self.routeRequests = PostManifestPublicationRouteAllocation
                .requests(for: Array(recipientsByIdentity.values))
            self.recipientEventIdentities = recipientsByIdentity
            self.codingLimits = codingLimits
            self.maximumPendingRelayOutputCount =
                maximumPendingRelayOutputCount
            self.provideRoutes = provideRoutes
        }

        /// Publishes every recipient gift wrap or fails the complete batch.
        func publish(_ batch: Batch) async throws(Failure) {
            try validate(batch)

            let routeGroups: [RecipientRouteGroup]
            do {
                routeGroups = try await provideRoutes(routeRequests)
            } catch {
                guard !Task.isCancelled else {
                    throw .cancelled
                }
                throw .routeProvisioningFailed
            }
            let allRoutes = routeGroups.flatMap(\.routes)
            guard !Task.isCancelled else {
                await PostManifestPublicationRouteCloser.close(allRoutes)
                throw .cancelled
            }

            let prepared: [PreparedContinuation]
            do {
                prepared = try prepare(batch, routeGroups: routeGroups)
            } catch {
                await PostManifestPublicationRouteCloser.close(allRoutes)
                throw error
            }
            let publishers = prepared.map(\.publisher)

            do {
                try await withTaskCancellationHandler {
                    try await withThrowingTaskGroup(of: Void.self) { group in
                        for publication in prepared {
                            group.addTask {
                                try await publication.publisher.publish(
                                    publication.continuation
                                )
                            }
                        }
                        do {
                            while try await group.next() != nil {}
                        } catch {
                            group.cancelAll()
                            await Self.stop(publishers)
                            throw error
                        }
                    }
                } onCancel: {
                    Task {
                        await Self.stop(publishers)
                    }
                }
            } catch {
                await Self.stop(publishers)
                guard !Task.isCancelled else {
                    throw .cancelled
                }
                throw .recipientPublicationFailed
            }
            guard !Task.isCancelled else {
                await Self.stop(publishers)
                throw .cancelled
            }
        }

        /// Performs one caller-triggered attempt for each pending control continuation.
        ///
        /// The operation provisions a fresh complete control allocation and retransmits only
        /// byte-identical journaled events. It defines no reconnect or scheduling policy.
        func resumePendingPublications() async throws(Failure) {
            guard let durableBatch = publicationJournal
                .pendingBatchContinuation(for: .control) else {
                return
            }
            let continuations = durableBatch.continuations

            let expectedIdentities = Set(
                recipientEventIdentities.values
            )
            let receivedIdentities = continuations.map {
                $0.publication.binding.recipientEventIdentity
            }
            guard Set(receivedIdentities).count == receivedIdentities.count,
                  Set(receivedIdentities) == expectedIdentities else {
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

            let routeGroups: [RecipientRouteGroup]
            do {
                routeGroups = try await provideRoutes(routeRequests)
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
                    expectedRecipientEventIdentities: routeRequests.map(
                        \.recipientEventIdentity
                    ),
                    routeGroups: routeGroups
                )
            } catch {
                await PostManifestPublicationRouteCloser.close(allRoutes)
                throw .routeAllocationMismatch
            }

            let prepared: [PreparedContinuation]
            do {
                prepared = try pendingContinuations.map { continuation in
                    let recipient = continuation.publication.binding
                        .recipientEventIdentity
                    guard let routes = allocation.routes(for: recipient) else {
                        throw Failure.routeAllocationMismatch
                    }
                    return try .init(
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

            let usedIdentities = Set(pendingContinuations.map {
                $0.publication.binding.recipientEventIdentity
            })
            await PostManifestPublicationRouteCloser.close(
                routeGroups.filter {
                    !usedIdentities.contains($0.recipientEventIdentity)
                }.flatMap(\.routes)
            )
            let publishers = prepared.map(\.publisher)
            do {
                try await withTaskCancellationHandler {
                    try await withThrowingTaskGroup(of: Void.self) { group in
                        for publication in prepared {
                            group.addTask {
                                try await publication.publisher.resume(
                                    publication.continuation
                                )
                            }
                        }
                        do {
                            while try await group.next() != nil {}
                        } catch {
                            group.cancelAll()
                            await Self.stop(publishers)
                            throw error
                        }
                    }
                } onCancel: {
                    Task { await Self.stop(publishers) }
                }
            } catch {
                await Self.stop(publishers)
                guard !Task.isCancelled else { throw .cancelled }
                throw .recipientPublicationFailed
            }
        }

        private func validate(_ batch: Batch) throws(Failure) {
            guard batch.context == context,
                  batch.envelope.roundIdentifier == context.roundIdentifier,
                  batch.envelope.senderControlIdentity
                    == context.localControlIdentity,
                  batch.recipients.count == routeRequests.count else {
                throw .batchContextMismatch
            }
            var receivedIdentities: Set<ControlIdentity> = []
            for recipient in batch.recipients {
                guard receivedIdentities.insert(
                    recipient.controlIdentity
                ).inserted,
                let expectedEventIdentity = recipientEventIdentities[
                    recipient.controlIdentity
                ],
                recipient.giftWrap.event.template.tags == [[
                    "p",
                    Nostr.EventCodec.hexadecimal(expectedEventIdentity),
                ]] else {
                    throw .batchContextMismatch
                }
            }
            guard receivedIdentities == Set(context.roster.controlIdentities) else {
                throw .batchContextMismatch
            }
        }

        private func prepare(
            _ batch: Batch,
            routeGroups: [RecipientRouteGroup]
        ) throws(Failure) -> [PreparedContinuation] {
            let allocation: PostManifestPublicationRouteAllocation
            do {
                allocation = try .init(
                    expectedRecipientEventIdentities: routeRequests.map(
                        \.recipientEventIdentity
                    ),
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

            let publications: [PreparedPublication]
            do {
                publications = try batch.recipients.map { recipient in
                    guard let eventIdentity = recipientEventIdentities[
                        recipient.controlIdentity
                    ],
                    let routes = allocation.routes(for: eventIdentity) else {
                        throw Failure.routeAllocationMismatch
                    }
                    return try .init(
                        giftWrap: recipient.giftWrap,
                        binding: .init(
                            channelPurpose: .control,
                            recipientEventIdentity: eventIdentity,
                            expiryUnixSeconds:
                                batch.envelope.expiryUnixSeconds
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

            let durableBatch: PublicationJournal.BatchContinuation
            do {
                durableBatch = try publicationJournal.prepareBatch(
                    publications.map { publication in
                        .init(
                            giftWrap: publication.giftWrap,
                            binding: publication.binding
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
            guard continuationsByEventIdentifier.count == publications.count else {
                throw .publicationJournalFailed
            }
            var preparedPublications: [PreparedContinuation] = []
            for publication in publications {
                let eventIdentifier = publication.giftWrap.event.identifier
                    .rawRepresentation
                guard let continuation = continuationsByEventIdentifier[
                    eventIdentifier
                ] else {
                    throw .publicationJournalFailed
                }
                preparedPublications.append(.init(
                    continuation: continuation,
                    publisher: publication.publisher
                ))
            }
            return preparedPublications
        }

        private static func stop(
            _ publishers: [PostManifestRelayPublisher]
        ) async {
            await withTaskGroup(of: Void.self) { group in
                for publisher in publishers {
                    group.addTask {
                        await publisher.stop()
                    }
                }
            }
        }
    }
}

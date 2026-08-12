// OpalFusion+Mosaic+OpalMainnetAlpha+PostManifestAnonymousBatchPublisher.swift

import Foundation

extension OpalFusion.Mosaic.OpalMainnetAlpha {
    /// Publishes one material-bound anonymous phase batch through injected Tor-only routes.
    ///
    /// The value obtains and validates the complete route allocation before exposing any signed
    /// gift wrap to a relay publisher. Each recipient then requires a caller-owned publication
    /// permit before its exact-three-route/two-accepted-ACK publication begins. Endpoint and Tor
    /// provisioning, timing policy, persistence, retry, and semantic loopback remain external.
    struct PostManifestAnonymousBatchPublisher: Sendable {
        typealias Batch = PostManifestAnonymousPublicationBridge.GiftWrapBatch
        typealias Context = PostManifestAnonymousPublicationBridge.Context
        typealias MaterialBinding = PostManifestAnonymousPublicationBridge
            .MaterialBinding
        typealias PublicationKind = PostManifestAnonymousPublicationBridge
            .PublicationKind
        typealias Nostr = OpalFusion.Mosaic.NostrNamespace

        struct RecipientRouteRequest: Sendable, Equatable {
            let recipientEventIdentity: Data
        }

        struct RecipientRouteGroup: Sendable {
            let recipientEventIdentity: Data
            let routes: [PostManifestRelayRoute]

            init(
                recipientEventIdentity: Data,
                routes: [PostManifestRelayRoute]
            ) {
                self.recipientEventIdentity = recipientEventIdentity
                self.routes = routes
            }
        }

        struct PublicationPermitRequest: Sendable, Equatable {
            let kind: PublicationKind
            let recipientEventIdentity: Data
        }

        enum InitializationError: Error, Sendable, Equatable {
            case localPeerIsNotContributor
            case localMaterialMismatch
            case manifestRelaySelectionMismatch
            case incompatibleCodingLimits
            case invalidOutputBufferLimit
        }

        enum Failure: Error, Sendable, Equatable {
            case batchContextMismatch
            case routeProvisioningFailed
            case routeAllocationMismatch
            case duplicateConnection
            case publisherConstructionFailed
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

        private struct PreparedPublication: Sendable {
            let permitRequest: PublicationPermitRequest
            let giftWrap: PostManifestRelayPublisher.GiftWrap
            let publisher: PostManifestRelayPublisher
        }

        private enum PublicationTaskResult: Sendable {
            case completed
            case permitFailed
            case recipientFailed
            case cancelled
        }

        private let context: Context
        private let expectedMaterialBinding: MaterialBinding
        private let componentRecipientIdentities: [Data]
        private let signatureRecipientIdentities: [Data]
        private let relaySelection: PostManifestRelaySelectionValidation
        private let codingLimits: Nostr.RelayMessageCodingLimits
        private let maximumPendingRelayOutputCount: Int
        private let provideRoutes: PurposefulRouteProvider
        private let awaitPublicationPermit: PublicationPermitProvider

        init(
            context: Context,
            material: LocalContributionMaterial,
            relaySelection: PostManifestRelaySelectionValidation,
            codingLimits: Nostr.RelayMessageCodingLimits,
            maximumPendingRelayOutputCount: Int,
            provideRoutes: @escaping RouteProvider,
            awaitPublicationPermit: @escaping PublicationPermitProvider
        ) throws(InitializationError) {
            try self.init(
                context: context,
                material: material,
                relaySelection: relaySelection,
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
            let routeRequests = expectedRecipients.map {
                RecipientRouteRequest(
                    recipientEventIdentity: $0
                )
            }.sorted {
                $0.recipientEventIdentity.lexicographicallyPrecedes(
                    $1.recipientEventIdentity
                )
            }

            let routeGroups: [RecipientRouteGroup]
            do {
                routeGroups = try await provideRoutes(batch.kind, routeRequests)
            } catch {
                guard !Task.isCancelled else { throw .cancelled }
                throw .routeProvisioningFailed
            }
            let allRoutes = routeGroups.flatMap(\.routes)
            guard !Task.isCancelled else {
                await Self.close(allRoutes)
                throw .cancelled
            }

            let prepared: [PreparedPublication]
            do {
                prepared = try prepare(
                    batch,
                    expectedRecipients: expectedRecipients,
                    routeGroups: routeGroups
                )
            } catch {
                await Self.close(allRoutes)
                throw error
            }
            let publishers = prepared.map(\.publisher)

            let result: PublicationTaskResult = await withTaskCancellationHandler {
                await withTaskGroup(
                    of: PublicationTaskResult.self
                ) { group in
                    for publication in prepared {
                        group.addTask {
                            guard !Task.isCancelled else {
                                return .cancelled
                            }
                            do {
                                try await awaitPublicationPermit(
                                    publication.permitRequest
                                )
                            } catch {
                                return Task.isCancelled
                                    ? .cancelled : .permitFailed
                            }
                            guard !Task.isCancelled else {
                                return .cancelled
                            }
                            do {
                                try await publication.publisher.publish(
                                    publication.giftWrap
                                )
                                return .completed
                            } catch {
                                return Task.isCancelled
                                    ? .cancelled : .recipientFailed
                            }
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
                        case .permitFailed, .recipientFailed:
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
            case .recipientFailed:
                await Self.stop(publishers)
                throw .recipientPublicationFailed
            case .cancelled:
                await Self.stop(publishers)
                throw .cancelled
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
        ) throws(Failure) -> [PreparedPublication] {
            guard routeGroups.count == expectedRecipients.count else {
                throw .routeAllocationMismatch
            }
            var routesByEventIdentity: [Data: [PostManifestRelayRoute]] = [:]
            var connectionIdentities: Set<ObjectIdentifier> = []
            for group in routeGroups {
                guard routesByEventIdentity.updateValue(
                    group.routes,
                    forKey: group.recipientEventIdentity
                ) == nil else {
                    throw .routeAllocationMismatch
                }
                for route in group.routes {
                    guard connectionIdentities.insert(
                        ObjectIdentifier(route.connection as AnyObject)
                    ).inserted else {
                        throw .duplicateConnection
                    }
                }
            }
            guard Set(routesByEventIdentity.keys)
                    == Set(expectedRecipients) else {
                throw .routeAllocationMismatch
            }

            do {
                return try batch.recipients.map { recipient in
                    guard let routes = routesByEventIdentity[
                        recipient.recipientEventIdentity
                    ] else {
                        throw Failure.routeAllocationMismatch
                    }
                    return try .init(
                        permitRequest: .init(
                            kind: batch.kind,
                            recipientEventIdentity:
                                recipient.recipientEventIdentity
                        ),
                        giftWrap: recipient.giftWrap,
                        publisher: PostManifestRelayPublisher(
                            routes: routes,
                            relaySelection: relaySelection,
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

        private static func stop(
            _ publishers: [PostManifestRelayPublisher]
        ) async {
            await withTaskGroup(of: Void.self) { group in
                for publisher in publishers {
                    group.addTask { await publisher.stop() }
                }
            }
        }

        private static func close(
            _ routes: [PostManifestRelayRoute]
        ) async {
            await withTaskGroup(of: Void.self) { group in
                var connectionIdentities: Set<ObjectIdentifier> = []
                for route in routes {
                    guard connectionIdentities.insert(
                        ObjectIdentifier(route.connection as AnyObject)
                    ).inserted else {
                        continue
                    }
                    group.addTask { await route.connection.close() }
                }
            }
        }
    }
}

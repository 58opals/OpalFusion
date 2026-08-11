// OpalFusion+Mosaic+OpalMainnetAlpha+PostManifestControlBatchPublisher.swift

import Foundation

extension OpalFusion.Mosaic.OpalMainnetAlpha {
    /// Publishes one bridge-minted control-envelope batch to the complete roster.
    ///
    /// The value binds the batch to one manifest, recipient allocation, and relay selection. It
    /// obtains every recipient's already Tor-bound routes before exposing any signed gift wrap to
    /// a relay publisher, rejects connection reuse across recipients, and returns only after every
    /// publisher has reached its two-acknowledgement boundary and closed all routes. Endpoint
    /// provisioning, persistence, retry, and semantic loopback admission remain caller-owned.
    struct PostManifestControlBatchPublisher: Sendable {
        typealias Batch = PostManifestControlPublicationBridge.GiftWrapBatch
        typealias Recipient = PostManifestControlPublicationBridge.Recipient
        typealias Context = PostManifestControlPublicationBridge.Context
        typealias ControlIdentity = OpalFusion.Mosaic.Attempt.ControlIdentity
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

        enum InitializationError: Error, Sendable, Equatable {
            case manifestRelaySelectionMismatch
            case invalidRecipientCount(actual: Int)
            case duplicateRecipient(ControlIdentity)
            case recipientSetMismatch
            case duplicateRecipientEventIdentity
            case recipientEventIdentityReusesRosterControlIdentity
            case incompatibleCodingLimits
            case invalidOutputBufferLimit
        }

        enum Failure: Error, Sendable, Equatable {
            case batchContextMismatch
            case routeProvisioningFailed
            case routeAllocationMismatch
            case duplicateConnection
            case publisherConstructionFailed
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
            let publisher: PostManifestRelayPublisher
        }

        private let context: Context
        private let relaySelection: PostManifestRelaySelectionValidation
        private let routeRequests: [RecipientRouteRequest]
        private let recipientEventIdentities: [ControlIdentity: Data]
        private let codingLimits: Nostr.RelayMessageCodingLimits
        private let maximumPendingRelayOutputCount: Int
        private let provideRoutes: RouteProvider

        init(
            context: Context,
            recipients: [Recipient],
            relaySelection: PostManifestRelaySelectionValidation,
            codingLimits: Nostr.RelayMessageCodingLimits,
            maximumPendingRelayOutputCount: Int,
            provideRoutes: @escaping RouteProvider
        ) throws(InitializationError) {
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
            self.routeRequests = recipientsByIdentity.values
                .map(RecipientRouteRequest.init(recipientEventIdentity:))
                .sorted {
                    $0.recipientEventIdentity.lexicographicallyPrecedes(
                        $1.recipientEventIdentity
                    )
                }
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
                await Self.close(allRoutes)
                throw .cancelled
            }

            let prepared: [PreparedPublication]
            do {
                prepared = try prepare(batch, routeGroups: routeGroups)
            } catch {
                await Self.close(allRoutes)
                throw error
            }
            let publishers = prepared.map(\.publisher)

            do {
                try await withTaskCancellationHandler {
                    try await withThrowingTaskGroup(of: Void.self) { group in
                        for publication in prepared {
                            group.addTask {
                                try await publication.publisher.publish(
                                    publication.giftWrap
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
        ) throws(Failure) -> [PreparedPublication] {
            guard routeGroups.count == routeRequests.count else {
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
                    == Set(routeRequests.map(\.recipientEventIdentity)) else {
                throw .routeAllocationMismatch
            }

            do {
                return try batch.recipients.map { recipient in
                    guard let eventIdentity = recipientEventIdentities[
                        recipient.controlIdentity
                    ],
                    let routes = routesByEventIdentity[eventIdentity] else {
                        throw Failure.routeAllocationMismatch
                    }
                    return try .init(
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
                    group.addTask {
                        await publisher.stop()
                    }
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
                    group.addTask {
                        await route.connection.close()
                    }
                }
            }
        }
    }
}

// OpalFusion+Mosaic+OpalMainnetAlpha+PostManifestAttemptTransportOwner.swift

import Foundation
import OpalCrypto
import Synchronization

extension OpalFusion.Mosaic.OpalMainnetAlpha {
    /// Owns one peer's post-manifest mailbox projection and route capabilities for one attempt.
    ///
    /// The injected mailbox projection must already have crossed the caller's authenticated
    /// distribution boundary. This actor validates its exact attempt, role, and mailbox shape;
    /// it does not define that distribution protocol. Likewise, an isolation lease is opaque
    /// evidence supplied by the route provisioner. Rejecting lease reuse prevents accidental
    /// in-process reuse, but only the provisioner can attest that leases name distinct Tor
    /// circuits with remote DNS and no clearnet fallback.
    actor PostManifestAttemptTransportOwner {
        typealias ControlBridge = PostManifestControlPublicationBridge
        typealias ControlPublisher = PostManifestControlBatchPublisher
        typealias AnonymousPublisher = PostManifestAnonymousBatchPublisher
        typealias Driver = PostManifestRuntimeDriver
        typealias FanIn = PostManifestRelayFanIn
        typealias Nostr = OpalFusion.Mosaic.NostrNamespace
        typealias Role = OpalFusion.Mosaic.Role
        typealias Transport = PostManifestNIP59Transport

        /// Immutable attempt facts covered by the caller's authenticated mailbox projection.
        struct Binding: Sendable, Equatable {
            let context: ControlBridge.Context
            let role: Role

            init(context: ControlBridge.Context, role: Role) {
                self.context = context
                self.role = role
            }
        }

        /// Role-limited anonymous mailbox knowledge supplied by the authentication boundary.
        enum AnonymousMailboxProjection: Sendable {
            /// Ordered public recipient identities for this contributor's material slots.
            case contributor([
                OpalCrypto.Signature.BIP340.VerificationKey
            ])

            /// The complete unlabeled private-capability set required by the conductor.
            case conductor([Transport.RecipientCapability])
        }

        /// A caller-authenticated projection; construction itself performs no authentication.
        struct AuthenticatedMailboxProjection: Sendable {
            let binding: Binding
            let controlRecipients: [ControlBridge.Recipient]
            let localControlRecipientCapability: Transport.RecipientCapability
            let anonymous: AnonymousMailboxProjection

            init(
                binding: Binding,
                controlRecipients: [ControlBridge.Recipient],
                localControlRecipientCapability: Transport.RecipientCapability,
                anonymous: AnonymousMailboxProjection
            ) {
                self.binding = binding
                self.controlRecipients = controlRecipients
                self.localControlRecipientCapability =
                    localControlRecipientCapability
                self.anonymous = anonymous
            }
        }

        /// One complete, owner-validated inbound allocation for private runtime construction.
        ///
        /// Every route group shares one attempt binding, so constructing the authorized fan-in
        /// consumes exactly one capability rather than one claim per mailbox. The capability
        /// grants neither event admission nor wallet or broadcast authority.
        struct InboundRuntimeProvisioning: Sendable {
            /// Opaque evidence that this provisioning was claimed for one exact runtime.
            ///
            /// Only `claim` can mint this value. It carries no mutable lifecycle state; the
            /// provisioning's claim state remains the single one-attempt authority.
            struct ClaimedRuntimeConstruction: Sendable {
                fileprivate init() {}
            }

            private final class ClaimState: Sendable {
                private struct Facts: Sendable, Equatable {
                    let attemptIdentifier: Driver.Session.AttemptIdentifier
                    let generationIdentifier: Driver.Session.GenerationIdentifier
                    let materialIdentifier: Driver.Session.MaterialIdentifier
                    let localControlIdentity: Driver.Session.ControlIdentity
                    let manifestCore: RoundManifestCore
                }

                private let facts: Facts
                private let isClaimed = Mutex(false)

                init(bootstrap: Driver.Bootstrap) {
                    facts = .init(
                        attemptIdentifier: bootstrap.attemptIdentifier,
                        generationIdentifier: bootstrap.generationIdentifier,
                        materialIdentifier: bootstrap.materialIdentifier,
                        localControlIdentity: bootstrap.localControlIdentity,
                        manifestCore: bootstrap.proposalValidation.core
                    )
                }

                func matches(_ bootstrap: Driver.Bootstrap) -> Bool {
                    facts == .init(
                        attemptIdentifier: bootstrap.attemptIdentifier,
                        generationIdentifier: bootstrap.generationIdentifier,
                        materialIdentifier: bootstrap.materialIdentifier,
                        localControlIdentity: bootstrap.localControlIdentity,
                        manifestCore: bootstrap.proposalValidation.core
                    )
                }

                func claim() -> Bool {
                    isClaimed.withLock {
                        guard !$0 else { return false }
                        $0 = true
                        return true
                    }
                }
            }

            let recipientRouteGroups: [FanIn.RecipientRouteGroup]
            let relaySelection: PostManifestRelaySelectionValidation

            private let role: Role
            private let claimState: ClaimState

            fileprivate init(
                role: Role,
                bootstrap: Driver.Bootstrap,
                recipientRouteGroups: [FanIn.RecipientRouteGroup],
                relaySelection: PostManifestRelaySelectionValidation
            ) {
                self.role = role
                claimState = .init(bootstrap: bootstrap)
                self.recipientRouteGroups = recipientRouteGroups
                self.relaySelection = relaySelection
            }

            func matches(
                _ bootstrap: Driver.Bootstrap,
                role: Role
            ) -> Bool {
                self.role == role && claimState.matches(bootstrap)
            }

            func claim(
                _: FanIn.RuntimeConstructionRequest,
                _ bootstrap: Driver.Bootstrap,
                role: Role
            ) -> ClaimedRuntimeConstruction? {
                guard matches(bootstrap, role: role),
                      claimState.claim() else {
                    return nil
                }
                return .init()
            }
        }

        enum RoutePurpose: Sendable, Hashable {
            case inboundControl
            case inboundAnonymous
            case outboundControl
            case outboundAnonymousComponents
            case outboundAnonymousBCHSignatures
        }

        /// Non-diagnostic identity for a caller-attested Tor isolation capability.
        struct IsolationLease: Sendable, Hashable {
            let opaqueIdentifier: UUID

            init(opaqueIdentifier: UUID) {
                self.opaqueIdentifier = opaqueIdentifier
            }
        }

        struct RouteRequest: Sendable, Equatable {
            let binding: Binding
            let purpose: RoutePurpose
            let recipientEventIdentity: Data
            let endpoints: [PostManifestRelayEndpoint]
        }

        struct ProvisionedRoute: Sendable {
            let endpoint: PostManifestRelayEndpoint
            let connection: any OpalFusion.Mosaic.TorWebSocketConnectioning
            let isolationLease: IsolationLease

            init(
                endpoint: PostManifestRelayEndpoint,
                connection: any OpalFusion.Mosaic.TorWebSocketConnectioning,
                isolationLease: IsolationLease
            ) {
                self.endpoint = endpoint
                self.connection = connection
                self.isolationLease = isolationLease
            }
        }

        struct ProvisionedRouteGroup: Sendable {
            let recipientEventIdentity: Data
            let routes: [ProvisionedRoute]

            init(
                recipientEventIdentity: Data,
                routes: [ProvisionedRoute]
            ) {
                self.recipientEventIdentity = recipientEventIdentity
                self.routes = routes
            }
        }

        struct Dependencies: Sendable {
            /// Returns endpoint-bound connections with caller-attested isolation leases.
            ///
            /// The provider receives no publication bytes. It must close any partial allocation
            /// before throwing. Once a complete allocation is returned, this actor owns closure
            /// on rejection and transfers valid routes to the requesting fan-in or publisher.
            let provisionRoutes: @Sendable (
                [RouteRequest]
            ) async throws -> [ProvisionedRouteGroup]

            /// Creates one fresh, non-correlating subscription identifier for an inbound route.
            let makeSubscriptionIdentifier: @Sendable (
                RouteRequest,
                PostManifestRelayEndpoint
            ) throws -> Nostr.SubscriptionIdentifier

            init(
                provisionRoutes: @escaping @Sendable (
                    [RouteRequest]
                ) async throws -> [ProvisionedRouteGroup],
                makeSubscriptionIdentifier: @escaping @Sendable (
                    RouteRequest,
                    PostManifestRelayEndpoint
                ) throws -> Nostr.SubscriptionIdentifier
            ) {
                self.provisionRoutes = provisionRoutes
                self.makeSubscriptionIdentifier = makeSubscriptionIdentifier
            }
        }

        enum InitializationError: Error, Sendable, Equatable {
            case invalidContext(ControlBridge.Context.ValidationError)
            case mailboxProjectionBindingMismatch
            case relaySelectionManifestMismatch
            case invalidControlMailboxProjection
            case roleProjectionMismatch
            case invalidAnonymousMailboxProjection
        }

        enum Failure: Error, Sendable, Equatable {
            case invalidRouteRequestSet
            case inboundRoutesAlreadyIssued
            case concurrentProvisioning
            case routeProvisioningFailed
            case routeAllocationMismatch
            case duplicateConnection
            case duplicateIsolationLease
            case subscriptionIdentifierUnavailable
            case duplicateSubscriptionIdentifier
            case cancelled
            case inputAfterTermination
        }

        private struct Claims {
            var inboundRoutesWereIssued = false
            var connectionIdentities: Set<ObjectIdentifier> = []
            var isolationLeases: Set<IsolationLease> = []
            var subscriptionIdentifiers: Set<Nostr.SubscriptionIdentifier> = []
        }

        private enum State {
            case ready(Claims)
            case provisioning
            case terminal
        }

        private struct OwnedRouteGroup: Sendable {
            let recipientEventIdentity: Data
            let routes: [PostManifestRelayRoute]
            let subscriptionIdentifiers: [
                PostManifestRelayEndpoint: Nostr.SubscriptionIdentifier
            ]
        }

        nonisolated let binding: Binding
        nonisolated let localRole: Role
        nonisolated let controlRecipients: [ControlBridge.Recipient]
        nonisolated let localControlRecipientCapability:
            Transport.RecipientCapability

        private let bootstrap: Driver.Bootstrap
        private let relaySelection: PostManifestRelaySelectionValidation
        private let contributorAnonymousRecipientIdentities: [Data]?
        private let conductorAnonymousRecipientCapabilities: [
            Transport.RecipientCapability
        ]
        private let dependencies: Dependencies
        private var state: State = .ready(.init())

        init(
            bootstrap: Driver.Bootstrap,
            manifest: RoundManifest,
            mailboxProjection: AuthenticatedMailboxProjection,
            relaySelection: PostManifestRelaySelectionValidation,
            dependencies: Dependencies
        ) throws(InitializationError) {
            let context: ControlBridge.Context
            do {
                context = try .init(validating: manifest, against: bootstrap)
            } catch let error {
                throw .invalidContext(error)
            }
            let role: Role = context.localControlIdentity == context.roster.conductor
                ? .conductor : .contributor
            let binding = Binding(context: context, role: role)
            guard mailboxProjection.binding == binding else {
                throw .mailboxProjectionBindingMismatch
            }
            guard relaySelection.manifestRelaySetDigest
                    == context.manifest.core.relaySetDigest else {
                throw .relaySelectionManifestMismatch
            }

            let rosterIdentities = context.roster.controlIdentities
            guard mailboxProjection.controlRecipients.count
                    == rosterIdentities.count else {
                throw .invalidControlMailboxProjection
            }
            let rosterEventIdentities = Set(
                rosterIdentities.map { Data($0.validatedBytes) }
            )
            var controlRecipientsByIdentity: [
                Driver.Session.ControlIdentity: ControlBridge.Recipient
            ] = [:]
            var mailboxIdentities: Set<Data> = []
            for recipient in mailboxProjection.controlRecipients {
                guard controlRecipientsByIdentity.updateValue(
                    recipient,
                    forKey: recipient.controlIdentity
                ) == nil else {
                    throw .invalidControlMailboxProjection
                }
                let eventIdentity = recipient.eventVerificationKey
                    .rawRepresentation
                guard !rosterEventIdentities.contains(eventIdentity) else {
                    throw .invalidControlMailboxProjection
                }
                guard mailboxIdentities.insert(eventIdentity).inserted else {
                    throw .invalidControlMailboxProjection
                }
            }
            guard Set(controlRecipientsByIdentity.keys)
                    == Set(rosterIdentities) else {
                throw .invalidControlMailboxProjection
            }
            guard let localControlRecipient = controlRecipientsByIdentity[
                context.localControlIdentity
            ] else {
                throw .invalidControlMailboxProjection
            }
            let localCapability = mailboxProjection
                .localControlRecipientCapability
            guard localCapability.channel == .control,
                  localCapability.recipientEventIdentity
                    == localControlRecipient.eventVerificationKey
                        .rawRepresentation else {
                throw .invalidControlMailboxProjection
            }

            let expectedAnonymousCount = context.roster.contributors.count
                * OpalFusion.Mosaic.OpalMainnetAlpha
                    .componentCountPerContributor
            let contributorAnonymousIdentities: [Data]?
            let conductorAnonymousCapabilities: [
                Transport.RecipientCapability
            ]
            switch (role, mailboxProjection.anonymous) {
            case let (.contributor, .contributor(verificationKeys)):
                guard verificationKeys.count
                        == OpalFusion.Mosaic.OpalMainnetAlpha
                            .componentCountPerContributor else {
                    throw .invalidAnonymousMailboxProjection
                }
                let identities = verificationKeys.map(\.rawRepresentation)
                for identity in identities {
                    guard !rosterEventIdentities.contains(identity) else {
                        throw .invalidAnonymousMailboxProjection
                    }
                    guard mailboxIdentities.insert(identity).inserted else {
                        throw .invalidAnonymousMailboxProjection
                    }
                }
                contributorAnonymousIdentities = identities
                conductorAnonymousCapabilities = []

            case let (.conductor, .conductor(capabilities)):
                guard capabilities.count == expectedAnonymousCount else {
                    throw .invalidAnonymousMailboxProjection
                }
                for capability in capabilities {
                    guard capability.channel == .anonymous else {
                        throw .invalidAnonymousMailboxProjection
                    }
                    let identity = capability.recipientEventIdentity
                    guard !rosterEventIdentities.contains(identity) else {
                        throw .invalidAnonymousMailboxProjection
                    }
                    guard mailboxIdentities.insert(identity).inserted else {
                        throw .invalidAnonymousMailboxProjection
                    }
                }
                contributorAnonymousIdentities = nil
                conductorAnonymousCapabilities = capabilities.sorted {
                    $0.recipientEventIdentity.lexicographicallyPrecedes(
                        $1.recipientEventIdentity
                    )
                }

            default:
                throw .roleProjectionMismatch
            }

            self.binding = binding
            localRole = role
            controlRecipients = rosterIdentities.compactMap {
                controlRecipientsByIdentity[$0]
            }
            localControlRecipientCapability = localCapability
            self.bootstrap = bootstrap
            self.relaySelection = relaySelection
            contributorAnonymousRecipientIdentities =
                contributorAnonymousIdentities
            conductorAnonymousRecipientCapabilities =
                conductorAnonymousCapabilities
            self.dependencies = dependencies
        }

        /// Provisions and authorizes the complete inbound runtime once without opening a route.
        func provisionInboundRuntime() async throws(Failure)
            -> InboundRuntimeProvisioning {
            var recipients: [(RoutePurpose, Transport.RecipientCapability)] = [
                (.inboundControl, localControlRecipientCapability),
            ]
            if localRole == .conductor {
                recipients.append(
                    contentsOf: conductorAnonymousRecipientCapabilities.map {
                        (.inboundAnonymous, $0)
                    }
                )
            }
            let requests = recipients.map {
                routeRequest(
                    purpose: $0.0,
                    recipientEventIdentity: $0.1.recipientEventIdentity
                )
            }
            let groups = try await provision(
                requests,
                needsSubscriptions: true,
                claimsInboundRoutes: true
            )
            let capabilitiesByIdentity = Dictionary(
                uniqueKeysWithValues: recipients.map {
                    ($0.1.recipientEventIdentity, $0.1)
                }
            )
            let recipientRouteGroups = groups.map { group in
                guard let capability = capabilitiesByIdentity[
                    group.recipientEventIdentity
                ] else {
                    preconditionFailure(
                        "Validated inbound allocation lost its recipient capability."
                    )
                }
                return FanIn.RecipientRouteGroup(
                    recipient: capability,
                    routes: group.routes,
                    subscriptionIdentifiers: group.subscriptionIdentifiers
                )
            }
            return .init(
                role: localRole,
                bootstrap: bootstrap,
                recipientRouteGroups: recipientRouteGroups,
                relaySelection: relaySelection
            )
        }

        nonisolated var controlRouteProvider: ControlPublisher.RouteProvider {
            { [self] requests in
                try await provideControlRoutes(requests)
            }
        }

        nonisolated var anonymousRouteProvider:
            AnonymousPublisher.PurposefulRouteProvider {
            { [self] kind, requests in
                try await provideAnonymousRoutes(kind, requests: requests)
            }
        }

        private func provideControlRoutes(
            _ requests: [ControlPublisher.RecipientRouteRequest]
        ) async throws -> [ControlPublisher.RecipientRouteGroup] {
            let receivedIdentities = requests.map(\.recipientEventIdentity)
            let expectedIdentities = controlRecipients.map {
                $0.eventVerificationKey.rawRepresentation
            }
            guard receivedIdentities.count == expectedIdentities.count,
                  Set(receivedIdentities) == Set(expectedIdentities) else {
                throw Failure.invalidRouteRequestSet
            }
            let groups = try await provision(
                receivedIdentities.map {
                    routeRequest(
                        purpose: .outboundControl,
                        recipientEventIdentity: $0
                    )
                },
                needsSubscriptions: false,
                claimsInboundRoutes: false
            )
            return groups.map {
                .init(
                    recipientEventIdentity: $0.recipientEventIdentity,
                    routes: $0.routes
                )
            }
        }

        private func provideAnonymousRoutes(
            _ kind: AnonymousPublisher.PublicationKind,
            requests: [AnonymousPublisher.RecipientRouteRequest]
        ) async throws -> [AnonymousPublisher.RecipientRouteGroup] {
            guard localRole == .contributor else {
                throw Failure.invalidRouteRequestSet
            }
            guard let contributorAnonymousRecipientIdentities else {
                throw Failure.invalidRouteRequestSet
            }
            let purpose: RoutePurpose
            let requiresCompleteSet: Bool
            switch kind {
            case .components:
                purpose = .outboundAnonymousComponents
                requiresCompleteSet = true
            case .bchSignatures:
                purpose = .outboundAnonymousBCHSignatures
                requiresCompleteSet = false
            }
            let receivedIdentities = requests.map(\.recipientEventIdentity)
            let receivedSet = Set(receivedIdentities)
            let allocatedSet = Set(contributorAnonymousRecipientIdentities)
            guard receivedSet.count == receivedIdentities.count,
                  receivedSet.isSubset(of: allocatedSet),
                  !requiresCompleteSet
                    || receivedSet == allocatedSet else {
                throw Failure.invalidRouteRequestSet
            }
            let groups = try await provision(
                receivedIdentities.map {
                    routeRequest(
                        purpose: purpose,
                        recipientEventIdentity: $0
                    )
                },
                needsSubscriptions: false,
                claimsInboundRoutes: false
            )
            return groups.map {
                .init(
                    recipientEventIdentity: $0.recipientEventIdentity,
                    routes: $0.routes
                )
            }
        }

        private func routeRequest(
            purpose: RoutePurpose,
            recipientEventIdentity: Data
        ) -> RouteRequest {
            .init(
                binding: binding,
                purpose: purpose,
                recipientEventIdentity: recipientEventIdentity,
                endpoints: relaySelection.endpoints
            )
        }

        private func provision(
            _ requests: [RouteRequest],
            needsSubscriptions: Bool,
            claimsInboundRoutes: Bool
        ) async throws(Failure) -> [OwnedRouteGroup] {
            guard Set(requests.map(\.recipientEventIdentity)).count
                    == requests.count else {
                throw .invalidRouteRequestSet
            }
            let startingClaims: Claims
            switch state {
            case let .ready(claims):
                guard !claimsInboundRoutes
                        || !claims.inboundRoutesWereIssued else {
                    throw .inboundRoutesAlreadyIssued
                }
                startingClaims = claims
                state = .provisioning
            case .provisioning:
                throw .concurrentProvisioning
            case .terminal:
                throw .inputAfterTermination
            }

            guard !requests.isEmpty else {
                var claims = startingClaims
                if claimsInboundRoutes {
                    claims.inboundRoutesWereIssued = true
                }
                state = .ready(claims)
                return []
            }

            let provisioned: [ProvisionedRouteGroup]
            do {
                provisioned = try await dependencies.provisionRoutes(requests)
            } catch {
                let failure: Failure = Task.isCancelled
                    ? .cancelled : .routeProvisioningFailed
                state = .terminal
                throw failure
            }
            guard !Task.isCancelled else {
                await Self.close(provisioned)
                state = .terminal
                throw .cancelled
            }

            do {
                let result = try validate(
                    provisioned,
                    for: requests,
                    needsSubscriptions: needsSubscriptions,
                    startingClaims: startingClaims,
                    claimsInboundRoutes: claimsInboundRoutes
                )
                state = .ready(result.claims)
                return result.groups
            } catch let failure as Failure {
                await Self.close(provisioned)
                state = .terminal
                throw failure
            } catch {
                await Self.close(provisioned)
                state = .terminal
                throw .routeAllocationMismatch
            }
        }

        private func validate(
            _ provisioned: [ProvisionedRouteGroup],
            for requests: [RouteRequest],
            needsSubscriptions: Bool,
            startingClaims: Claims,
            claimsInboundRoutes: Bool
        ) throws -> (groups: [OwnedRouteGroup], claims: Claims) {
            guard provisioned.count == requests.count else {
                throw Failure.routeAllocationMismatch
            }
            let requestsByIdentity = Dictionary(
                uniqueKeysWithValues: requests.map {
                    ($0.recipientEventIdentity, $0)
                }
            )
            var provisionedByIdentity: [Data: ProvisionedRouteGroup] = [:]
            for group in provisioned {
                guard provisionedByIdentity.updateValue(
                    group,
                    forKey: group.recipientEventIdentity
                ) == nil else {
                    throw Failure.routeAllocationMismatch
                }
            }
            guard Set(provisionedByIdentity.keys)
                    == Set(requestsByIdentity.keys) else {
                throw Failure.routeAllocationMismatch
            }

            var claims = startingClaims
            var result: [OwnedRouteGroup] = []
            result.reserveCapacity(requests.count)
            for request in requests {
                guard let group = provisionedByIdentity[
                    request.recipientEventIdentity
                ] else {
                    throw Failure.routeAllocationMismatch
                }
                guard group.routes.count
                        == OpalFusion.Mosaic.OpalMainnetAlpha.relayCount else {
                    throw Failure.routeAllocationMismatch
                }
                var endpoints: Set<PostManifestRelayEndpoint> = []
                var routes: [PostManifestRelayRoute] = []
                var subscriptions: [
                    PostManifestRelayEndpoint: Nostr.SubscriptionIdentifier
                ] = [:]
                for provisionedRoute in group.routes {
                    guard endpoints.insert(provisionedRoute.endpoint).inserted else {
                        throw Failure.routeAllocationMismatch
                    }
                    let connectionIdentity = ObjectIdentifier(
                        provisionedRoute.connection as AnyObject
                    )
                    guard claims.connectionIdentities.insert(
                        connectionIdentity
                    ).inserted else {
                        throw Failure.duplicateConnection
                    }
                    guard claims.isolationLeases.insert(
                        provisionedRoute.isolationLease
                    ).inserted else {
                        throw Failure.duplicateIsolationLease
                    }
                    routes.append(
                        .init(
                            endpoint: provisionedRoute.endpoint,
                            connection: provisionedRoute.connection
                        )
                    )
                    if needsSubscriptions {
                        let identifier: Nostr.SubscriptionIdentifier
                        do {
                            identifier = try dependencies
                                .makeSubscriptionIdentifier(
                                    request,
                                    provisionedRoute.endpoint
                                )
                        } catch {
                            throw Failure.subscriptionIdentifierUnavailable
                        }
                        guard claims.subscriptionIdentifiers.insert(
                            identifier
                        ).inserted else {
                            throw Failure.duplicateSubscriptionIdentifier
                        }
                        subscriptions[provisionedRoute.endpoint] = identifier
                    }
                }
                guard endpoints == Set(relaySelection.endpoints) else {
                    throw Failure.routeAllocationMismatch
                }
                result.append(
                    .init(
                        recipientEventIdentity:
                            request.recipientEventIdentity,
                        routes: routes,
                        subscriptionIdentifiers: subscriptions
                    )
                )
            }
            if claimsInboundRoutes {
                claims.inboundRoutesWereIssued = true
            }
            return (result, claims)
        }

        private static func close(
            _ groups: [ProvisionedRouteGroup]
        ) async {
            await withTaskGroup(of: Void.self) { tasks in
                var connectionIdentities: Set<ObjectIdentifier> = []
                for route in groups.flatMap(\.routes) {
                    guard connectionIdentities.insert(
                        ObjectIdentifier(route.connection as AnyObject)
                    ).inserted else {
                        continue
                    }
                    tasks.addTask {
                        await route.connection.close()
                    }
                }
            }
        }
    }
}

// MosaicMainnetAlphaPostManifestMailboxRouteProvisioningValidator.swift

import Foundation
import OpalCrypto
import Synchronization
import Testing
@testable import OpalFusion

@Suite("Mosaic mainnet-alpha mailbox and route provisioning")
struct MosaicMainnetAlphaPostManifestMailboxRouteProvisioningValidator {
    typealias Alpha = OpalFusion.Mosaic.OpalMainnetAlpha
    typealias Attempt = OpalFusion.Mosaic.Attempt
    typealias Bridge = Alpha.PostManifestContributorTransportBridge
    typealias ControlBridge = Alpha.PostManifestControlPublicationBridge
    typealias Fixture = MosaicMainnetAlphaAdmissionLedgerFixtures
    typealias LocalAttempt = OpalFusion.Mosaic.LocalAttempt
    typealias Nostr = OpalFusion.Mosaic.NostrNamespace
    typealias Owner = Alpha.PostManifestAttemptTransportOwner
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
                throw ProbeFailure.injected
            }
        }
    }

    private final class SubscriptionFactory: Sendable {
        private let nextValue = Mutex(0)

        func make(
            _: Owner.RouteRequest,
            _: Tracker.Endpoint
        ) throws -> Nostr.SubscriptionIdentifier {
            let value = nextValue.withLock { value in
                defer { value += 1 }
                return value
            }
            return try .init("mailbox-\(value)")
        }
    }

    private final class UnexpectedConnectionActivityProbe: Sendable {
        private struct Counts: Sendable {
            var opens = 0
            var sends = 0
        }

        private let counts = Mutex(Counts())

        func recordOpen() {
            counts.withLock { $0.opens += 1 }
        }

        func recordSend() {
            counts.withLock { $0.sends += 1 }
        }

        var snapshot: (opens: Int, sends: Int) {
            counts.withLock { ($0.opens, $0.sends) }
        }
    }

    private actor ProvisionedConnection:
        OpalFusion.Mosaic.TorWebSocketConnectioning
    {
        private let activity: UnexpectedConnectionActivityProbe

        init(activity: UnexpectedConnectionActivityProbe) {
            self.activity = activity
        }

        func open(
            maximumIncomingMessageByteCount _: Int
        ) async throws -> MessageStream {
            activity.recordOpen()
            throw ProbeFailure.injected
        }

        func send(text _: String) async throws {
            activity.recordSend()
            throw ProbeFailure.injected
        }

        func close() async {}
    }

    private actor RouteProvisioner {
        enum Fault: Sendable {
            case none
            case wrongEndpoint
            case duplicateLease
            case reuseConnectionOnSecondInvocation
        }

        private let fault: Fault
        private var invocationCount = 0
        private var nextLease = 1
        private var retainedConnection: ProvisionedConnection?
        nonisolated let activity = UnexpectedConnectionActivityProbe()

        init(fault: Fault = .none) {
            self.fault = fault
        }

        func provision(
            _ requests: [Owner.RouteRequest]
        ) -> [Owner.ProvisionedRouteGroup] {
            invocationCount += 1
            return requests.enumerated().map { groupIndex, request in
                var firstGroupLease: Owner.IsolationLease?
                let routes = request.endpoints.enumerated().map {
                    endpointIndex,
                    endpoint in
                    let connection: ProvisionedConnection
                    if case .reuseConnectionOnSecondInvocation = fault,
                       invocationCount > 1,
                       groupIndex == 0,
                       endpointIndex == 0,
                       let retainedConnection {
                        connection = retainedConnection
                    } else {
                        connection = .init(activity: activity)
                        if retainedConnection == nil {
                            retainedConnection = connection
                        }
                    }

                    let lease: Owner.IsolationLease
                    if case .duplicateLease = fault,
                       groupIndex == 0,
                       endpointIndex > 0,
                       let firstGroupLease {
                        lease = firstGroupLease
                    } else {
                        lease = .init(
                            opaqueIdentifier: Self.uuid(nextLease)
                        )
                        nextLease += 1
                        if endpointIndex == 0 {
                            firstGroupLease = lease
                        }
                    }
                    let selectedEndpoint: Tracker.Endpoint
                    if case .wrongEndpoint = fault,
                       groupIndex == 0,
                       endpointIndex == 0 {
                        selectedEndpoint = .init(
                            validatedIdentifier: "foreign-relay"
                        )
                    } else {
                        selectedEndpoint = endpoint
                    }
                    return Owner.ProvisionedRoute(
                        endpoint: selectedEndpoint,
                        connection: connection,
                        isolationLease: lease
                    )
                }
                return .init(
                    recipientEventIdentity:
                        request.recipientEventIdentity,
                    routes: routes
                )
            }
        }

        func snapshot() -> Int {
            invocationCount
        }

        private static func uuid(_ value: Int) -> UUID {
            UUID(
                uuid: (
                    0, 0, 0, 0, 0, 0, 0, 0,
                    0, 0, 0, 0,
                    UInt8(truncatingIfNeeded: value >> 24),
                    UInt8(truncatingIfNeeded: value >> 16),
                    UInt8(truncatingIfNeeded: value >> 8),
                    UInt8(truncatingIfNeeded: value)
                )
            )
        }
    }

    private struct RosterFixture {
        let peerIdentities: [Attempt.ControlIdentity]
        let validatedAttempt: Attempt
        let manifest: Alpha.RoundManifest
        let proposalValidation: Alpha.ManifestProposalValidation
        let attemptIdentifier: LocalAttempt.AttemptIdentifier
        let generationIdentifier: LocalAttempt.GenerationIdentifier
        let materialIdentifier: LocalAttempt.MaterialIdentifier
        let controlRecipients: [ControlBridge.Recipient]
        let controlRecipientCapabilities: [
            Attempt.ControlIdentity: Transport.RecipientCapability
        ]
        let anonymousRecipientCapabilities: [Transport.RecipientCapability]
        let contributorAnonymousIdentities: [
            Attempt.ControlIdentity: [Data]
        ]
        let contributorAnonymousVerificationKeys: [
            Attempt.ControlIdentity: [
                OpalCrypto.Signature.BIP340.VerificationKey
            ]
        ]
        let relaySelection: Alpha.PostManifestRelaySelectionValidation
    }

    @Test("Bind and defend the minimum-roster mailbox and route shape")
    func validateMinimumRosterProvisioning() async throws {
        let fixture = try makeRosterFixture()
        try await bindMinimumRosterProvisioning(fixture)
        try await rejectSubstitutionBeforeOpeningRoutes(fixture)
        try await rejectReuseAndTransferOwnershipOnce(fixture)
    }

    private func bindMinimumRosterProvisioning(
        _ fixture: RosterFixture
    ) async throws {
        let provisioner = RouteProvisioner()
        let subscriptions = SubscriptionFactory()
        var owners: [
            Attempt.ControlIdentity: Owner
        ] = [:]
        var inboundGroups: [Alpha.PostManifestRelayFanIn.RecipientRouteGroup] = []

        for localControlIdentity in fixture.peerIdentities {
            let owner = try makeOwner(
                localControlIdentity: localControlIdentity,
                fixture: fixture,
                provisioner: provisioner,
                subscriptions: subscriptions
            )
            owners[localControlIdentity] = owner
            let provisioning = try await owner.provisionInboundRuntime()
            let groups = provisioning.recipientRouteGroups
            let expectedCount = owner.localRole == .conductor
                ? 1 + fixture.manifest.core.roster.contributors.count
                    * Alpha.componentCountPerContributor
                : 1
            #expect(groups.count == expectedCount)
            inboundGroups.append(contentsOf: groups)
        }

        #expect(owners.count == 7)
        #expect(
            inboundGroups.count
                == 7 + 6 * Alpha.componentCountPerContributor
        )
        #expect(
            inboundGroups.filter { $0.recipient.channel == .control }.count
                == 7
        )
        #expect(
            inboundGroups.filter { $0.recipient.channel == .anonymous }.count
                == 6 * Alpha.componentCountPerContributor
        )
        #expect(
            Set(
                inboundGroups.filter {
                    $0.recipient.channel == .anonymous
                }.map { $0.recipient.recipientEventIdentity }
            )
                == Set(
                    fixture.contributorAnonymousIdentities.values
                        .flatMap { $0 }
                )
        )
        #expect(
            Set(inboundGroups.map { $0.recipient.recipientEventIdentity }).count
                == inboundGroups.count
        )
        #expect(
            inboundGroups.allSatisfy {
                $0.routes.count == Alpha.relayCount
                    && Set($0.routes.map(\.endpoint))
                        == Set(fixture.relaySelection.endpoints)
                    && $0.subscriptionIdentifiers.count == Alpha.relayCount
            }
        )
        let inboundConnections = inboundGroups.flatMap(\.routes).map {
            ObjectIdentifier($0.connection as AnyObject)
        }
        #expect(Set(inboundConnections).count == inboundConnections.count)
        let inboundSubscriptions = inboundGroups.flatMap {
            $0.subscriptionIdentifiers.values
        }
        #expect(
            Set(inboundSubscriptions).count == inboundSubscriptions.count
        )

        let representative = try #require(
            fixture.peerIdentities.first {
                $0 != fixture.manifest.core.roster.conductor
            }
        )
        let representativeOwner = try #require(
            owners[representative]
        )
        let identities = try #require(
            fixture.contributorAnonymousIdentities[
                representative
            ]
        )
        let anonymousGroups = try await representativeOwner
            .anonymousRouteProvider(
                .components,
                identities.map {
                    .init(recipientEventIdentity: $0)
                }
            )
        #expect(
            anonymousGroups.count == Alpha.componentCountPerContributor
        )
        #expect(
            anonymousGroups.allSatisfy {
                $0.routes.count == Alpha.relayCount
            }
        )

        let controlGroups = try await representativeOwner.controlRouteProvider(
            fixture.controlRecipients.map {
                .init(
                    recipientEventIdentity:
                        $0.eventVerificationKey.rawRepresentation
                )
            }
        )
        #expect(controlGroups.count == 7)
        #expect(controlGroups.allSatisfy { $0.routes.count == Alpha.relayCount })

        let controlScalar = try #require(
            MosaicMainnetAlphaFixtures.scalarByte(
                for: representative
            )
        )
        let managedBridge = try Bridge(
            bootstrap: bootstrap(
                for: representative,
                fixture: fixture
            ),
            manifest: fixture.manifest,
            controlSigningKey: try signingKey(Int(controlScalar)),
            controlEventSigningKey: try signingKey(9_000),
            relaySelection: fixture.relaySelection,
            codingLimits: try relayCodingLimits(),
            maximumPendingRelayOutputCount: 1,
            dependencies: .init(
                makeExpiryUnixSeconds: { _ in
                    throw ProbeFailure.injected
                },
                makeControlLayerTimestamps: { _ in
                    throw ProbeFailure.injected
                },
                makeAnonymousLayerTimestamps: { _ in
                    throw ProbeFailure.injected
                },
                attemptTransportOwner: representativeOwner,
                awaitAnonymousPublicationPermit: { _ in
                    throw ProbeFailure.injected
                }
            )
        )
        await managedBridge.requestStop()
        #expect(
            await managedBridge.waitForTermination()
                == .terminal(.cancelled)
        )

        #expect(await provisioner.snapshot() == 9)
        let activity = provisioner.activity.snapshot
        #expect(activity.opens == 0)
        #expect(activity.sends == 0)
    }

    private func rejectSubstitutionBeforeOpeningRoutes(
        _ fixture: RosterFixture
    ) async throws {
        let contributor = try #require(
            fixture.peerIdentities.first {
                $0 != fixture.manifest.core.roster.conductor
            }
        )
        let contributorBootstrap = bootstrap(
            for: contributor,
            fixture: fixture
        )
        let context = try ControlBridge.Context(
            validating: fixture.manifest,
            against: contributorBootstrap
        )
        let validProjection = try projection(
            localControlIdentity: contributor,
            fixture: fixture,
            binding: .init(context: context, role: .contributor)
        )
        let conductor = try #require(
            fixture.peerIdentities.first {
                $0 == fixture.manifest.core.roster.conductor
            }
        )
        let conductorContext = try ControlBridge.Context(
            validating: fixture.manifest,
            against: bootstrap(for: conductor, fixture: fixture)
        )
        let inertProvisioner = RouteProvisioner()
        let subscriptions = SubscriptionFactory()

        #expect(
            throws: Owner.InitializationError
                .mailboxProjectionBindingMismatch
        ) {
            _ = try Owner(
                bootstrap: contributorBootstrap,
                manifest: fixture.manifest,
                mailboxProjection: try projection(
                    localControlIdentity: contributor,
                    fixture: fixture,
                    binding: .init(
                        context: conductorContext,
                        role: .contributor
                    )
                ),
                relaySelection: fixture.relaySelection,
                dependencies: dependencies(
                    provisioner: inertProvisioner,
                    subscriptions: subscriptions
                )
            )
        }

        #expect(
            throws: Owner.InitializationError.invalidControlMailboxProjection
        ) {
            _ = try Owner(
                bootstrap: contributorBootstrap,
                manifest: fixture.manifest,
                mailboxProjection: .init(
                    binding: validProjection.binding,
                    controlRecipients: validProjection.controlRecipients.filter {
                        $0.controlIdentity != contributor
                    },
                    localControlRecipientCapability:
                        validProjection.localControlRecipientCapability,
                    anonymous: validProjection.anonymous
                ),
                relaySelection: fixture.relaySelection,
                dependencies: dependencies(
                    provisioner: inertProvisioner,
                    subscriptions: subscriptions
                )
            )
        }

        let foreignControlIdentity = try #require(
            fixture.peerIdentities.first { $0 != contributor }
        )
        let foreignControlCapability = try #require(
            fixture.controlRecipientCapabilities[foreignControlIdentity]
        )
        #expect(
            throws: Owner.InitializationError.invalidControlMailboxProjection
        ) {
            _ = try Owner(
                bootstrap: contributorBootstrap,
                manifest: fixture.manifest,
                mailboxProjection: .init(
                    binding: validProjection.binding,
                    controlRecipients: validProjection.controlRecipients,
                    localControlRecipientCapability: foreignControlCapability,
                    anonymous: validProjection.anonymous
                ),
                relaySelection: fixture.relaySelection,
                dependencies: dependencies(
                    provisioner: inertProvisioner,
                    subscriptions: subscriptions
                )
            )
        }
        #expect(await inertProvisioner.snapshot() == 0)

        let wrongEndpointProvisioner = RouteProvisioner(
            fault: .wrongEndpoint
        )
        let wrongEndpointOwner = try Owner(
            bootstrap: contributorBootstrap,
            manifest: fixture.manifest,
            mailboxProjection: validProjection,
            relaySelection: fixture.relaySelection,
            dependencies: dependencies(
                provisioner: wrongEndpointProvisioner,
                subscriptions: subscriptions
            )
        )
        await #expect(throws: Owner.Failure.routeAllocationMismatch) {
            _ = try await wrongEndpointOwner
                .provisionInboundRuntime()
        }
        #expect(wrongEndpointProvisioner.activity.snapshot.opens == 0)
        #expect(wrongEndpointProvisioner.activity.snapshot.sends == 0)

        let duplicateLeaseProvisioner = RouteProvisioner(
            fault: .duplicateLease
        )
        let duplicateLeaseOwner = try Owner(
            bootstrap: contributorBootstrap,
            manifest: fixture.manifest,
            mailboxProjection: validProjection,
            relaySelection: fixture.relaySelection,
            dependencies: dependencies(
                provisioner: duplicateLeaseProvisioner,
                subscriptions: subscriptions
            )
        )
        await #expect(throws: Owner.Failure.duplicateIsolationLease) {
            _ = try await duplicateLeaseOwner
                .provisionInboundRuntime()
        }
        #expect(duplicateLeaseProvisioner.activity.snapshot.opens == 0)
        #expect(duplicateLeaseProvisioner.activity.snapshot.sends == 0)
    }

    private func rejectReuseAndTransferOwnershipOnce(
        _ fixture: RosterFixture
    ) async throws {
        let contributor = try #require(
            fixture.peerIdentities.first {
                $0 != fixture.manifest.core.roster.conductor
            }
        )
        let provisioner = RouteProvisioner(
            fault: .reuseConnectionOnSecondInvocation
        )
        let subscriptions = SubscriptionFactory()
        let owner = try makeOwner(
            localControlIdentity: contributor,
            fixture: fixture,
            provisioner: provisioner,
            subscriptions: subscriptions
        )

        let inbound = try await owner.provisionInboundRuntime()
        #expect(inbound.recipientRouteGroups.count == 1)
        await #expect(throws: Owner.Failure.inboundRoutesAlreadyIssued) {
            _ = try await owner.provisionInboundRuntime()
        }

        await #expect(throws: Owner.Failure.duplicateConnection) {
            _ = try await owner.controlRouteProvider(
                fixture.controlRecipients.map {
                    .init(
                        recipientEventIdentity:
                            $0.eventVerificationKey.rawRepresentation
                    )
                }
            )
        }
        #expect(await provisioner.snapshot() == 2)
        let activity = provisioner.activity.snapshot
        #expect(activity.opens == 0)
        #expect(activity.sends == 0)
    }

    private func makeRosterFixture() throws -> RosterFixture {
        let componentVerificationKey = try MosaicMainnetAlphaFixtures
            .rsaVerificationKey()
        let bchSignatureVerificationKey = try MosaicMainnetAlphaFixtures
            .bchSignatureRSAVerificationKey()
        let election = try MosaicMainnetAlphaFixtures.makeElection(
            candidateCount: 7
        )
        let manifest = try MosaicMainnetAlphaFixtures.makeManifest(
            election: election,
            verificationKey: componentVerificationKey,
            bchSignatureVerificationKey: bchSignatureVerificationKey
        )
        let proposalValidation = try Alpha.ManifestProposalValidation(
            validating: manifest.core,
            against: try MosaicMainnetAlphaFixtures
                .makeManifestProposalContext(election: election)
        )
        let roster = manifest.core.roster
        let controlRecipientCapabilities = try Dictionary(
            uniqueKeysWithValues: roster.controlIdentities.enumerated().map {
                index,
                identity in
                (
                    identity,
                    Transport.RecipientCapability(
                        channel: .control,
                        signingKey: try signingKey(100 + index)
                    )
                )
            }
        )
        let controlRecipients = try roster.controlIdentities.map { identity in
            let capability = try #require(
                controlRecipientCapabilities[identity]
            )
            return ControlBridge.Recipient(
                controlIdentity: identity,
                eventVerificationKey: try .init(
                    rawRepresentation: capability.recipientEventIdentity
                )
            )
        }
        let anonymousRecipientCapabilities = try (
            0 ..< roster.contributors.count
                * Alpha.componentCountPerContributor
        ).map {
            Transport.RecipientCapability(
                channel: .anonymous,
                signingKey: try signingKey(1_000 + $0)
            )
        }
        let contributorAnonymousIdentities = Dictionary(
            uniqueKeysWithValues: roster.contributors.enumerated().map {
                contributorIndex,
                identity in
                let first = contributorIndex
                    * Alpha.componentCountPerContributor
                let last = first + Alpha.componentCountPerContributor
                return (
                    identity,
                    anonymousRecipientCapabilities[first ..< last].map {
                        $0.recipientEventIdentity
                    }
                )
            }
        )
        let contributorAnonymousVerificationKeys = try Dictionary(
            uniqueKeysWithValues: contributorAnonymousIdentities.map {
                identity,
                eventIdentities in
                (
                    identity,
                    try eventIdentities.map {
                        try OpalCrypto.Signature.BIP340.VerificationKey(
                            rawRepresentation: $0
                        )
                    }
                )
            }
        )
        let endpoints = (1 ... Alpha.relayCount).map {
            Tracker.Endpoint(validatedIdentifier: "provisioning-relay-\($0)")
        }
        let relaySelection = try Alpha.PostManifestRelaySelectionValidation(
            manifestRelaySetDigest: manifest.core.relaySetDigest,
            endpoints: endpoints,
            using: ExactRelaySelectionValidator(
                digest: manifest.core.relaySetDigest,
                endpoints: Set(endpoints)
            )
        )
        return .init(
            peerIdentities: [roster.conductor] + roster.contributors,
            validatedAttempt: Fixture.makeValidatedAttempt(
                election: election
            ),
            manifest: manifest,
            proposalValidation: proposalValidation,
            attemptIdentifier: .init(
                validatedBytes: [UInt8](repeating: 0xA1, count: 32)
            ),
            generationIdentifier: .init(
                opaqueBytes: [UInt8](repeating: 0xA2, count: 32)
            ),
            materialIdentifier: .init(
                opaqueBytes: [UInt8](repeating: 0xA3, count: 32)
            ),
            controlRecipients: controlRecipients,
            controlRecipientCapabilities: controlRecipientCapabilities,
            anonymousRecipientCapabilities: anonymousRecipientCapabilities,
            contributorAnonymousIdentities:
                contributorAnonymousIdentities,
            contributorAnonymousVerificationKeys:
                contributorAnonymousVerificationKeys,
            relaySelection: relaySelection
        )
    }

    private func makeOwner(
        localControlIdentity: Attempt.ControlIdentity,
        fixture: RosterFixture,
        provisioner: RouteProvisioner,
        subscriptions: SubscriptionFactory
    ) throws -> Owner {
        let bootstrap = bootstrap(
            for: localControlIdentity,
            fixture: fixture
        )
        let context = try ControlBridge.Context(
            validating: fixture.manifest,
            against: bootstrap
        )
        let role: OpalFusion.Mosaic.Role = localControlIdentity
            == fixture.manifest.core.roster.conductor
            ? .conductor : .contributor
        return try Owner(
            bootstrap: bootstrap,
            manifest: fixture.manifest,
            mailboxProjection: try projection(
                localControlIdentity: localControlIdentity,
                fixture: fixture,
                binding: .init(context: context, role: role)
            ),
            relaySelection: fixture.relaySelection,
            dependencies: dependencies(
                provisioner: provisioner,
                subscriptions: subscriptions
            )
        )
    }

    private func projection(
        localControlIdentity: Attempt.ControlIdentity,
        fixture: RosterFixture,
        binding: Owner.Binding
    ) throws -> Owner.AuthenticatedMailboxProjection {
        let localCapability = try #require(
            fixture.controlRecipientCapabilities[localControlIdentity]
        )
        let anonymous: Owner.AnonymousMailboxProjection
        if localControlIdentity
                == fixture.manifest.core.roster.conductor {
            anonymous = .conductor(
                fixture.anonymousRecipientCapabilities
            )
        } else {
            anonymous = .contributor(
                try #require(
                    fixture.contributorAnonymousVerificationKeys[
                        localControlIdentity
                    ]
                )
            )
        }
        return .init(
            binding: binding,
            controlRecipients: fixture.controlRecipients,
            localControlRecipientCapability: localCapability,
            anonymous: anonymous
        )
    }

    private func dependencies(
        provisioner: RouteProvisioner,
        subscriptions: SubscriptionFactory
    ) -> Owner.Dependencies {
        .init(
            provisionRoutes: { requests in
                await provisioner.provision(requests)
            },
            makeSubscriptionIdentifier: subscriptions.make
        )
    }

    private func bootstrap(
        for localControlIdentity: Attempt.ControlIdentity,
        fixture: RosterFixture
    ) -> Alpha.PostManifestRuntimeDriver.Bootstrap {
        .init(
            validatedAttempt: fixture.validatedAttempt,
            attemptIdentifier: fixture.attemptIdentifier,
            generationIdentifier: fixture.generationIdentifier,
            materialIdentifier: fixture.materialIdentifier,
            localControlIdentity: localControlIdentity,
            proposalValidation: fixture.proposalValidation
        )
    }

    private func signingKey(
        _ scalar: Int
    ) throws -> OpalCrypto.Secp256k1.SigningKey {
        try .init(rawRepresentation: scalarBytes(scalar))
    }

    private func scalarBytes(_ scalar: Int) -> Data {
        precondition(scalar > 0)
        var value = UInt32(scalar).bigEndian
        var result = Data(repeating: 0, count: 28)
        withUnsafeBytes(of: &value) { result.append(contentsOf: $0) }
        return result
    }

    private func relayCodingLimits() throws
        -> Nostr.RelayMessageCodingLimits {
        try .init(
            maximumFrameByteCount:
                Alpha.nip59MaximumPublicationFrameByteCount,
            maximumFiltersPerRequest: 1,
            maximumValuesPerFilter: 1,
            maximumMessageStringByteCount: 256,
            event: (try Transport.codingLimits).event
        )
    }

    private enum ProbeFailure: Error {
        case injected
    }
}

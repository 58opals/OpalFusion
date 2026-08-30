// MosaicMainnetAlphaMinimumRosterCompositionValidator.swift

import Foundation
import OpalCrypto
import Testing
@testable import OpalFusion

@Suite("Mosaic mainnet-alpha minimum-roster composition")
struct MosaicMainnetAlphaMinimumRosterCompositionValidator {
    typealias Alpha = OpalFusion.Mosaic.OpalMainnetAlpha
    typealias Attempt = OpalFusion.Mosaic.Attempt
    typealias Bridge = Alpha.PostManifestContributorTransportBridge
    typealias ControlBridge = Alpha.PostManifestControlPublicationBridge
    typealias Driver = Alpha.PostManifestRuntimeDriver
    typealias FanIn = Alpha.PostManifestRelayFanIn
    typealias Fixture = MosaicMainnetAlphaAdmissionLedgerFixtures
    typealias Ingress = Alpha.PostManifestTransportIngress
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
                throw ProbeFailure.unexpectedInvocation
            }
        }
    }

    private struct RejectingPreviousOutputSource:
        OpalFusion.Host.MosaicPreviousOutputSource
    {
        func resolvePreviousOutputs(
            for _: [OpalFusion.Host.MosaicPreviousOutputRequest]
        ) async throws -> [OpalFusion.Host.MosaicPreviousOutput] {
            throw ProbeFailure.unexpectedInvocation
        }
    }

    private actor UnexpectedAuthorityProbe {
        private(set) var invocationCount = 0

        func record() {
            invocationCount += 1
        }
    }

    private actor RuntimeProbe {
        private var terminalState: Driver.State?
        private var waiters: [CheckedContinuation<Driver.State?, Never>] = []
        private(set) var state: Ingress.State = .idle

        nonisolated var endpoint: FanIn.RuntimeEndpoint {
            .init(
                start: { await self.start() },
                state: { await self.state },
                submit: { _ in .rejected(.runtimeRejected) },
                inputSourceDidTerminate: {
                    await self.inputSourceDidTerminate($0)
                },
                stop: { await self.stop() },
                waitForTermination: { await self.waitForTermination() }
            )
        }

        func start() -> Bool {
            guard state == .idle else { return false }
            state = .running
            return true
        }

        func inputSourceDidTerminate(
            _ termination: Alpha.InputSourceTermination
        ) -> Bool {
            guard state == .running else { return false }
            finish(
                .conductor(
                    .terminal(.failed(.inputSourceTerminated(termination)))
                )
            )
            return true
        }

        func stop() {
            guard terminalState == nil else { return }
            finish(
                .conductor(
                    .terminal(.cancelled(during: .manifestAgreement))
                )
            )
        }

        func waitForTermination() async -> Driver.State? {
            if let terminalState { return terminalState }
            return await withCheckedContinuation { continuation in
                waiters.append(continuation)
            }
        }

        private func finish(_ terminalState: Driver.State) {
            self.terminalState = terminalState
            state = .terminal(terminalState)
            let waiters = waiters
            self.waiters.removeAll()
            for waiter in waiters {
                waiter.resume(returning: terminalState)
            }
        }
    }

    private actor RejectingWalletHost:
        OpalFusion.Host.MosaicCompleteTransactionHost
    {
        private(set) var invocationCount = 0

        func reserveMosaicContribution(
            for _: OpalFusion.Host.MosaicReservationRequest
        ) async throws -> OpalFusion.Host.MosaicReservationLease {
            invocationCount += 1
            throw ProbeFailure.unexpectedInvocation
        }

        func finalizeMosaicTransaction(
            for _: OpalFusion.Host.MosaicTransactionSigningRequest
        ) async throws -> OpalFusion.Host.FinalizedTransaction {
            invocationCount += 1
            throw ProbeFailure.unexpectedInvocation
        }

        func releaseMosaicReservation(
            _: OpalFusion.Host.MosaicReservationReference
        ) async throws {
            invocationCount += 1
            throw ProbeFailure.unexpectedInvocation
        }

        func commitMosaicReservation(
            _: OpalFusion.Host.MosaicReservationReference,
            finalizedTransaction _: OpalFusion.Host.FinalizedTransaction
        ) async throws {
            invocationCount += 1
            throw ProbeFailure.unexpectedInvocation
        }

        func commitMosaicReservation(
            _: OpalFusion.Host.MosaicReservationReference,
            completeTransaction _: OpalFusion.Host.MosaicCompleteTransaction
        ) async throws {
            invocationCount += 1
            throw ProbeFailure.unexpectedInvocation
        }
    }

    private struct Peer {
        let role: OpalFusion.Mosaic.Role
        let localControlIdentity: Attempt.ControlIdentity
        let fanIn: FanIn
        let connections: [ScriptedMosaicTorWebSocketConnection]
        let maximumInboundFrameByteCount: Int
        let contributorBridge: Bridge?
        let walletHost: RejectingWalletHost?
    }

    @Test(
        "Compose the BCH-mainnet minimum roster through no-broadcast fan-in",
        .timeLimit(.minutes(1))
    )
    func composeMinimumRoster() async throws {
        let componentVerificationKey = try MosaicMainnetAlphaFixtures
            .rsaVerificationKey()
        let bchSignatureVerificationKey = try MosaicMainnetAlphaFixtures
            .bchSignatureRSAVerificationKey()
        let conductor = try Fixture.makeHarness(
            candidateCount: 7,
            localRole: .conductor,
            verificationKey: componentVerificationKey,
            bchSignatureVerificationKey: bchSignatureVerificationKey
        )
        let contributors = try (0 ..< 6).map { index in
            try Fixture.makeHarness(
                candidateCount: 7,
                localRole: .contributor,
                localContributorIndex: index,
                verificationKey: componentVerificationKey,
                bchSignatureVerificationKey: bchSignatureVerificationKey
            )
        }
        let harnesses = [conductor] + contributors
        let manifest = conductor.manifest
        let roster = manifest.core.roster

        #expect(roster.contributors.count == 6)
        #expect(roster.controlIdentities.count == 7)
        #expect(
            manifest.core.networkGenesisHash
                == Alpha.mainnetGenesisHash
        )
        #expect(
            manifest.core.transactionProfileIdentifier
                == OpalFusion.Mosaic.Profile.opalMainnetAlpha
                    .transactionProfileIdentifier
        )
        #expect(Set(harnesses.map(\.localControlIdentity)).count == 7)
        #expect(harnesses.allSatisfy { $0.manifest == manifest })
        #expect(
            harnesses.allSatisfy {
                $0.attemptIdentifier == conductor.attemptIdentifier
                    && $0.generationIdentifier
                        == conductor.generationIdentifier
                    && $0.materialIdentifier == conductor.materialIdentifier
            }
        )

        let recipientKeys = try Dictionary(
            uniqueKeysWithValues: roster.controlIdentities.enumerated().map {
                index,
                identity in
                (identity, try signingKey(UInt8(30 + index)))
            }
        )
        let controlRecipients = try roster.controlIdentities.map { identity in
            let key = try #require(recipientKeys[identity])
            return ControlBridge.Recipient(
                controlIdentity: identity,
                eventVerificationKey: key.bip340VerificationKey
            )
        }
        let endpoints = (1 ... Alpha.relayCount).map {
            Tracker.Endpoint(validatedIdentifier: "composition-relay-\($0)")
        }
        let relaySelection = try Alpha
            .PostManifestRelaySelectionValidation(
                manifestRelaySetDigest: manifest.core.relaySetDigest,
                endpoints: endpoints,
                using: ExactRelaySelectionValidator(
                    digest: manifest.core.relaySetDigest,
                    endpoints: Set(endpoints)
                )
            )
        let authorityProbe = UnexpectedAuthorityProbe()
        var peers: [Peer] = []
        peers.reserveCapacity(harnesses.count)
        for (peerIndex, harness) in harnesses.enumerated() {
            peers.append(
                try await makePeer(
                    harness: harness,
                    peerIndex: peerIndex,
                    recipientKeys: recipientKeys,
                    controlRecipients: controlRecipients,
                    endpoints: endpoints,
                    relaySelection: relaySelection,
                    authorityProbe: authorityProbe
                )
            )
        }

        #expect(peers.filter { $0.role == .conductor }.count == 1)
        #expect(peers.filter { $0.role == .contributor }.count == 6)
        #expect(Set(peers.map(\.localControlIdentity)) == Set(roster.controlIdentities))

        try await withThrowingTaskGroup(of: Void.self) { group in
            for peer in peers {
                let fanIn = peer.fanIn
                group.addTask {
                    try await fanIn.start()
                }
            }
            try await group.waitForAll()
        }
        for peer in peers {
            #expect(await peer.fanIn.state == .running)
        }

        await withTaskGroup(of: Void.self) { group in
            for peer in peers {
                let fanIn = peer.fanIn
                group.addTask {
                    await fanIn.stop()
                }
            }
        }
        for peer in peers {
            #expect(await peer.fanIn.waitForTermination() == .stopped)
            #expect(await peer.fanIn.waitForTermination() == .stopped)
            for connection in peer.connections {
                #expect(await connection.openCount == 1)
                #expect(await connection.closeCount == 1)
                #expect(await connection.sentTexts.count == 1)
                #expect(
                    await connection.openedMaximumIncomingMessageByteCount
                        == peer.maximumInboundFrameByteCount
                )
            }
            if let bridge = peer.contributorBridge {
                await bridge.requestStop()
                #expect(
                    await bridge.waitForTermination()
                        == .terminal(.cancelled)
                )
                #expect(
                    await bridge.waitForTermination()
                        == .terminal(.cancelled)
                )
            }
            if let walletHost = peer.walletHost {
                #expect(await walletHost.invocationCount == 0)
            }
        }
        #expect(await authorityProbe.invocationCount == 0)
    }

    private func makePeer(
        harness: Fixture.Harness,
        peerIndex: Int,
        recipientKeys: [
            Attempt.ControlIdentity: OpalCrypto.Secp256k1.SigningKey
        ],
        controlRecipients: [ControlBridge.Recipient],
        endpoints: [Tracker.Endpoint],
        relaySelection: Alpha.PostManifestRelaySelectionValidation,
        authorityProbe: UnexpectedAuthorityProbe
    ) async throws -> Peer {
        let bootstrap = Driver.Bootstrap(
            validatedAttempt: Fixture.makeValidatedAttempt(
                election: harness.election
            ),
            attemptIdentifier: harness.attemptIdentifier,
            generationIdentifier: harness.generationIdentifier,
            materialIdentifier: harness.materialIdentifier,
            localControlIdentity: harness.localControlIdentity,
            proposalValidation: harness.proposalValidation
        )
        let localRecipientKey = try #require(
            recipientKeys[harness.localControlIdentity]
        )
        let recipient = Transport.RecipientCapability(
            channel: .control,
            signingKey: localRecipientKey
        )
        let connections = (0 ..< Alpha.relayCount).map { _ in
            ScriptedMosaicTorWebSocketConnection()
        }
        let subscriptions = try subscriptionIdentifiers(
            peerIndex: peerIndex,
            endpoints: endpoints
        )
        let routes = zip(endpoints, connections).map {
            Alpha.PostManifestRelayRoute(
                endpoint: $0.0,
                connection: $0.1
            )
        }
        let codingLimits = try relayCodingLimits(
            subscriptionIdentifiers: Array(subscriptions.values)
        )

        let role: OpalFusion.Mosaic.Role
        let routeGroup: FanIn.RecipientRouteGroup
        let contributorBridge: Bridge?
        let walletHost: RejectingWalletHost?
        if harness.localControlIdentity == harness.manifest.core.roster.conductor {
            role = .conductor
            routeGroup = .init(
                recipient: recipient,
                routes: routes,
                subscriptionIdentifiers: subscriptions
            )
            contributorBridge = nil
            walletHost = nil
        } else {
            role = .contributor
            let controlScalar = try #require(
                MosaicMainnetAlphaFixtures.scalarByte(
                    for: harness.localControlIdentity
                )
            )
            let context = try ControlBridge.Context(
                validating: harness.manifest,
                against: bootstrap
            )
            let anonymousRecipientVerificationKeys = try
                (0 ..< Alpha.componentCountPerContributor).map {
                    try signingKey(UInt8(150 + peerIndex + $0))
                        .bip340VerificationKey
                }
            let attemptTransportOwner = try Owner(
                bootstrap: bootstrap,
                manifest: harness.manifest,
                mailboxProjection: .init(
                    binding: .init(context: context, role: .contributor),
                    controlRecipients: controlRecipients,
                    localControlRecipientCapability: recipient,
                    anonymous: .contributor(
                        anonymousRecipientVerificationKeys
                    )
                ),
                relaySelection: relaySelection,
                dependencies: .init(
                    provisionRoutes: { _ in
                        throw ProbeFailure.unexpectedInvocation
                    },
                    makeSubscriptionIdentifier: { _, _ in
                        throw ProbeFailure.unexpectedInvocation
                    }
                )
            )
            let bridge = try Bridge(
                bootstrap: bootstrap,
                manifest: harness.manifest,
                controlSigningKey: try signingKey(controlScalar),
                controlEventSigningKey: try signingKey(
                    UInt8(60 + peerIndex)
                ),
                relaySelection: relaySelection,
                codingLimits: codingLimits,
                maximumPendingRelayOutputCount: 1,
                dependencies: .init(
                    makeExpiryUnixSeconds: { _ in
                        throw ProbeFailure.unexpectedInvocation
                    },
                    makeControlLayerTimestamps: { _ in
                        throw ProbeFailure.unexpectedInvocation
                    },
                    makeAnonymousLayerTimestamps: { _ in
                        throw ProbeFailure.unexpectedInvocation
                    },
                    makeControlSignatureAuxiliaryRandomness: {
                        try .init(
                            rawRepresentation: Data(
                                repeating: 0xA5,
                                count: 32
                            )
                        )
                    },
                    attemptTransportOwner: attemptTransportOwner,
                    publicationJournal: try .init(
                        context: .init(
                            publicationContext: context,
                            relaySelection: relaySelection
                        ),
                        persistence: .init(
                            loadSnapshot: { _ in nil },
                            appendRecords: { _, _, _ in }
                        )
                    ),
                    awaitAnonymousPublicationPermit: { _ in
                        throw ProbeFailure.unexpectedInvocation
                    }
                )
            )
            routeGroup = .init(
                recipient: recipient,
                routes: routes,
                subscriptionIdentifiers: subscriptions
            )
            let host = RejectingWalletHost()
            let execution = bridge.makeExecutionDependencies(
                transactionHost: host,
                previousOutputSource: RejectingPreviousOutputSource(),
                makeLocalContributionMaterial: { _, _ in
                    await authorityProbe.record()
                    throw ProbeFailure.unexpectedInvocation
                }
            )
            _ = execution
            contributorBridge = bridge
            walletHost = host
        }

        let runtimeProbe = RuntimeProbe()
        let fanIn = try FanIn.makeComponent(
            role: role,
            maximumAnonymousRecipientCount:
                harness.manifest.core.roster.contributors.count
                    * Alpha.componentCountPerContributor,
            manifestRelaySetDigest: harness.manifest.core.relaySetDigest,
            recipientRouteGroups: [routeGroup],
            relaySelection: relaySelection,
            runtime: runtimeProbe.endpoint,
            codingLimits: codingLimits,
            maximumPendingEventCount: 8
        )
        return .init(
            role: role,
            localControlIdentity: harness.localControlIdentity,
            fanIn: fanIn,
            connections: connections,
            maximumInboundFrameByteCount:
                codingLimits.maximumFrameByteCount,
            contributorBridge: contributorBridge,
            walletHost: walletHost
        )
    }

    private func subscriptionIdentifiers(
        peerIndex: Int,
        endpoints: [Tracker.Endpoint]
    ) throws -> [Tracker.Endpoint: Nostr.SubscriptionIdentifier] {
        try Dictionary(
            uniqueKeysWithValues: endpoints.enumerated().map {
                endpointIndex,
                endpoint in
                (
                    endpoint,
                    try Nostr.SubscriptionIdentifier(
                        "composition-\(peerIndex)-\(endpointIndex)"
                    )
                )
            }
        )
    }

    private func relayCodingLimits(
        subscriptionIdentifiers: [Nostr.SubscriptionIdentifier]
    ) throws -> Nostr.RelayMessageCodingLimits {
        let identifierWidth = try subscriptionIdentifiers.map {
            try JSONEncoder().encode($0.value).count
        }.max() ?? 0
        let maximumFrameByteCount = Data("[\"EVENT\",".utf8).count
            + identifierWidth + 1
            + Alpha.nip59MaximumGiftWrapJSONByteCount + 1
        return try .init(
            maximumFrameByteCount: maximumFrameByteCount,
            maximumFiltersPerRequest: 1,
            maximumValuesPerFilter: 1,
            maximumMessageStringByteCount: 256,
            event: (try Transport.codingLimits).event
        )
    }

    private func signingKey(
        _ scalarByte: UInt8
    ) throws -> OpalCrypto.Secp256k1.SigningKey {
        try .init(
            rawRepresentation: Data(repeating: 0, count: 31)
                + Data([scalarByte])
        )
    }

    private enum ProbeFailure: Error {
        case unexpectedInvocation
    }
}

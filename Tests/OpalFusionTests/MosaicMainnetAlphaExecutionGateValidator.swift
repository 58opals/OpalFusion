// MosaicMainnetAlphaExecutionGateValidator.swift

import Foundation
import OpalCrypto
import Testing
@testable import OpalFusion

@Suite("Mosaic mainnet-alpha execution gate")
struct MosaicMainnetAlphaExecutionGateValidator {
    typealias Alpha = OpalFusion.Mosaic.OpalMainnetAlpha
    typealias ControlBridge = Alpha.PostManifestControlPublicationBridge
    typealias Driver = Alpha.PostManifestRuntimeDriver
    typealias FanIn = Alpha.PostManifestRelayFanIn
    typealias Fixture = MosaicMainnetAlphaAdmissionLedgerFixtures
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

    private actor RejectingAuthority:
        OpalFusion.Host.MosaicCompleteTransactionHost,
        OpalFusion.Host.MosaicPreviousOutputSource
    {
        private(set) var invocationCount = 0

        func record() {
            invocationCount += 1
        }

        func reserveMosaicContribution(
            for _: OpalFusion.Host.MosaicReservationRequest
        ) async throws -> OpalFusion.Host.MosaicReservationLease {
            record()
            throw ProbeFailure.unexpectedInvocation
        }

        func finalizeMosaicTransaction(
            for _: OpalFusion.Host.MosaicTransactionSigningRequest
        ) async throws -> OpalFusion.Host.FinalizedTransaction {
            record()
            throw ProbeFailure.unexpectedInvocation
        }

        func releaseMosaicReservation(
            _: OpalFusion.Host.MosaicReservationReference
        ) async throws {
            record()
            throw ProbeFailure.unexpectedInvocation
        }

        func commitMosaicReservation(
            _: OpalFusion.Host.MosaicReservationReference,
            finalizedTransaction _: OpalFusion.Host.FinalizedTransaction
        ) async throws {
            record()
            throw ProbeFailure.unexpectedInvocation
        }

        func commitMosaicReservation(
            _: OpalFusion.Host.MosaicReservationReference,
            completeTransaction _: OpalFusion.Host.MosaicCompleteTransaction
        ) async throws {
            record()
            throw ProbeFailure.unexpectedInvocation
        }

        func resolvePreviousOutputs(
            for _: [OpalFusion.Host.MosaicPreviousOutputRequest]
        ) async throws -> [OpalFusion.Host.MosaicPreviousOutput] {
            record()
            throw ProbeFailure.unexpectedInvocation
        }
    }

    @Test("Admit only one exact private runtime before authority access")
    func admitOnlyExactAttemptBeforeAuthorityAccess() async throws {
        let componentVerificationKey = try MosaicMainnetAlphaFixtures
            .rsaVerificationKey()
        let bchSignatureVerificationKey = try MosaicMainnetAlphaFixtures
            .bchSignatureRSAVerificationKey()
        let harness = try Fixture.makeHarness(
            localRole: .contributor,
            verificationKey: componentVerificationKey,
            bchSignatureVerificationKey: bchSignatureVerificationKey
        )
        let bootstrap = makeBootstrap(harness)

        let genericInput = MosaicRuntimeSessionDriverInputProbe()
        let genericOutput = MosaicRuntimeSessionDriverOutputProbe()
        #expect(
            throws: OpalFusion.Mosaic.RuntimeSessionDriver
                .InitializationError.unsupportedProfile(.opalMainnetAlpha)
        ) {
            _ = try OpalFusion.Mosaic.RuntimeSessionDriver(
                runtimeSession: MosaicRuntimeSessionDriverFixture.makeSession(
                    profile: .opalMainnetAlpha
                ),
                dependencies: .init(
                    openInputStream: { await genericInput.open() },
                    closeInputSource: { await genericInput.close() },
                    outputSink: { genericOutput.record($0) }
                )
            )
        }

        let endpoints = (1 ... Alpha.relayCount).map {
            Tracker.Endpoint(validatedIdentifier: "gate-relay-\($0)")
        }
        let subscriptions = try Dictionary(
            uniqueKeysWithValues: endpoints.enumerated().map { index, endpoint in
                (endpoint, try Nostr.SubscriptionIdentifier("gate-\(index)"))
            }
        )
        let relaySelection = try Alpha.PostManifestRelaySelectionValidation(
            manifestRelaySetDigest: harness.manifest.core.relaySetDigest,
            endpoints: endpoints,
            using: ExactRelaySelectionValidator(
                digest: harness.manifest.core.relaySetDigest,
                endpoints: Set(endpoints)
            )
        )
        let connections = (0 ..< Alpha.relayCount).map { _ in
            ScriptedMosaicTorWebSocketConnection()
        }
        let owner = try makeOwner(
            harness: harness,
            bootstrap: bootstrap,
            endpoints: endpoints,
            subscriptions: subscriptions,
            connections: connections,
            relaySelection: relaySelection
        )
        let provisioning = try await owner.provisionInboundRuntime()
        let authority = RejectingAuthority()
        let roleDependencies = contributorDependencies(authority: authority)
        let ingressDependencies = Alpha.PostManifestTransportIngress
            .Dependencies(
                currentUnixSeconds: {
                    harness.manifest.core.deadlines.phaseStart + 1
                },
                beforeDriverStart: {
                    await authority.record()
                }
            )
        let codingLimits = try relayCodingLimits(
            subscriptions: Array(subscriptions.values)
        )

        let otherLocalIdentity = harness.manifest.core.roster.conductor
        let foreignHarness = try Fixture.makeHarness(
            candidateCount: 8,
            localRole: .contributor,
            verificationKey: componentVerificationKey,
            bchSignatureVerificationKey: bchSignatureVerificationKey
        )
        let substitutions: [Driver.Bootstrap] = [
            .init(
                validatedAttempt: bootstrap.validatedAttempt,
                attemptIdentifier: .init(validatedBytes: [0xF1]),
                generationIdentifier: bootstrap.generationIdentifier,
                materialIdentifier: bootstrap.materialIdentifier,
                localControlIdentity: bootstrap.localControlIdentity,
                proposalValidation: bootstrap.proposalValidation
            ),
            .init(
                validatedAttempt: bootstrap.validatedAttempt,
                attemptIdentifier: bootstrap.attemptIdentifier,
                generationIdentifier: .init(opaqueBytes: [0xF2]),
                materialIdentifier: bootstrap.materialIdentifier,
                localControlIdentity: bootstrap.localControlIdentity,
                proposalValidation: bootstrap.proposalValidation
            ),
            .init(
                validatedAttempt: bootstrap.validatedAttempt,
                attemptIdentifier: bootstrap.attemptIdentifier,
                generationIdentifier: bootstrap.generationIdentifier,
                materialIdentifier: .init(opaqueBytes: [0xF3]),
                localControlIdentity: bootstrap.localControlIdentity,
                proposalValidation: bootstrap.proposalValidation
            ),
            .init(
                validatedAttempt: bootstrap.validatedAttempt,
                attemptIdentifier: bootstrap.attemptIdentifier,
                generationIdentifier: bootstrap.generationIdentifier,
                materialIdentifier: bootstrap.materialIdentifier,
                localControlIdentity: otherLocalIdentity,
                proposalValidation: bootstrap.proposalValidation
            ),
            .init(
                validatedAttempt: Fixture.makeValidatedAttempt(
                    election: foreignHarness.election
                ),
                attemptIdentifier: bootstrap.attemptIdentifier,
                generationIdentifier: bootstrap.generationIdentifier,
                materialIdentifier: bootstrap.materialIdentifier,
                localControlIdentity: bootstrap.localControlIdentity,
                proposalValidation: foreignHarness.proposalValidation
            ),
        ]
        for substitution in substitutions {
            #expect(
                throws: FanIn.InitializationError
                    .runtimeAuthorizationMismatch
            ) {
                _ = try FanIn(
                    bootstrap: substitution,
                    roleDependencies: roleDependencies,
                    inboundRuntimeProvisioning: provisioning,
                    ingressDependencies: ingressDependencies,
                    codingLimits: codingLimits,
                    maximumPendingEventCount: 1
                )
            }
        }
        #expect(
            throws: FanIn.InitializationError
                .runtimeAuthorizationMismatch
        ) {
            _ = try FanIn(
                bootstrap: bootstrap,
                roleDependencies: conductorDependencies(authority: authority),
                inboundRuntimeProvisioning: provisioning,
                ingressDependencies: ingressDependencies,
                codingLimits: codingLimits,
                maximumPendingEventCount: 1
            )
        }

        let fanIn = try FanIn(
            bootstrap: bootstrap,
            roleDependencies: roleDependencies,
            inboundRuntimeProvisioning: provisioning,
            ingressDependencies: ingressDependencies,
            codingLimits: codingLimits,
            maximumPendingEventCount: 1
        )
        #expect(await fanIn.state == .idle)
        #expect(
            throws: FanIn.InitializationError
                .runtimeAuthorizationAlreadyUsed
        ) {
            _ = try FanIn(
                bootstrap: bootstrap,
                roleDependencies: roleDependencies,
                inboundRuntimeProvisioning: provisioning,
                ingressDependencies: ingressDependencies,
                codingLimits: codingLimits,
                maximumPendingEventCount: 1
            )
        }

        #expect(await genericInput.openCount == 0)
        #expect(await genericInput.closeCount == 0)
        #expect(genericOutput.outputs.isEmpty)
        #expect(await authority.invocationCount == 0)
        for connection in connections {
            #expect(await connection.openCount == 0)
            #expect(await connection.sentTexts.isEmpty)
        }
    }

    private func makeOwner(
        harness: Fixture.Harness,
        bootstrap: Driver.Bootstrap,
        endpoints: [Tracker.Endpoint],
        subscriptions: [Tracker.Endpoint: Nostr.SubscriptionIdentifier],
        connections: [ScriptedMosaicTorWebSocketConnection],
        relaySelection: Alpha.PostManifestRelaySelectionValidation
    ) throws -> Owner {
        let roster = harness.manifest.core.roster
        let capabilities = try Dictionary(
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
        let recipients = try roster.controlIdentities.map { identity in
            let capability = try #require(capabilities[identity])
            return ControlBridge.Recipient(
                controlIdentity: identity,
                eventVerificationKey:
                    capability.signingKey.bip340VerificationKey
            )
        }
        let localCapability = try #require(
            capabilities[harness.localControlIdentity]
        )
        let anonymousKeys = try (0 ..< Alpha.componentCountPerContributor).map {
            try signingKey(200 + $0).bip340VerificationKey
        }
        let context = try ControlBridge.Context(
            validating: harness.manifest,
            against: bootstrap
        )
        let localIdentity = localCapability.recipientEventIdentity
        return try Owner(
            bootstrap: bootstrap,
            manifest: harness.manifest,
            mailboxProjection: .init(
                binding: .init(context: context, role: .contributor),
                controlRecipients: recipients,
                localControlRecipientCapability: localCapability,
                anonymous: .contributor(anonymousKeys)
            ),
            relaySelection: relaySelection,
            dependencies: .init(
                provisionRoutes: { requests in
                    guard requests.count == 1,
                          requests[0].recipientEventIdentity == localIdentity else {
                        throw ProbeFailure.unexpectedInvocation
                    }
                    return [
                        .init(
                            recipientEventIdentity: localIdentity,
                            routes: zip(endpoints, connections).enumerated().map {
                                index,
                                pair in
                                .init(
                                    endpoint: pair.0,
                                    connection: pair.1,
                                    isolationLease: .init(
                                        opaqueIdentifier: Self.uuid(index + 1)
                                    )
                                )
                            }
                        ),
                    ]
                },
                makeSubscriptionIdentifier: { request, endpoint in
                    guard request.recipientEventIdentity == localIdentity,
                          let subscription = subscriptions[endpoint] else {
                        throw ProbeFailure.unexpectedInvocation
                    }
                    return subscription
                }
            )
        )
    }

    private func contributorDependencies(
        authority: RejectingAuthority
    ) -> Driver.RoleDependencies {
        .contributor(
            .init(
                execution: .init(
                    transactionHost: authority,
                    previousOutputSource: authority,
                    makeLocalContributionMaterial: { _, _ in
                        await authority.record()
                        throw ProbeFailure.unexpectedInvocation
                    },
                    publishPlayerCommit: { _ in
                        await authority.record()
                        throw ProbeFailure.unexpectedInvocation
                    },
                    publishAnonymousComponents: { _ in
                        await authority.record()
                        throw ProbeFailure.unexpectedInvocation
                    },
                    publishPreSignAcknowledgement: { _ in
                        await authority.record()
                        throw ProbeFailure.unexpectedInvocation
                    },
                    publishLocalBCHSignatures: { _ in
                        await authority.record()
                        throw ProbeFailure.unexpectedInvocation
                    }
                ),
                expectedReservationExpiration: Date(
                    timeIntervalSince1970: 1_900_000_000
                ),
                maximumPendingInputCount: 1,
                makeReservationRequest: { _ in
                    await authority.record()
                    throw ProbeFailure.unexpectedInvocation
                }
            )
        )
    }

    private func conductorDependencies(
        authority: RejectingAuthority
    ) -> Driver.RoleDependencies {
        .conductor(
            .init(
                componentAuthorizationEvaluator: .unavailable,
                bchSignatureAuthorizationEvaluator: .unavailable,
                previousOutputSource: authority,
                maximumPendingInputCount: 1,
                handoffPublication: { _ in
                    await authority.record()
                    throw ProbeFailure.unexpectedInvocation
                }
            )
        )
    }

    private func makeBootstrap(
        _ harness: Fixture.Harness
    ) -> Driver.Bootstrap {
        .init(
            validatedAttempt: Fixture.makeValidatedAttempt(
                election: harness.election
            ),
            attemptIdentifier: harness.attemptIdentifier,
            generationIdentifier: harness.generationIdentifier,
            materialIdentifier: harness.materialIdentifier,
            localControlIdentity: harness.localControlIdentity,
            proposalValidation: harness.proposalValidation
        )
    }

    private func relayCodingLimits(
        subscriptions: [Nostr.SubscriptionIdentifier]
    ) throws -> Nostr.RelayMessageCodingLimits {
        let identifierWidth = try subscriptions.map {
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
        _ scalar: Int
    ) throws -> OpalCrypto.Secp256k1.SigningKey {
        precondition(scalar > 0)
        var value = UInt32(scalar).bigEndian
        var bytes = Data(repeating: 0, count: 28)
        withUnsafeBytes(of: &value) { bytes.append(contentsOf: $0) }
        return try .init(rawRepresentation: bytes)
    }

    private static func uuid(_ value: Int) -> UUID {
        UUID(
            uuid: (
                0, 0, 0, 0, 0, 0, 0, 0,
                0, 0, 0, 0, 0, 0, 0,
                UInt8(truncatingIfNeeded: value)
            )
        )
    }

    private enum ProbeFailure: Error {
        case unexpectedInvocation
    }
}

// MosaicMainnetAlphaPostManifestRuntimeDriverValidator.swift

import Foundation
import OpalCrypto
import Testing
@testable import OpalFusion

@Suite("Mosaic mainnet-alpha post-manifest runtime driver")
struct MosaicMainnetAlphaPostManifestRuntimeDriverValidator {
    typealias Alpha = OpalFusion.Mosaic.OpalMainnetAlpha
    typealias Driver = Alpha.PostManifestRuntimeDriver
    typealias Fixture = MosaicMainnetAlphaAdmissionLedgerFixtures
    typealias Nostr = OpalFusion.Mosaic.NostrNamespace
    typealias Transport = Alpha.PostManifestNIP59Transport

    enum RoleCase: CaseIterable, Sendable {
        case contributor
        case conductor

        var role: OpalFusion.Mosaic.Role {
            switch self {
            case .contributor: .contributor
            case .conductor: .conductor
            }
        }
    }

    private struct RejectingPreviousOutputSource:
        OpalFusion.Host.MosaicPreviousOutputSource {
        func resolvePreviousOutputs(
            for _: [OpalFusion.Host.MosaicPreviousOutputRequest]
        ) async throws -> [OpalFusion.Host.MosaicPreviousOutput] {
            throw ProbeFailure.unexpectedInvocation
        }
    }

    @Test("Select one matching role and preserve the one-shot lifecycle", arguments: RoleCase.allCases)
    func selectMatchingRole(_ roleCase: RoleCase) async throws {
        let harness = try Fixture.makeHarness(localRole: roleCase.role)
        let construction = try makeDriver(harness: harness, roleCase: roleCase)
        let manifestRun = try makeManifestRun(harness)

        #expect(
            !(try await submit(
                try controlInput(
                    manifestRun.reservation,
                    harness: harness
                ),
                to: construction.driver
            ))
        )
        #expect(
            !(await construction.driver.inputSourceDidTerminate(.finished))
        )
        #expect(await construction.driver.state == idleState(for: roleCase))

        await construction.driver.start()
        await construction.driver.start()
        #expect(await construction.driver.state == runningState(for: roleCase))

        await construction.driver.stop()
        #expect(
            !(await construction.driver.inputSourceDidTerminate(.failed))
        )
        #expect(
            await construction.driver.waitForTermination()
                == cancelledState(for: roleCase)
        )
        #expect(
            !(try await submit(
                try controlInput(
                    manifestRun.reservation,
                    harness: harness
                ),
                to: construction.driver
            ))
        )
        #expect(await construction.host.reservationRequests.isEmpty)
    }

    @Test("Reject dependencies for the opposite local role", arguments: RoleCase.allCases)
    func rejectOppositeRoleDependencies(_ roleCase: RoleCase) async throws {
        let harness = try Fixture.makeHarness(localRole: roleCase.role)
        let receivedRole: OpalFusion.Mosaic.Role = roleCase == .contributor
            ? .conductor
            : .contributor
        let construction = try makeDependencies(
            roleCase: roleCase == .contributor ? .conductor : .contributor
        )

        #expect(
            throws: Driver.InitializationError.dependencyRoleMismatch(
                expected: roleCase.role,
                received: receivedRole
            )
        ) {
            _ = try Driver(
                bootstrap: bootstrap(harness),
                dependencies: construction.dependencies
            )
        }
        #expect(await construction.host.reservationRequests.isEmpty)
        #expect(await construction.host.signingRequests.isEmpty)
        #expect(await construction.host.completeCommits.isEmpty)
    }

    @Test("Reject a nonpositive input buffer limit", arguments: RoleCase.allCases)
    func rejectInvalidInputBuffer(_ roleCase: RoleCase) throws {
        let harness = try Fixture.makeHarness(localRole: roleCase.role)
        let dependencies = try makeDependencies(
            roleCase: roleCase,
            maximumPendingInputCount: 0
        ).dependencies

        #expect(throws: Driver.InitializationError.invalidInputBufferLimit) {
            _ = try Driver(
                bootstrap: bootstrap(harness),
                dependencies: dependencies
            )
        }
    }

    @Test("Reject an invalid attempt bootstrap before invoking dependencies")
    func rejectInvalidBootstrap() async throws {
        let harness = try Fixture.makeHarness(localRole: .contributor)
        let construction = try makeDependencies(roleCase: .contributor)
        let invalidAttempt = OpalFusion.Mosaic.Attempt(
            configuration: .init(profile: .opalMainnetAlpha)
        )
        let invalidBootstrap = Driver.Bootstrap(
            validatedAttempt: invalidAttempt,
            attemptIdentifier: harness.attemptIdentifier,
            generationIdentifier: harness.generationIdentifier,
            materialIdentifier: harness.materialIdentifier,
            localControlIdentity: harness.localControlIdentity,
            proposalValidation: harness.proposalValidation
        )

        #expect(
            throws: Driver.InitializationError.runtimeConstructionFailed
        ) {
            _ = try Driver(
                bootstrap: invalidBootstrap,
                dependencies: construction.dependencies
            )
        }
        #expect(await construction.host.reservationRequests.isEmpty)
        #expect(await construction.host.signingRequests.isEmpty)
        #expect(await construction.host.completeCommits.isEmpty)
    }

    @Test("Route authenticated control through the selected role", arguments: RoleCase.allCases)
    func routeControlDelivery(_ roleCase: RoleCase) async throws {
        let harness = try Fixture.makeHarness(localRole: roleCase.role)
        let construction = try makeDriver(harness: harness, roleCase: roleCase)
        let manifestRun = try makeManifestRun(harness)
        await construction.driver.start()

        #expect(
            try await submit(
                try controlInput(
                    manifestRun.reservation,
                    harness: harness
                ),
                to: construction.driver
            )
        )
        for fragment in manifestRun.fragments {
            #expect(
                try await submit(
                    try controlInput(
                        fragment,
                        harness: harness
                    ),
                    to: construction.driver
                )
            )
        }

        let expected: Driver.State = switch roleCase {
        case .contributor:
            .contributor(.terminal(.failed(.invalidReservationRequest)))
        case .conductor:
            .conductor(.terminal(.failed(.authorizationKeyMismatch)))
        }
        #expect(await construction.driver.waitForTermination() == expected)
        #expect(await construction.host.reservationRequests.isEmpty)
    }

    @Test("Bind transport authentication to the driver's exact phase start")
    func rejectCallerRelabeledTransportContext() async throws {
        let harness = try Fixture.makeHarness(localRole: .conductor)
        let construction = try makeDriver(
            harness: harness,
            roleCase: .conductor
        )
        let run = try makeManifestRun(harness)
        let sender = try [UInt8(9), UInt8(10)]
            .map(signingKey)
            .first {
                Array($0.bip340VerificationKey.rawRepresentation)
                    == run.reservation.envelope.senderEventIdentity
            }
        let validatedSender = try #require(sender)
        let recipient = try signingKey(12)
        let expectedPhaseStart = harness.manifest.core.deadlines.phaseStart
        let foreignPhaseStart = expectedPhaseStart - 2
        let giftWrap = try Transport.makeControlGiftWrap(
            run.reservation.envelope,
            context: .init(
                attemptIdentifier: harness.attemptIdentifier,
                generationIdentifier: .init(
                    opaqueBytes: [UInt8](repeating: 0xEE, count: 32)
                ),
                phaseStartUnixSeconds: foreignPhaseStart
            ),
            timestamps: .init(
                phaseStartUnixSeconds: foreignPhaseStart,
                currentUnixSeconds: expectedPhaseStart - 1,
                sealCreatedAt: foreignPhaseStart,
                giftWrapCreatedAt: foreignPhaseStart
            ),
            senderEventSigningKey: validatedSender,
            recipientPublicKey: recipient.bip340VerificationKey
        )
        await construction.driver.start()

        do {
            _ = try await construction.driver.submit(
                giftWrap,
                to: .init(channel: .control, signingKey: recipient),
                currentUnixSeconds: expectedPhaseStart
            )
            Issue.record("Expected driver-owned transport context rejection")
        } catch let failure {
            #expect(failure == .invalidRumorTimestamp)
        }
        #expect(await construction.driver.state == .conductor(.running))

        await construction.driver.stop()
        #expect(
            await construction.driver.waitForTermination()
                == .conductor(
                    .terminal(.cancelled(during: .manifestAgreement))
                )
        )
    }

    @Test("Contributor ingress rejects anonymous authority without mutation")
    func rejectAnonymousDeliveryForContributor() async throws {
        let harness = try Fixture.makeHarness(localRole: .contributor)
        let construction = try makeDriver(
            harness: harness,
            roleCase: .contributor
        )
        let input = try anonymousInput(
            harness: harness,
            payloadType: .anonymousComponent
        )
        await construction.driver.start()

        #expect(!(try await submit(input, to: construction.driver)))
        #expect(await construction.driver.state == .contributor(.running))

        await construction.driver.stop()
        #expect(
            await construction.driver.waitForTermination()
                == .contributor(
                    .terminal(.cancelled(during: .manifestAgreement))
                )
        )
        #expect(await construction.host.reservationRequests.isEmpty)
    }

    @Test(
        "Conductor ingress forwards both anonymous payload kinds",
        arguments: Alpha.AnonymousPayloadType.allCases
    )
    func routeAnonymousDeliveryForConductor(
        _ payloadType: Alpha.AnonymousPayloadType
    ) async throws {
        let harness = try Fixture.makeHarness(localRole: .conductor)
        let construction = try makeDriver(
            harness: harness,
            roleCase: .conductor
        )
        let input = try anonymousInput(
            harness: harness,
            payloadType: payloadType
        )
        await construction.driver.start()

        #expect(try await submit(input, to: construction.driver))
        #expect(await construction.driver.inputSourceDidTerminate(.finished))
        await construction.driver.stop()

        #expect(
            await construction.driver.waitForTermination()
                == .conductor(
                    .terminal(.failed(.inputSourceTerminated(.finished)))
                )
        )
        #expect(await construction.host.reservationRequests.isEmpty)
    }

    @Test(
        "Ordered source closure wins over a later stop",
        arguments: RoleCase.allCases,
        [
            Driver.InputSourceTermination.finished,
            Driver.InputSourceTermination.failed,
        ]
    )
    func preserveInputSourceTermination(
        _ roleCase: RoleCase,
        _ termination: Driver.InputSourceTermination
    ) async throws {
        let harness = try Fixture.makeHarness(localRole: roleCase.role)
        let construction = try makeDriver(harness: harness, roleCase: roleCase)
        await construction.driver.start()

        #expect(await construction.driver.inputSourceDidTerminate(termination))
        let manifestRun = try makeManifestRun(harness)
        #expect(
            !(try await submit(
                try controlInput(
                    manifestRun.reservation,
                    harness: harness
                ),
                to: construction.driver
            ))
        )
        await construction.driver.stop()

        let expected: Driver.State = switch (roleCase, termination) {
        case (.contributor, .finished):
            .contributor(
                .terminal(.failed(.inputSourceTerminated(.finished)))
            )
        case (.contributor, .failed):
            .contributor(
                .terminal(.failed(.inputSourceTerminated(.failed)))
            )
        case (.conductor, .finished):
            .conductor(
                .terminal(.failed(.inputSourceTerminated(.finished)))
            )
        case (.conductor, .failed):
            .conductor(
                .terminal(.failed(.inputSourceTerminated(.failed)))
            )
        }
        #expect(await construction.driver.waitForTermination() == expected)
        #expect(
            !(await construction.driver.inputSourceDidTerminate(termination))
        )
        #expect(await construction.host.reservationRequests.isEmpty)
    }

    private struct Construction {
        let driver: Driver
        let host: MosaicRuntimeCoordinatorHostProbe
    }

    private struct DependenciesConstruction {
        let dependencies: Driver.RoleDependencies
        let host: MosaicRuntimeCoordinatorHostProbe
    }

    private struct TransportInput {
        let giftWrap: Nostr.Event
        let recipient: Transport.RecipientCapability
        let currentUnixSeconds: UInt64
    }

    private func makeDriver(
        harness: Fixture.Harness,
        roleCase: RoleCase,
        maximumPendingInputCount: Int = 8
    ) throws -> Construction {
        let construction = try makeDependencies(
            roleCase: roleCase,
            maximumPendingInputCount: maximumPendingInputCount
        )
        return .init(
            driver: try Driver(
                bootstrap: bootstrap(harness),
                dependencies: construction.dependencies
            ),
            host: construction.host
        )
    }

    private func makeDependencies(
        roleCase: RoleCase,
        maximumPendingInputCount: Int = 8
    ) throws -> DependenciesConstruction {
        let expiresAt = Date(timeIntervalSince1970: 1_900_000_000)
        let host = MosaicRuntimeCoordinatorHostProbe(
            lease: try .init(
                reference: .init(
                    identifier: UUID(
                        uuid: (
                            0, 0, 0, 0, 0, 0, 0, 0,
                            0, 0, 0, 0, 0, 0, 0, 0xD1
                        )
                    ),
                    generation: 1
                ),
                expiresAt: expiresAt,
                participantReservation: .init(
                    inputs: [
                        .init(
                            outpointTransactionHashBytes: [UInt8](
                                repeating: 0x31,
                                count: 32
                            ),
                            outpointIndex: 0,
                            amountSatoshis: 100_000,
                            lockingScriptBytes: [0x51]
                        ),
                    ],
                    outputs: [
                        .init(
                            lockingScriptBytes: [0x51],
                            amountSatoshis: 99_000
                        ),
                    ]
                )
            ),
            finalizedTransaction: .init(
                signedFusionTransactionBytes: [0x01]
            )
        )
        let dependencies: Driver.RoleDependencies
        switch roleCase {
        case .contributor:
            dependencies = .contributor(
                .init(
                    execution: .init(
                        transactionHost: host,
                        previousOutputSource: RejectingPreviousOutputSource(),
                        makeLocalContributionMaterial: { _, _ in
                            throw ProbeFailure.unexpectedInvocation
                        },
                        publishPlayerCommit: { _ in
                            throw ProbeFailure.unexpectedInvocation
                        },
                        publishAnonymousComponents: { _ in
                            throw ProbeFailure.unexpectedInvocation
                        },
                        publishPreSignAcknowledgement: { _, _, _ in
                            throw ProbeFailure.unexpectedInvocation
                        },
                        publishLocalBCHSignatures: { _ in
                            throw ProbeFailure.unexpectedInvocation
                        }
                    ),
                    expectedReservationExpiration: expiresAt,
                    maximumPendingInputCount: maximumPendingInputCount,
                    makeReservationRequest: { _ in
                        throw ProbeFailure.unexpectedInvocation
                    }
                )
            )
        case .conductor:
            dependencies = .conductor(
                .init(
                    componentAuthorizationEvaluator: .unavailable,
                    bchSignatureAuthorizationEvaluator: .unavailable,
                    previousOutputSource: RejectingPreviousOutputSource(),
                    maximumPendingInputCount: maximumPendingInputCount,
                    handoffPublication: { _ in
                        throw ProbeFailure.unexpectedInvocation
                    }
                )
            )
        }
        return .init(dependencies: dependencies, host: host)
    }

    private func bootstrap(_ harness: Fixture.Harness) -> Driver.Bootstrap {
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

    private func makeManifestRun(
        _ harness: Fixture.Harness
    ) throws -> Fixture.AggregateRun {
        try Fixture.aggregateRun(
            canonicalBytes: harness.manifest.canonicalBytes,
            kind: .completeManifest,
            sender: harness.election.result.roster.conductor,
            phase: .manifestAgreement,
            sequence: 0,
            harness: harness
        )
    }

    private func anonymousInput(
        harness: Fixture.Harness,
        payloadType: Alpha.AnonymousPayloadType
    ) throws -> TransportInput {
        let senderSigningKey = try OpalCrypto.Secp256k1.SigningKey(
            rawRepresentation: Data(
                [UInt8](repeating: 0, count: 31) + [0x0B]
            )
        )
        let communicationPublicKey = [UInt8](
            senderSigningKey.publicKey.compressedRepresentation
        )
        let recipientEventIdentity = harness.election.result.roster.conductor
            .validatedBytes
        let phase: OpalFusion.Mosaic.Attempt.Phase
        let sequence: UInt64
        switch payloadType {
        case .anonymousComponent:
            phase = .anonymousComponentSubmission
            sequence = 0
        case .bchSignatureSubmission:
            phase = .bchSigning
            sequence = 1
        }
        let envelope = try Alpha.AnonymousEnvelope(
            roundIdentifier: harness.manifest.core.roundIdentifier,
            phase: phase,
            senderCommunicationPublicKey: communicationPublicKey,
            recipientEventIdentity: recipientEventIdentity,
            sequence: sequence,
            payloadType: payloadType,
            expiryUnixSeconds: 1_800_000_060,
            payload: [0x00]
        )
        let recipientScalar = try Fixture.requiredScalarByte(
            for: harness.election.result.roster.conductor
        )
        let recipientKey = try signingKey(recipientScalar)
        let giftWrap = try Transport.makeAnonymousGiftWrap(
            envelope,
            context: runtimeContext(harness),
            timestamps: try layerTimestamps(harness),
            senderCommunicationSigningKey: senderSigningKey,
            recipientPublicKey: recipientKey.bip340VerificationKey
        )
        return .init(
            giftWrap: giftWrap,
            recipient: .init(
                channel: .anonymous,
                signingKey: recipientKey
            ),
            currentUnixSeconds: 1_800_000_000
        )
    }

    private func controlInput(
        _ delivery: Alpha.AdmissionLedger.ControlDelivery,
        harness: Fixture.Harness
    ) throws -> TransportInput {
        let senderKey = try [UInt8(9), UInt8(10)]
            .map(signingKey)
            .first {
                Array($0.bip340VerificationKey.rawRepresentation)
                    == delivery.envelope.senderEventIdentity
            }
        let validatedSenderKey = try #require(senderKey)
        let recipientKey = try signingKey(12)
        let giftWrap = try Transport.makeControlGiftWrap(
            delivery.envelope,
            context: runtimeContext(harness),
            timestamps: try layerTimestamps(harness),
            senderEventSigningKey: validatedSenderKey,
            recipientPublicKey: recipientKey.bip340VerificationKey
        )
        return .init(
            giftWrap: giftWrap,
            recipient: .init(channel: .control, signingKey: recipientKey),
            currentUnixSeconds: 1_800_000_000
        )
    }

    private func submit(
        _ input: TransportInput,
        to driver: Driver
    ) async throws -> Bool {
        try await driver.submit(
            input.giftWrap,
            to: input.recipient,
            currentUnixSeconds: input.currentUnixSeconds
        )
    }

    private func layerTimestamps(
        _ harness: Fixture.Harness
    ) throws -> Transport.LayerTimestamps {
        let phaseStart = harness.manifest.core.deadlines.phaseStart
        return try .init(
            phaseStartUnixSeconds: phaseStart,
            currentUnixSeconds: phaseStart + 1,
            sealCreatedAt: phaseStart,
            giftWrapCreatedAt: phaseStart
        )
    }

    private func runtimeContext(
        _ harness: Fixture.Harness
    ) -> Transport.RuntimeContext {
        .init(
            attemptIdentifier: harness.attemptIdentifier,
            generationIdentifier: harness.generationIdentifier,
            phaseStartUnixSeconds: harness.manifest.core.deadlines.phaseStart
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

    private func idleState(for roleCase: RoleCase) -> Driver.State {
        switch roleCase {
        case .contributor: .contributor(.idle)
        case .conductor: .conductor(.idle)
        }
    }

    private func runningState(for roleCase: RoleCase) -> Driver.State {
        switch roleCase {
        case .contributor: .contributor(.running)
        case .conductor: .conductor(.running)
        }
    }

    private func cancelledState(for roleCase: RoleCase) -> Driver.State {
        switch roleCase {
        case .contributor:
            .contributor(
                .terminal(.cancelled(during: .manifestAgreement))
            )
        case .conductor:
            .conductor(
                .terminal(.cancelled(during: .manifestAgreement))
            )
        }
    }

    private enum ProbeFailure: Error {
        case unexpectedInvocation
    }
}

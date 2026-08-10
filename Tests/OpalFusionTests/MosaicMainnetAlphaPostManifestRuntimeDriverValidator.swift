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
            !(await construction.driver.submit(
                .control(manifestRun.reservation)
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
            !(await construction.driver.submit(
                .control(manifestRun.reservation)
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
            await construction.driver.submit(.control(manifestRun.reservation))
        )
        for fragment in manifestRun.fragments {
            #expect(await construction.driver.submit(.control(fragment)))
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

    @Test("Contributor ingress rejects anonymous authority without mutation")
    func rejectAnonymousDeliveryForContributor() async throws {
        let harness = try Fixture.makeHarness(localRole: .contributor)
        let construction = try makeDriver(
            harness: harness,
            roleCase: .contributor
        )
        let delivery = try makeAnonymousDelivery(
            harness: harness,
            payloadType: .anonymousComponent
        )
        await construction.driver.start()

        #expect(!(await construction.driver.submit(.anonymous(delivery))))
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
        let delivery = try makeAnonymousDelivery(
            harness: harness,
            payloadType: payloadType
        )
        await construction.driver.start()

        #expect(await construction.driver.submit(.anonymous(delivery)))
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
            !(await construction.driver.submit(
                .control(manifestRun.reservation)
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

    private func makeAnonymousDelivery(
        harness: Fixture.Harness,
        payloadType: Alpha.AnonymousPayloadType
    ) throws -> Alpha.AdmissionLedger.AnonymousDelivery {
        let signingKey = try OpalCrypto.Secp256k1.SigningKey(
            rawRepresentation: Data(
                [UInt8](repeating: 0, count: 31) + [0x0B]
            )
        )
        let communicationPublicKey = [UInt8](
            signingKey.publicKey.compressedRepresentation
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
        return .init(
            attemptIdentifier: harness.attemptIdentifier,
            generationIdentifier: harness.generationIdentifier,
            envelope: envelope,
            authenticatedOuterEventIdentity: Array(
                communicationPublicKey.dropFirst()
            ),
            authenticatedRecipientEventIdentity: recipientEventIdentity,
            authenticatedMessageIdentifier: try .init(
                bytes: [UInt8](repeating: 0xB1, count: 32)
            ),
            currentUnixSeconds: 1_800_000_000
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

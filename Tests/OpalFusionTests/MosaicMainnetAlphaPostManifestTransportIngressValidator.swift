// MosaicMainnetAlphaPostManifestTransportIngressValidator.swift

import Foundation
import OpalCrypto
import Testing
@testable import OpalFusion

@Suite("Mosaic mainnet-alpha post-manifest transport ingress")
struct MosaicMainnetAlphaPostManifestTransportIngressValidator {
    typealias Alpha = OpalFusion.Mosaic.OpalMainnetAlpha
    typealias Driver = Alpha.PostManifestRuntimeDriver
    typealias Fixture = MosaicMainnetAlphaAdmissionLedgerFixtures
    typealias Ingress = Alpha.PostManifestTransportIngress
    typealias Nostr = OpalFusion.Mosaic.NostrNamespace
    typealias Transport = Alpha.PostManifestNIP59Transport

    private struct RejectingPreviousOutputSource:
        OpalFusion.Host.MosaicPreviousOutputSource {
        func resolvePreviousOutputs(
            for _: [OpalFusion.Host.MosaicPreviousOutputRequest]
        ) async throws -> [OpalFusion.Host.MosaicPreviousOutput] {
            throw ProbeFailure.unexpectedInvocation
        }
    }

    @Test("Require a nonempty set of distinct recipient identities")
    func validateRecipientSet() throws {
        #expect(throws: Ingress.RecipientSet.ValidationError.empty) {
            _ = try Ingress.RecipientSet([])
        }

        let recipient = try signingKey(20)
        #expect(
            throws: Ingress.RecipientSet.ValidationError
                .duplicateRecipientIdentity
        ) {
            _ = try Ingress.RecipientSet([
                .init(channel: .control, signingKey: recipient),
                .init(channel: .anonymous, signingKey: recipient),
            ])
        }

        let positiveScalar = try OpalCrypto.Secp256k1.SigningKey(
            rawRepresentation: try Nostr.EventCodec.decodeHexadecimal(
                String(repeating: "00", count: 31) + "01",
                field: "positiveScalar"
            )
        )
        let negativeScalar = try OpalCrypto.Secp256k1.SigningKey(
            rawRepresentation: try Nostr.EventCodec.decodeHexadecimal(
                "fffffffffffffffffffffffffffffffebaaedce6af48a03bbfd25e8cd0364140",
                field: "negativeScalar"
            )
        )
        #expect(
            positiveScalar.verificationKey.rawRepresentation
                != negativeScalar.verificationKey.rawRepresentation
        )
        #expect(
            positiveScalar.bip340VerificationKey
                == negativeScalar.bip340VerificationKey
        )
        #expect(
            throws: Ingress.RecipientSet.ValidationError
                .duplicateRecipientIdentity
        ) {
            _ = try Ingress.RecipientSet([
                .init(channel: .control, signingKey: positiveScalar),
                .init(channel: .anonymous, signingKey: negativeScalar),
            ])
        }

        _ = try Ingress.RecipientSet([
            .init(channel: .control, signingKey: recipient),
            .init(channel: .anonymous, signingKey: try signingKey(21)),
        ])
    }

    @Test("Open one control gift wrap before routing it to the selected driver")
    func routeControl() async throws {
        let harness = try Fixture.makeHarness(localRole: .conductor)
        let run = try manifestRun(harness)
        let sender = try eventSigningKey(
            matching: run.reservation.envelope.senderEventIdentity
        )
        let recipient = try signingKey(21)
        let giftWrap = try Transport.makeControlGiftWrap(
            run.reservation.envelope,
            context: runtimeContext(harness),
            timestamps: try layerTimestamps(harness),
            senderEventSigningKey: sender,
            recipientPublicKey: recipient.bip340VerificationKey
        )
        let ingress = try Ingress(
            bootstrap: bootstrap(harness),
            roleDependencies: conductorDependencies,
            recipientSet: try .init([
                .init(channel: .control, signingKey: recipient),
            ]),
            dependencies: .init(currentUnixSeconds: {
                harness.manifest.core.deadlines.phaseStart + 1
            })
        )

        #expect(
            await ingress.submit(giftWrap) == .rejected(.notRunning)
        )
        #expect(await ingress.start())
        #expect(!(await ingress.start()))
        #expect(await ingress.submit(giftWrap) == .accepted)
        #expect(await ingress.inputSourceDidTerminate(.finished))
        #expect(
            await ingress.submit(giftWrap) == .rejected(.notRunning)
        )
        let terminalState = Driver.State.conductor(
            .terminal(.failed(.inputSourceTerminated(.finished)))
        )
        #expect(await ingress.waitForTermination() == terminalState)
        #expect(await ingress.waitForTermination() == terminalState)
        #expect(!(await ingress.start()))
    }

    @Test("Reject an unknown recipient before runtime mutation")
    func rejectWrongRecipientWithoutRuntimeMutation() async throws {
        let harness = try Fixture.makeHarness(localRole: .conductor)
        let run = try manifestRun(harness)
        let sender = try eventSigningKey(
            matching: run.reservation.envelope.senderEventIdentity
        )
        let recipient = try signingKey(22)
        let outsider = try signingKey(23)
        let giftWrap = try Transport.makeControlGiftWrap(
            run.reservation.envelope,
            context: runtimeContext(harness),
            timestamps: try layerTimestamps(harness),
            senderEventSigningKey: sender,
            recipientPublicKey: recipient.bip340VerificationKey
        )
        let outsiderGiftWrap = try Transport.makeControlGiftWrap(
            run.reservation.envelope,
            context: runtimeContext(harness),
            timestamps: try layerTimestamps(harness),
            senderEventSigningKey: sender,
            recipientPublicKey: outsider.bip340VerificationKey
        )
        let ingress = try Ingress(
            bootstrap: bootstrap(harness),
            roleDependencies: conductorDependencies,
            recipientSet: try .init([
                .init(channel: .control, signingKey: recipient),
            ]),
            dependencies: .init(currentUnixSeconds: {
                harness.manifest.core.deadlines.phaseStart + 1
            })
        )
        #expect(await ingress.start())

        #expect(
            await ingress.submit(outsiderGiftWrap)
                == .rejected(.unknownRecipient)
        )
        #expect(await ingress.state == .running)
        #expect(await ingress.submit(giftWrap) == .accepted)

        await ingress.stop()
        #expect(
            await ingress.submit(giftWrap) == .rejected(.notRunning)
        )
        #expect(
            await ingress.waitForTermination()
                == .conductor(
                    .terminal(.cancelled(during: .manifestAgreement))
                )
        )
    }

    @Test("Reject an invalid recipient tag before runtime mutation")
    func rejectInvalidRecipientTag() async throws {
        let harness = try Fixture.makeHarness(localRole: .conductor)
        let run = try manifestRun(harness)
        let sender = try eventSigningKey(
            matching: run.reservation.envelope.senderEventIdentity
        )
        let recipient = try signingKey(28)
        let validGiftWrap = try Transport.makeControlGiftWrap(
            run.reservation.envelope,
            context: runtimeContext(harness),
            timestamps: try layerTimestamps(harness),
            senderEventSigningKey: sender,
            recipientPublicKey: recipient.bip340VerificationKey
        )
        let invalidTemplate = try Nostr.EventTemplate(
            createdAt: validGiftWrap.template.createdAt,
            kind: validGiftWrap.template.kind,
            tags: [["p", String(repeating: "f", count: 64)]],
            content: validGiftWrap.template.content,
            limits: (try Transport.codingLimits).event
        )
        let invalidGiftWrap = try Nostr.EventSigner.sign(
            invalidTemplate,
            using: try signingKey(29),
            auxiliaryRandomness: try .init(
                rawRepresentation: Data(repeating: 0x29, count: 32)
            ),
            limits: (try Transport.codingLimits).event
        )
        let ingress = try Ingress(
            bootstrap: bootstrap(harness),
            roleDependencies: conductorDependencies,
            recipientSet: try .init([
                .init(channel: .control, signingKey: recipient),
            ]),
            dependencies: .init(currentUnixSeconds: {
                harness.manifest.core.deadlines.phaseStart + 1
            })
        )
        #expect(await ingress.start())

        #expect(
            await ingress.submit(invalidGiftWrap)
                == .rejected(.transport(.invalidGiftWrapTags))
        )
        #expect(await ingress.state == .running)
        #expect(await ingress.submit(validGiftWrap) == .accepted)

        await ingress.stop()
        _ = await ingress.waitForTermination()
    }

    @Test("Use only the channel sealed for a recipient identity")
    func rejectRecipientChannelSubstitution() async throws {
        let harness = try Fixture.makeHarness(localRole: .conductor)
        let run = try manifestRun(harness)
        let sender = try eventSigningKey(
            matching: run.reservation.envelope.senderEventIdentity
        )
        let recipient = try signingKey(33)
        let controlGiftWrap = try Transport.makeControlGiftWrap(
            run.reservation.envelope,
            context: runtimeContext(harness),
            timestamps: try layerTimestamps(harness),
            senderEventSigningKey: sender,
            recipientPublicKey: recipient.bip340VerificationKey
        )
        let ingress = try Ingress(
            bootstrap: bootstrap(harness),
            roleDependencies: conductorDependencies,
            recipientSet: try .init([
                .init(channel: .anonymous, signingKey: recipient),
            ]),
            dependencies: .init(currentUnixSeconds: {
                harness.manifest.core.deadlines.phaseStart + 1
            })
        )
        #expect(await ingress.start())

        #expect(
            await ingress.submit(controlGiftWrap)
                == .rejected(.transport(.invalidCanonicalEnvelope))
        )
        #expect(await ingress.state == .running)

        await ingress.stop()
        _ = await ingress.waitForTermination()
    }

    @Test(
        "Preserve cancellation requested while runtime startup is suspended",
        .timeLimit(.minutes(1))
    )
    func preserveStopDuringStartup() async throws {
        let harness = try Fixture.makeHarness(localRole: .conductor)
        let run = try manifestRun(harness)
        let sender = try eventSigningKey(
            matching: run.reservation.envelope.senderEventIdentity
        )
        let recipient = try signingKey(26)
        let giftWrap = try Transport.makeControlGiftWrap(
            run.reservation.envelope,
            context: runtimeContext(harness),
            timestamps: try layerTimestamps(harness),
            senderEventSigningKey: sender,
            recipientPublicKey: recipient.bip340VerificationKey
        )
        let suspension = MosaicRuntimeCoordinatorSuspensionProbe()
        await suspension.arm()
        let ingress = try Ingress(
            bootstrap: bootstrap(harness),
            roleDependencies: conductorDependencies,
            recipientSet: try .init([
                .init(channel: .control, signingKey: recipient),
            ]),
            dependencies: .init(
                currentUnixSeconds: {
                    harness.manifest.core.deadlines.phaseStart + 1
                },
                beforeDriverStart: {
                    await suspension.suspendIfArmed()
                }
            )
        )

        let startTask = Task { await ingress.start() }
        await suspension.waitUntilSuspended()
        #expect(await ingress.waitForTermination() == nil)
        await ingress.stop()
        #expect(
            await ingress.submit(giftWrap) == .rejected(.notRunning)
        )
        await suspension.resume()
        #expect(await startTask.value)
        #expect(
            await ingress.waitForTermination()
                == .conductor(
                    .terminal(.cancelled(during: .manifestAgreement))
                )
        )
    }

    @Test(
        "Preserve source closure requested while runtime startup is suspended",
        .timeLimit(.minutes(1))
    )
    func preserveSourceClosureDuringStartup() async throws {
        let harness = try Fixture.makeHarness(localRole: .conductor)
        let run = try manifestRun(harness)
        let sender = try eventSigningKey(
            matching: run.reservation.envelope.senderEventIdentity
        )
        let recipient = try signingKey(27)
        let giftWrap = try Transport.makeControlGiftWrap(
            run.reservation.envelope,
            context: runtimeContext(harness),
            timestamps: try layerTimestamps(harness),
            senderEventSigningKey: sender,
            recipientPublicKey: recipient.bip340VerificationKey
        )
        let suspension = MosaicRuntimeCoordinatorSuspensionProbe()
        await suspension.arm()
        let ingress = try Ingress(
            bootstrap: bootstrap(harness),
            roleDependencies: conductorDependencies,
            recipientSet: try .init([
                .init(channel: .control, signingKey: recipient),
            ]),
            dependencies: .init(
                currentUnixSeconds: {
                    harness.manifest.core.deadlines.phaseStart + 1
                },
                beforeDriverStart: {
                    await suspension.suspendIfArmed()
                }
            )
        )

        let startTask = Task { await ingress.start() }
        await suspension.waitUntilSuspended()
        #expect(await ingress.inputSourceDidTerminate(.failed))
        #expect(
            await ingress.submit(giftWrap) == .rejected(.notRunning)
        )
        await suspension.resume()
        #expect(await startTask.value)
        #expect(
            await ingress.waitForTermination()
                == .conductor(
                    .terminal(.failed(.inputSourceTerminated(.failed)))
                )
        )
    }

    @Test("Keep anonymous authority unavailable to contributor ingress")
    func rejectAnonymousForContributor() async throws {
        let harness = try Fixture.makeHarness(localRole: .contributor)
        let sender = try signingKey(24)
        let recipient = try signingKey(25)
        let envelope = try Alpha.AnonymousEnvelope(
            roundIdentifier: harness.manifest.core.roundIdentifier,
            phase: .anonymousComponentSubmission,
            senderCommunicationPublicKey: Array(
                sender.publicKey.compressedRepresentation
            ),
            recipientEventIdentity: Array(
                recipient.bip340VerificationKey.rawRepresentation
            ),
            sequence: 0,
            payloadType: .anonymousComponent,
            expiryUnixSeconds: harness.manifest.core.deadlines.bchSigning + 10,
            payload: [0x00]
        )
        let giftWrap = try Transport.makeAnonymousGiftWrap(
            envelope,
            context: runtimeContext(harness),
            timestamps: try layerTimestamps(harness),
            senderCommunicationSigningKey: sender,
            recipientPublicKey: recipient.bip340VerificationKey
        )
        let ingress = try Ingress(
            bootstrap: bootstrap(harness),
            roleDependencies: try contributorDependencies(),
            recipientSet: try .init([
                .init(channel: .anonymous, signingKey: recipient),
            ]),
            dependencies: .init(currentUnixSeconds: {
                harness.manifest.core.deadlines.phaseStart + 1
            })
        )
        #expect(await ingress.start())

        #expect(
            await ingress.submit(giftWrap) == .rejected(.runtimeRejected)
        )
        #expect(await ingress.state == .running)

        await ingress.stop()
        #expect(
            await ingress.waitForTermination()
                == .contributor(
                    .terminal(.cancelled(during: .manifestAgreement))
                )
        )
    }

    private var conductorDependencies: Driver.RoleDependencies {
        .conductor(
            .init(
                componentAuthorizationEvaluator: .unavailable,
                bchSignatureAuthorizationEvaluator: .unavailable,
                previousOutputSource: RejectingPreviousOutputSource(),
                maximumPendingInputCount: 8,
                handoffPublication: { _ in
                    throw ProbeFailure.unexpectedInvocation
                }
            )
        )
    }

    private func contributorDependencies() throws -> Driver.RoleDependencies {
        let expiresAt = Date(timeIntervalSince1970: 1_900_000_000)
        let host = MosaicRuntimeCoordinatorHostProbe(
            lease: try .init(
                reference: .init(
                    identifier: UUID(
                        uuid: (
                            0, 0, 0, 0, 0, 0, 0, 0,
                            0, 0, 0, 0, 0, 0, 0, 0xE1
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
        return .contributor(
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
                    publishPreSignAcknowledgement: { _ in
                        throw ProbeFailure.unexpectedInvocation
                    },
                    publishLocalBCHSignatures: { _ in
                        throw ProbeFailure.unexpectedInvocation
                    }
                ),
                expectedReservationExpiration: expiresAt,
                maximumPendingInputCount: 8,
                makeReservationRequest: { _ in
                    throw ProbeFailure.unexpectedInvocation
                }
            )
        )
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

    private func manifestRun(
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

    private func eventSigningKey(
        matching identity: [UInt8]
    ) throws -> OpalCrypto.Secp256k1.SigningKey {
        for scalar in [UInt8(9), UInt8(10)] {
            let candidate = try signingKey(scalar)
            if Array(candidate.bip340VerificationKey.rawRepresentation)
                == identity {
                return candidate
            }
        }
        throw ProbeFailure.unexpectedInvocation
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

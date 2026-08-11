// MosaicMainnetAlphaPostManifestAnonymousPublicationBridgeValidator.swift

import Foundation
import OpalCrypto
import Testing
@testable import OpalFusion

@Suite("Mosaic mainnet-alpha anonymous publication bridge", .serialized)
struct MosaicMainnetAlphaPostManifestAnonymousPublicationBridgeValidator {
    typealias Alpha = OpalFusion.Mosaic.OpalMainnetAlpha
    typealias Attempt = OpalFusion.Mosaic.Attempt
    typealias Bridge = Alpha.PostManifestAnonymousPublicationBridge
    typealias Coordinator = Alpha.ReservationCoordinator
    typealias ExecutionFixture = MosaicMainnetAlphaExecutionFixtures
    typealias Fixture = MosaicMainnetAlphaAdmissionLedgerFixtures
    typealias LocalAttempt = OpalFusion.Mosaic.LocalAttempt
    typealias Session = Alpha.RuntimeSession
    typealias Transport = Alpha.PostManifestNIP59Transport

    private static let currentUnixSeconds: UInt64 = 1_800_000_100
    private static let expiryUnixSeconds: UInt64 = 1_800_000_200

    private enum ProbeFailure: Error {
        case injected
        case invalidTimestampRequest
    }

    private struct AcceptTranscriptInclusion:
        LocalAttempt.TranscriptInclusionValidating
    {
        func validateCompleteInclusion(
            attemptIdentifier _: LocalAttempt.AttemptIdentifier,
            generationIdentifier _: LocalAttempt.GenerationIdentifier,
            contributor _: Attempt.ControlIdentity,
            materialIdentifier _: LocalAttempt.MaterialIdentifier,
            transcript _: OpalFusion.Mosaic.OpalV0
                .UnsignedTransactionTranscript
        ) throws {}
    }

    private struct SharedFixture: Sendable {
        let context: Bridge.Context
        let bootstrap: Alpha.PostManifestRuntimeDriver.Bootstrap
        let runtimeContext: Session.Context
        let material: Alpha.LocalContributionMaterial
        let foreignManifestMaterial: Alpha.LocalContributionMaterial
        let transcript: OpalFusion.Mosaic.OpalV0
            .UnsignedTransactionTranscript
        let rawComponentPublications: [
            Coordinator.LocalAnonymousComponentPublication
        ]
        let componentValidation: Bridge.ComponentValidation
        let alternateComponentValidation: Bridge.ComponentValidation
        let transcriptInclusion: LocalAttempt.TranscriptInclusionValidation
        let rawBCHSignaturePublications: [
            Alpha.LocalBCHSignaturePublication
        ]
        let mismatchedBCHSignaturePublications: [
            Alpha.LocalBCHSignaturePublication
        ]
        let bchSignatureValidation: Bridge.BCHSignatureValidation
        let alternateBCHSignatureValidation: Bridge.BCHSignatureValidation
        let recipientSigningKeys: [
            Data: OpalCrypto.Secp256k1.SigningKey
        ]
    }

    private actor BatchProbe {
        private let failureAtCount: Int?
        private let suspension: MosaicRuntimeCoordinatorSuspensionProbe?
        private var batches: [Bridge.GiftWrapBatch] = []

        init(
            failureAtCount: Int? = nil,
            suspension: MosaicRuntimeCoordinatorSuspensionProbe? = nil
        ) {
            self.failureAtCount = failureAtCount
            self.suspension = suspension
        }

        func handoff(_ batch: Bridge.GiftWrapBatch) async throws {
            batches.append(batch)
            await suspension?.suspendIfArmed()
            guard batches.count != failureAtCount else {
                throw Bridge.Failure.invalidPublication
            }
        }

        func values() -> [Bridge.GiftWrapBatch] {
            batches
        }
    }

    private static let sharedFixtureTask = Task {
        try await makeSharedFixture()
    }

    init() throws {
        try MosaicMainnetAlphaFixtures.requireAuthorizationEvaluators()
    }

    @Test(
        "Round-trip all components and local signatures on purpose-separated mailbox sequences",
        .timeLimit(.minutes(3))
    )
    func roundTripCompletePublicationOrder() async throws {
        let fixture = try await Self.sharedFixtureTask.value
        let probe = BatchProbe()
        let bridge = try makeBridge(fixture: fixture, probe: probe)

        try await bridge.publishComponents(
            fixture.componentValidation,
            expiryUnixSeconds: Self.expiryUnixSeconds
        )
        #expect(await bridge.state == .componentsPublished)

        let componentBatch = try #require(await probe.values().first)
        #expect(
            componentBatch.recipients.count
                == Alpha.componentCountPerContributor
        )
        let componentRecipients = Set(
            componentBatch.recipients.map(\.recipientEventIdentity)
        )
        #expect(componentRecipients.count == Alpha.componentCountPerContributor)
        for recipient in componentBatch.recipients {
            let recipientKey = try #require(
                fixture.recipientSigningKeys[
                    recipient.recipientEventIdentity
                ]
            )
            let delivery = try open(
                recipient,
                recipientKey: recipientKey,
                context: fixture.context
            )
            let expected = try #require(
                fixture.componentValidation.entries.first {
                    Data($0.recipientEventIdentity)
                        == recipient.recipientEventIdentity
                }
            )
            let binding = try #require(
                fixture.componentValidation.materialBinding.slots.first {
                    $0.recipientEventIdentity
                        == recipient.recipientEventIdentity
                }
            )
            #expect(delivery.envelope.phase == .anonymousComponentSubmission)
            #expect(delivery.envelope.sequence == 0)
            #expect(delivery.envelope.payloadType == .anonymousComponent)
            #expect(
                delivery.authenticatedOuterEventIdentity
                    == Array(
                        expected.senderPrivateKey.makeSigningKey()
                            .bip340VerificationKey.rawRepresentation
                    )
            )
            #expect(
                Data(delivery.authenticatedOuterEventIdentity)
                    == binding.componentEnvelopeIdentity
            )
            #expect(
                binding.componentEnvelopeIdentity
                    != binding.groupedCommunicationIdentity
            )
            #expect(
                binding.componentEnvelopeIdentity
                    != binding.bchSignatureEnvelopeIdentity
            )
            #expect(
                try Alpha.CanonicalWireCodec.decodeAnonymousComponent(
                    from: delivery.envelope.payload
                ) == expected.payload
            )
        }

        try await bridge.publishBCHSignatures(
            fixture.bchSignatureValidation,
            expiryUnixSeconds: Self.expiryUnixSeconds
        )
        #expect(await bridge.state == .completed)

        let batches = await probe.values()
        #expect(batches.count == 2)
        let signatureBatch = try #require(batches.last)
        #expect(
            signatureBatch.recipients.count
                == fixture.bchSignatureValidation.entries.count
        )
        for recipient in signatureBatch.recipients {
            #expect(componentRecipients.contains(recipient.recipientEventIdentity))
            let recipientKey = try #require(
                fixture.recipientSigningKeys[
                    recipient.recipientEventIdentity
                ]
            )
            let delivery = try open(
                recipient,
                recipientKey: recipientKey,
                context: fixture.context
            )
            let expected = try #require(
                fixture.bchSignatureValidation.entries.first {
                    Data($0.recipientEventIdentity)
                        == recipient.recipientEventIdentity
                }
            )
            let binding = try #require(
                fixture.bchSignatureValidation.materialBinding.slots.first {
                    $0.recipientEventIdentity
                        == recipient.recipientEventIdentity
                }
            )
            #expect(delivery.envelope.phase == .bchSigning)
            #expect(delivery.envelope.sequence == 1)
            #expect(delivery.envelope.payloadType == .bchSignatureSubmission)
            #expect(
                Data(delivery.authenticatedOuterEventIdentity)
                    == binding.bchSignatureEnvelopeIdentity
            )
            #expect(
                binding.bchSignatureEnvelopeIdentity
                    != binding.componentEnvelopeIdentity
            )
            #expect(
                binding.bchSignatureEnvelopeIdentity
                    != binding.groupedCommunicationIdentity
            )
            #expect(
                try Alpha.CanonicalWireCodec.decodeBCHSignatureSubmission(
                    from: delivery.envelope.payload
                ) == expected.submission
            )
        }

        await #expect(throws: Bridge.Failure.inputAfterTermination) {
            try await bridge.publishBCHSignatures(
                fixture.bchSignatureValidation,
                expiryUnixSeconds: Self.expiryUnixSeconds
            )
        }
        let postCompletionGate = MosaicRuntimeCoordinatorSuspensionProbe()
        await postCompletionGate.arm()
        let cancelledPostCompletionInput = Task {
            await postCompletionGate.suspendIfArmed()
            try await bridge.publishComponents(
                fixture.componentValidation,
                expiryUnixSeconds: Self.expiryUnixSeconds
            )
        }
        await postCompletionGate.waitUntilSuspended()
        cancelledPostCompletionInput.cancel()
        await postCompletionGate.resume()
        await #expect(throws: Bridge.Failure.inputAfterTermination) {
            try await cancelledPostCompletionInput.value
        }
        #expect(await bridge.state == .completed)
        #expect(await probe.values().count == 2)
    }

    @Test("Reject phase skipping, duplicate batches, and foreign attempt context")
    func rejectInvalidOrderingAndContext() async throws {
        let fixture = try await Self.sharedFixtureTask.value

        let skippedProbe = BatchProbe()
        let skipped = try makeBridge(fixture: fixture, probe: skippedProbe)
        await #expect(throws: Bridge.Failure.invalidOrder) {
            try await skipped.publishBCHSignatures(
                fixture.bchSignatureValidation,
                expiryUnixSeconds: Self.expiryUnixSeconds
            )
        }
        #expect(await skipped.state == .terminal(.invalidOrder))
        await #expect(throws: Bridge.Failure.inputAfterTermination) {
            try await skipped.publishComponents(
                fixture.componentValidation,
                expiryUnixSeconds: Self.expiryUnixSeconds
            )
        }
        #expect(await skippedProbe.values().isEmpty)

        let duplicateProbe = BatchProbe()
        let duplicate = try makeBridge(fixture: fixture, probe: duplicateProbe)
        try await duplicate.publishComponents(
            fixture.componentValidation,
            expiryUnixSeconds: Self.expiryUnixSeconds
        )
        await #expect(throws: Bridge.Failure.invalidOrder) {
            try await duplicate.publishComponents(
                fixture.componentValidation,
                expiryUnixSeconds: Self.expiryUnixSeconds
            )
        }
        #expect(await duplicate.state == .terminal(.invalidOrder))
        #expect(await duplicateProbe.values().count == 1)

        let foreignContext = try makeContext(
            fixture: fixture,
            attemptIdentifier: .init(
                validatedBytes: [UInt8](repeating: 0xB1, count: 32)
            )
        )
        let foreignProbe = BatchProbe()
        #expect(throws: Bridge.InitializationError.localMaterialMismatch) {
            _ = try Bridge(
                context: foreignContext,
                material: fixture.material,
                dependencies: dependencies(
                    context: foreignContext,
                    probe: foreignProbe
                )
            )
        }
        #expect(await foreignProbe.values().isEmpty)

        #expect(throws: Bridge.Context.ValidationError.localMaterialMismatch) {
            _ = try Bridge.Context(
                validating: fixture.foreignManifestMaterial,
                against: fixture.runtimeContext
            )
        }

        let conductorContext = try makeConductorContext(fixture: fixture)
        #expect(throws: Bridge.InitializationError.localPeerIsNotContributor) {
            _ = try Bridge(
                context: conductorContext,
                material: fixture.material,
                dependencies: dependencies(
                    context: conductorContext,
                    probe: foreignProbe
                )
            )
        }

        let componentSubstitutionProbe = BatchProbe()
        let componentSubstitution = try makeBridge(
            fixture: fixture,
            probe: componentSubstitutionProbe
        )
        await #expect(throws: Bridge.Failure.invalidPublication) {
            try await componentSubstitution.publishComponents(
                fixture.alternateComponentValidation,
                expiryUnixSeconds: Self.expiryUnixSeconds
            )
        }
        #expect(
            await componentSubstitution.state
                == .terminal(.invalidPublication)
        )
        #expect(await componentSubstitutionProbe.values().isEmpty)
        await #expect(throws: Bridge.Failure.inputAfterTermination) {
            try await componentSubstitution.publishComponents(
                fixture.componentValidation,
                expiryUnixSeconds: Self.expiryUnixSeconds
            )
        }

        let substitutedProbe = BatchProbe()
        let substituted = try makeBridge(
            fixture: fixture,
            probe: substitutedProbe
        )
        try await substituted.publishComponents(
            fixture.componentValidation,
            expiryUnixSeconds: Self.expiryUnixSeconds
        )
        await #expect(throws: Bridge.Failure.invalidPublication) {
            try await substituted.publishBCHSignatures(
                fixture.alternateBCHSignatureValidation,
                expiryUnixSeconds: Self.expiryUnixSeconds
            )
        }
        #expect(await substituted.state == .terminal(.invalidPublication))
        #expect(await substitutedProbe.values().count == 1)
    }

    @Test("Seal exact component slots, recipients, payloads, and runtime material")
    func rejectInvalidComponentValidations() async throws {
        let fixture = try await Self.sharedFixtureTask.value
        let publications = fixture.rawComponentPublications

        #expect(
            throws: Coordinator.AnonymousPublicationValidationError
                .invalidComponentCount(actual: publications.count - 1)
        ) {
            _ = try Bridge.ComponentValidation(
                validating: Array(publications.dropLast()),
                material: fixture.material,
                runtimeContext: fixture.runtimeContext
            )
        }

        var duplicateSlot = publications
        duplicateSlot[duplicateSlot.count - 1] = publications[0]
        #expect(
            throws: Coordinator.AnonymousPublicationValidationError
                .duplicateComponentSlot(publications[0].slot)
        ) {
            _ = try Bridge.ComponentValidation(
                validating: duplicateSlot,
                material: fixture.material,
                runtimeContext: fixture.runtimeContext
            )
        }

        let last = try #require(publications.last)
        var substitutedRecipient = publications
        substitutedRecipient[substitutedRecipient.count - 1] = .init(
            slot: last.slot,
            recipientEventIdentity: publications[0].recipientEventIdentity,
            payload: last.payload
        )
        #expect(
            throws: Coordinator.AnonymousPublicationValidationError
                .componentMismatch(slot: last.slot)
        ) {
            _ = try Bridge.ComponentValidation(
                validating: substitutedRecipient,
                material: fixture.material,
                runtimeContext: fixture.runtimeContext
            )
        }

        var substitutedPayload = publications
        substitutedPayload[substitutedPayload.count - 1] = .init(
            slot: last.slot,
            recipientEventIdentity: last.recipientEventIdentity,
            payload: publications[0].payload
        )
        #expect(
            throws: Coordinator.AnonymousPublicationValidationError
                .componentMismatch(slot: last.slot)
        ) {
            _ = try Bridge.ComponentValidation(
                validating: substitutedPayload,
                material: fixture.material,
                runtimeContext: fixture.runtimeContext
            )
        }

        let foreignRuntimeContext = Session.Context(
            attemptIdentifier: .init(
                validatedBytes: [UInt8](repeating: 0xB2, count: 32)
            ),
            generationIdentifier: fixture.runtimeContext.generationIdentifier,
            materialIdentifier: fixture.runtimeContext.materialIdentifier,
            localControlIdentity:
                fixture.runtimeContext.localControlIdentity,
            localRole: fixture.runtimeContext.localRole,
            roster: fixture.runtimeContext.roster,
            proposalRoundIdentifier:
                fixture.runtimeContext.proposalRoundIdentifier
        )
        #expect(
            throws: Coordinator.AnonymousPublicationValidationError
                .contextMismatch
        ) {
            _ = try Bridge.ComponentValidation(
                validating: publications,
                material: fixture.material,
                runtimeContext: foreignRuntimeContext
            )
        }

        let foreignInclusion = try LocalAttempt.TranscriptInclusionValidation(
            attemptIdentifier: .init(
                validatedBytes: [UInt8](repeating: 0xB3, count: 32)
            ),
            generationIdentifier: fixture.runtimeContext.generationIdentifier,
            contributor: fixture.material.contributor,
            materialIdentifier: fixture.material.materialIdentifier,
            transcript: fixture.transcript,
            using: AcceptTranscriptInclusion()
        )
        #expect(
            throws: Coordinator.AnonymousPublicationValidationError
                .transcriptMismatch
        ) {
            _ = try Bridge.BCHSignatureValidation(
                validating: fixture.rawBCHSignaturePublications,
                transcriptInclusion: foreignInclusion,
                material: fixture.material,
                runtimeContext: fixture.runtimeContext
            )
        }

        #expect(
            throws: Coordinator.AnonymousPublicationValidationError
                .invalidBCHSignatureCount(actual: 0)
        ) {
            _ = try Bridge.BCHSignatureValidation(
                validating: [],
                transcriptInclusion: fixture.transcriptInclusion,
                material: fixture.material,
                runtimeContext: fixture.runtimeContext
            )
        }

        let signature = try #require(
            fixture.rawBCHSignaturePublications.first
        )
        #expect(
            throws: Coordinator.AnonymousPublicationValidationError
                .duplicateBCHSignatureSlot(signature.slot)
        ) {
            _ = try Bridge.BCHSignatureValidation(
                validating: [signature, signature],
                transcriptInclusion: fixture.transcriptInclusion,
                material: fixture.material,
                runtimeContext: fixture.runtimeContext
            )
        }

        #expect(
            throws: Coordinator.AnonymousPublicationValidationError
                .bchSignatureMismatch(slot: signature.slot)
        ) {
            _ = try Bridge.BCHSignatureValidation(
                validating: fixture.mismatchedBCHSignaturePublications,
                transcriptInclusion: fixture.transcriptInclusion,
                material: fixture.material,
                runtimeContext: fixture.runtimeContext
            )
        }
    }

    @Test("Terminalize construction and handoff failures without retry")
    func terminalizeDependencyFailures() async throws {
        let fixture = try await Self.sharedFixtureTask.value
        let constructionProbe = BatchProbe()
        let construction = try Bridge(
            context: fixture.context,
            material: fixture.material,
            dependencies: .init(
                makeLayerTimestamps: { _ in
                    throw ProbeFailure.injected
                },
                handoffGiftWrapBatch: { batch in
                    try await constructionProbe.handoff(batch)
                }
            )
        )
        await #expect(throws: Bridge.Failure.giftWrapConstructionFailed) {
            try await construction.publishComponents(
                fixture.componentValidation,
                expiryUnixSeconds: Self.expiryUnixSeconds
            )
        }
        #expect(
            await construction.state
                == .terminal(.giftWrapConstructionFailed)
        )
        #expect(await constructionProbe.values().isEmpty)

        let cancellationProbe = BatchProbe()
        let cancelledConstruction = try Bridge(
            context: fixture.context,
            material: fixture.material,
            dependencies: .init(
                makeLayerTimestamps: { _ in
                    withUnsafeCurrentTask { task in
                        task?.cancel()
                    }
                    throw ProbeFailure.injected
                },
                handoffGiftWrapBatch: { batch in
                    try await cancellationProbe.handoff(batch)
                }
            )
        )
        await #expect(throws: Bridge.Failure.cancelled) {
            try await Task {
                try await cancelledConstruction.publishComponents(
                    fixture.componentValidation,
                    expiryUnixSeconds: Self.expiryUnixSeconds
                )
            }.value
        }
        #expect(
            await cancelledConstruction.state == .terminal(.cancelled)
        )
        #expect(await cancellationProbe.values().isEmpty)

        let handoffProbe = BatchProbe(failureAtCount: 1)
        let handoff = try makeBridge(
            fixture: fixture,
            probe: handoffProbe
        )
        await #expect(throws: Bridge.Failure.handoffFailed) {
            try await handoff.publishComponents(
                fixture.componentValidation,
                expiryUnixSeconds: Self.expiryUnixSeconds
            )
        }
        #expect(await handoff.state == .terminal(.handoffFailed))
        #expect(await handoffProbe.values().count == 1)
        await #expect(throws: Bridge.Failure.inputAfterTermination) {
            try await handoff.publishComponents(
                fixture.componentValidation,
                expiryUnixSeconds: Self.expiryUnixSeconds
            )
        }
        #expect(await handoffProbe.values().count == 1)
    }

    @Test(
        "Cancellation and concurrent publication terminalize one in-flight batch",
        .timeLimit(.minutes(2))
    )
    func terminalizeCancellationAndConcurrency() async throws {
        let fixture = try await Self.sharedFixtureTask.value

        let cancellationSuspension = MosaicRuntimeCoordinatorSuspensionProbe()
        await cancellationSuspension.arm()
        let cancellationProbe = BatchProbe(
            suspension: cancellationSuspension
        )
        let cancelled = try makeBridge(
            fixture: fixture,
            probe: cancellationProbe
        )
        let cancelledTask = Task {
            try await cancelled.publishComponents(
                fixture.componentValidation,
                expiryUnixSeconds: Self.expiryUnixSeconds
            )
        }
        await cancellationSuspension.waitUntilSuspended()
        cancelledTask.cancel()
        await cancellationSuspension.resume()
        await #expect(throws: Bridge.Failure.cancelled) {
            try await cancelledTask.value
        }
        #expect(await cancelled.state == .terminal(.cancelled))
        #expect(await cancellationProbe.values().count == 1)

        let concurrentSuspension = MosaicRuntimeCoordinatorSuspensionProbe()
        await concurrentSuspension.arm()
        let concurrentProbe = BatchProbe(suspension: concurrentSuspension)
        let concurrent = try makeBridge(
            fixture: fixture,
            probe: concurrentProbe
        )
        let firstTask = Task {
            try await concurrent.publishComponents(
                fixture.componentValidation,
                expiryUnixSeconds: Self.expiryUnixSeconds
            )
        }
        await concurrentSuspension.waitUntilSuspended()
        await #expect(throws: Bridge.Failure.concurrentPublication) {
            try await concurrent.publishComponents(
                fixture.componentValidation,
                expiryUnixSeconds: Self.expiryUnixSeconds
            )
        }
        await concurrentSuspension.resume()
        await #expect(throws: Bridge.Failure.concurrentPublication) {
            try await firstTask.value
        }
        #expect(
            await concurrent.state
                == .terminal(.concurrentPublication)
        )
        #expect(await concurrentProbe.values().count == 1)
    }

    private static func makeSharedFixture() async throws -> SharedFixture {
        let prepared = try await ExecutionFixture.prepare()
        let material = prepared.localMaterial
        let componentTokens = prepared.localAuthorizationValidation
            .componentAuthorizationTokens
        let rawComponents = try material.slots.map { slot in
            Coordinator.LocalAnonymousComponentPublication(
                slot: slot.slot,
                recipientEventIdentity: slot.recipientEventIdentity,
                payload: try .init(
                    roundIdentifier: material.manifest.core.roundIdentifier,
                    authorizationToken: componentTokens[slot.slot],
                    component: slot.component
                )
            )
        }
        let componentValidation = try Bridge.ComponentValidation(
            validating: rawComponents,
            material: material,
            runtimeContext: prepared.session.context
        )
        let transcript = prepared.materialized.prepared.transcript
        let inclusion = try LocalAttempt.TranscriptInclusionValidation(
            attemptIdentifier: material.attemptIdentifier,
            generationIdentifier: material.generationIdentifier,
            contributor: material.contributor,
            materialIdentifier: material.materialIdentifier,
            transcript: transcript,
            using: material
        )
        let signaturePublications = try Alpha.LocalBCHSignatureBuilder.build(
            finalizedTransaction: prepared.localFinalizedTransaction,
            signingRequest: prepared.signingRequest,
            transcript: transcript,
            material: material,
            authorizationValidation: prepared.localAuthorizationValidation
        )
        let signatureValidation = try Bridge.BCHSignatureValidation(
            validating: signaturePublications,
            transcriptInclusion: inclusion,
            material: material,
            runtimeContext: prepared.session.context
        )
        let alternateBCHMaterial = try alternateMaterial(
            from: material,
            contributorIndex: try contributorIndex(for: material),
            replacesBCHEnvelopeKeys: true,
            replacesRecipientIdentities: false
        )
        let alternateComponentValidation = try Bridge.ComponentValidation(
            validating: rawComponents,
            material: alternateBCHMaterial,
            runtimeContext: prepared.session.context
        )
        let alternateBCHInclusion = try LocalAttempt
            .TranscriptInclusionValidation(
                attemptIdentifier: alternateBCHMaterial.attemptIdentifier,
                generationIdentifier:
                    alternateBCHMaterial.generationIdentifier,
                contributor: alternateBCHMaterial.contributor,
                materialIdentifier: alternateBCHMaterial.materialIdentifier,
                transcript: transcript,
                using: alternateBCHMaterial
            )
        let alternateBCHPublications = try Alpha.LocalBCHSignatureBuilder.build(
            finalizedTransaction: prepared.localFinalizedTransaction,
            signingRequest: prepared.signingRequest,
            transcript: transcript,
            material: alternateBCHMaterial,
            authorizationValidation: prepared.localAuthorizationValidation
        )
        let alternateBCHValidation = try Bridge.BCHSignatureValidation(
            validating: alternateBCHPublications,
            transcriptInclusion: alternateBCHInclusion,
            material: alternateBCHMaterial,
            runtimeContext: prepared.session.context
        )
        let alternateRecipientMaterial = try alternateMaterial(
            from: material,
            contributorIndex: try contributorIndex(for: material),
            replacesBCHEnvelopeKeys: false,
            replacesRecipientIdentities: true
        )
        let foreignManifest = try MosaicMainnetAlphaFixtures.makeManifest(
            election: prepared.admission.election,
            verificationKey: material.manifest.core
                .componentAuthorizationVerificationKey,
            bchSignatureVerificationKey: material.manifest.core
                .bchSignatureAuthorizationVerificationKey,
            relaySetDigest: [UInt8](repeating: 0x99, count: 32)
        )
        let foreignManifestMaterial = try alternateMaterial(
            from: material,
            contributorIndex: try contributorIndex(for: material),
            replacesBCHEnvelopeKeys: false,
            replacesRecipientIdentities: false,
            manifest: foreignManifest
        )
        let mismatchedBCHPublications = try Alpha.LocalBCHSignatureBuilder.build(
            finalizedTransaction: prepared.localFinalizedTransaction,
            signingRequest: prepared.signingRequest,
            transcript: transcript,
            material: alternateRecipientMaterial,
            authorizationValidation: prepared.localAuthorizationValidation
        )
        let bootstrap = Alpha.PostManifestRuntimeDriver.Bootstrap(
            validatedAttempt: Fixture.makeValidatedAttempt(
                election: prepared.admission.election
            ),
            attemptIdentifier: prepared.admission.attemptIdentifier,
            generationIdentifier: prepared.admission.generationIdentifier,
            materialIdentifier: prepared.admission.materialIdentifier,
            localControlIdentity: prepared.admission.localControlIdentity,
            proposalValidation: prepared.admission.proposalValidation
        )
        let context = try Bridge.Context(
            validating: prepared.admission.manifest,
            against: bootstrap
        )
        let contributorIndex = try #require(
            material.manifest.core.orderedContributors.firstIndex(
                of: material.contributor
            )
        )
        let recipientSigningKeys = try Dictionary(
            uniqueKeysWithValues: material.slots.map { slot in
                let ordinal = contributorIndex
                    * Alpha.componentCountPerContributor + slot.slot + 1
                let key = try OpalCrypto.Secp256k1.SigningKey(
                    rawRepresentation: scalarBytes(2_000 + ordinal)
                )
                return (key.bip340VerificationKey.rawRepresentation, key)
            }
        )
        return .init(
            context: context,
            bootstrap: bootstrap,
            runtimeContext: prepared.session.context,
            material: material,
            foreignManifestMaterial: foreignManifestMaterial,
            transcript: transcript,
            rawComponentPublications: rawComponents,
            componentValidation: componentValidation,
            alternateComponentValidation: alternateComponentValidation,
            transcriptInclusion: inclusion,
            rawBCHSignaturePublications: signaturePublications,
            mismatchedBCHSignaturePublications:
                mismatchedBCHPublications,
            bchSignatureValidation: signatureValidation,
            alternateBCHSignatureValidation: alternateBCHValidation,
            recipientSigningKeys: recipientSigningKeys
        )
    }

    private func makeContext(
        fixture: SharedFixture,
        attemptIdentifier: LocalAttempt.AttemptIdentifier
    ) throws -> Bridge.Context {
        let bootstrap = Alpha.PostManifestRuntimeDriver.Bootstrap(
            validatedAttempt: fixture.bootstrap.validatedAttempt,
            attemptIdentifier: attemptIdentifier,
            generationIdentifier: fixture.context.generationIdentifier,
            materialIdentifier: fixture.context.materialIdentifier,
            localControlIdentity: fixture.context.localControlIdentity,
            proposalValidation: fixture.bootstrap.proposalValidation
        )
        return try .init(
            validating: fixture.context.manifest,
            against: bootstrap
        )
    }

    private func makeConductorContext(
        fixture: SharedFixture
    ) throws -> Bridge.Context {
        let bootstrap = Alpha.PostManifestRuntimeDriver.Bootstrap(
            validatedAttempt: fixture.bootstrap.validatedAttempt,
            attemptIdentifier: fixture.context.attemptIdentifier,
            generationIdentifier: fixture.context.generationIdentifier,
            materialIdentifier: fixture.context.materialIdentifier,
            localControlIdentity: fixture.context.roster.conductor,
            proposalValidation: fixture.bootstrap.proposalValidation
        )
        return try .init(
            validating: fixture.context.manifest,
            against: bootstrap
        )
    }

    private func makeBridge(
        fixture: SharedFixture,
        probe: BatchProbe
    ) throws -> Bridge {
        try .init(
            context: fixture.context,
            material: fixture.material,
            dependencies: dependencies(
                context: fixture.context,
                probe: probe
            )
        )
    }

    private func dependencies(
        context: Bridge.Context,
        probe: BatchProbe
    ) -> Bridge.Dependencies {
        .init(
            makeLayerTimestamps: { request in
                guard request.expiryUnixSeconds
                        == Self.expiryUnixSeconds,
                      request.sequence == 0 || request.sequence == 1 else {
                    throw ProbeFailure.invalidTimestampRequest
                }
                return try .init(
                    phaseStartUnixSeconds: context.phaseStartUnixSeconds,
                    currentUnixSeconds: Self.currentUnixSeconds,
                    sealCreatedAt: Self.currentUnixSeconds - 2,
                    giftWrapCreatedAt: Self.currentUnixSeconds - 1
                )
            },
            handoffGiftWrapBatch: { batch in
                try await probe.handoff(batch)
            }
        )
    }

    private func open(
        _ recipient: Bridge.RecipientGiftWrap,
        recipientKey: OpalCrypto.Secp256k1.SigningKey,
        context: Bridge.Context
    ) throws -> Alpha.AdmissionLedger.AnonymousDelivery {
        let delivery = try Transport.openAnonymous(
            recipient.giftWrap.event,
            context: .init(
                attemptIdentifier: context.attemptIdentifier,
                generationIdentifier: context.generationIdentifier,
                phaseStartUnixSeconds: context.phaseStartUnixSeconds
            ),
            recipientSigningKey: recipientKey,
            currentUnixSeconds: Self.currentUnixSeconds
        )
        guard case let .anonymous(anonymous) = delivery.storage else {
            throw ProbeFailure.injected
        }
        #expect(
            anonymous.authenticatedRecipientEventIdentity
                == Array(recipient.recipientEventIdentity)
        )
        #expect(
            anonymous.envelope.roundIdentifier == context.roundIdentifier
        )
        return anonymous
    }

    private static func scalarBytes(_ scalar: Int) -> Data {
        precondition(scalar > 0)
        var value = UInt32(scalar).bigEndian
        var result = Data(repeating: 0, count: 28)
        withUnsafeBytes(of: &value) { result.append(contentsOf: $0) }
        return result
    }

    private static func contributorIndex(
        for material: Alpha.LocalContributionMaterial
    ) throws -> Int {
        guard let index = material.manifest.core.orderedContributors
            .firstIndex(of: material.contributor) else {
            throw ProbeFailure.injected
        }
        return index
    }

    private static func alternateMaterial(
        from material: Alpha.LocalContributionMaterial,
        contributorIndex: Int,
        replacesBCHEnvelopeKeys: Bool,
        replacesRecipientIdentities: Bool,
        manifest: Alpha.RoundManifest? = nil
    ) throws -> Alpha.LocalContributionMaterial {
        let secrets = try material.slots.map { slot in
            let ordinal = contributorIndex
                * Alpha.componentCountPerContributor + slot.slot + 1
            let bchEnvelopeKey = replacesBCHEnvelopeKeys
                ? try OpalCrypto.Secp256k1.PrivateKey(
                    rawRepresentation: scalarBytes(5_000 + ordinal)
                )
                : slot.bchSignatureEnvelopePrivateKey
            let recipientEventIdentity: [UInt8]
            if replacesRecipientIdentities {
                recipientEventIdentity = [UInt8](
                    try OpalCrypto.Secp256k1.SigningKey(
                        rawRepresentation: scalarBytes(6_000 + ordinal)
                    ).bip340VerificationKey.rawRepresentation
                )
            } else {
                recipientEventIdentity = slot.recipientEventIdentity
            }
            return try Alpha.ComponentSlotSecrets(
                salt: slot.salt,
                pedersenNonce: slot.pedersenNonce,
                communicationPrivateKey: slot.communicationPrivateKey,
                componentEnvelopePrivateKey:
                    slot.componentEnvelopePrivateKey,
                bchSignatureEnvelopePrivateKey: bchEnvelopeKey,
                componentAuthorizationNonce:
                    slot.componentAuthorizationRequest.input.nonce,
                bchSignatureAuthorizationNonce:
                    slot.bchSignatureAuthorizationRequest.input.nonce,
                recipientEventIdentity: recipientEventIdentity
            )
        }
        return try Alpha.LocalContributionMaterial.build(
            attemptIdentifier: material.attemptIdentifier,
            generationIdentifier: material.generationIdentifier,
            materialIdentifier: material.materialIdentifier,
            contributor: material.contributor,
            manifest: manifest ?? material.manifest,
            reservationLease: material.reservationLease,
            slotSecrets: secrets
        )
    }
}

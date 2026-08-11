// MosaicMainnetAlphaControlPublicationBridgeValidator.swift

import Foundation
import OpalCrypto
import Testing
@testable import OpalFusion

@Suite("Mosaic mainnet-alpha control publication bridge")
struct MosaicMainnetAlphaControlPublicationBridgeValidator {
    typealias Alpha = OpalFusion.Mosaic.OpalMainnetAlpha
    typealias Attempt = OpalFusion.Mosaic.Attempt
    typealias Bridge = Alpha.PostManifestControlPublicationBridge
    typealias Fixture = MosaicMainnetAlphaAdmissionLedgerFixtures
    typealias LocalAttempt = OpalFusion.Mosaic.LocalAttempt
    typealias RuntimeSession = Alpha.RuntimeSession
    typealias Transport = Alpha.PostManifestNIP59Transport

    private static let currentUnixSeconds: UInt64 = 1_800_000_100
    private static let expiryUnixSeconds: UInt64 = 1_800_000_200

    private enum ProbeFailure: Error {
        case injected
        case invalidTimestamps
    }

    private enum ReservationSubstitution: CaseIterable {
        case attemptIdentifier
        case generationIdentifier
        case materialIdentifier
        case manifest
    }

    private struct AcceptReservationPublication:
        RuntimeSession.ReservationPublicationValidating
    {
        func validateReservationPublication(
            _: RuntimeSession.ReservationPublicationRequest
        ) throws {}
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
            let count = batches.count
            if count == 1 {
                await suspension?.suspendIfArmed()
            }
            guard count != failureAtCount else {
                throw ProbeFailure.injected
            }
        }

        func values() -> [Bridge.GiftWrapBatch] {
            batches
        }
    }

    private final class TimestampProbe: @unchecked Sendable {
        private let phaseStartUnixSeconds: UInt64
        private let suspendsFirstRequest: Bool
        private let lock = NSLock()
        private let requestedStream: AsyncStream<Void>
        private let requestedContinuation: AsyncStream<Void>.Continuation
        private let resumeSemaphore = DispatchSemaphore(value: 0)
        private var requests: [Bridge.TimestampRequest] = []
        private var didSuspend = false

        init(
            phaseStartUnixSeconds: UInt64,
            suspendsFirstRequest: Bool = false
        ) {
            self.phaseStartUnixSeconds = phaseStartUnixSeconds
            self.suspendsFirstRequest = suspendsFirstRequest
            (requestedStream, requestedContinuation) = AsyncStream<Void>
                .makeStream(bufferingPolicy: .bufferingNewest(1))
        }

        func makeTimestamps(
            for request: Bridge.TimestampRequest
        ) throws -> Transport.LayerTimestamps {
            lock.lock()
            requests.append(request)
            let shouldSuspend = suspendsFirstRequest && !didSuspend
            didSuspend = didSuspend || shouldSuspend
            lock.unlock()
            requestedContinuation.yield()
            if shouldSuspend {
                resumeSemaphore.wait()
            }
            return try .init(
                phaseStartUnixSeconds: phaseStartUnixSeconds,
                currentUnixSeconds: Self.currentUnixSeconds,
                sealCreatedAt: Self.currentUnixSeconds - 2,
                giftWrapCreatedAt: Self.currentUnixSeconds - 1
            )
        }

        func waitUntilRequested() async {
            guard !hasRequests() else { return }
            for await _ in requestedStream {
                return
            }
        }

        func resume() {
            resumeSemaphore.signal()
        }

        func values() -> [Bridge.TimestampRequest] {
            lock.lock()
            let values = requests
            lock.unlock()
            return values
        }

        private func hasRequests() -> Bool {
            lock.lock()
            let hasRequests = !requests.isEmpty
            lock.unlock()
            return hasRequests
        }

        private static let currentUnixSeconds: UInt64 = 1_800_000_100
    }

    private struct Harness {
        let ledgerHarness: Fixture.Harness
        let bootstrap: Alpha.PostManifestRuntimeDriver.Bootstrap
        let context: Bridge.Context
        let controlSigningKey: OpalCrypto.Secp256k1.SigningKey
        let eventSigningKey: OpalCrypto.Secp256k1.SigningKey
        let recipients: [Bridge.Recipient]
        let recipientSigningKeys: [
            Attempt.ControlIdentity: OpalCrypto.Secp256k1.SigningKey
        ]
    }

    @Test("Require exact sender authority and complete distinct roster recipients")
    func validateConstruction() async throws {
        let harness = try makeHarness(localRole: .conductor)
        let probe = BatchProbe()

        let bridge = try makeBridge(harness: harness, probe: probe)
        #expect(
            await bridge.state
                == .ready(nextSequence: 0, lastPublishedPhase: nil)
        )

        let foreignControlKey = try signingKey(10)
        let foreignIdentity = controlIdentity(for: foreignControlKey)
        let foreignBootstrap = Alpha.PostManifestRuntimeDriver.Bootstrap(
            validatedAttempt: harness.bootstrap.validatedAttempt,
            attemptIdentifier: harness.bootstrap.attemptIdentifier,
            generationIdentifier: harness.bootstrap.generationIdentifier,
            materialIdentifier: harness.bootstrap.materialIdentifier,
            localControlIdentity: foreignIdentity,
            proposalValidation: harness.bootstrap.proposalValidation
        )
        #expect(
            throws: Bridge.Context.ValidationError.runtimeBootstrapMismatch
        ) {
            _ = try Bridge.Context(
                validating: harness.context.manifest,
                against: foreignBootstrap
            )
        }

        #expect(throws: Bridge.InitializationError.controlSigningKeyMismatch) {
            _ = try makeBridge(
                harness: harness,
                probe: probe,
                controlSigningKey: foreignControlKey
            )
        }
        #expect(
            throws: Bridge.InitializationError.reusedControlAndEventIdentity
        ) {
            _ = try makeBridge(
                harness: harness,
                probe: probe,
                eventSigningKey: harness.controlSigningKey
            )
        }
        #expect(
            throws: Bridge.InitializationError.invalidRecipientCount(
                actual: harness.recipients.count - 1
            )
        ) {
            _ = try makeBridge(
                harness: harness,
                probe: probe,
                recipients: Array(harness.recipients.dropLast())
            )
        }

        var duplicateRecipient = harness.recipients
        duplicateRecipient[duplicateRecipient.count - 1] = .init(
            controlIdentity: duplicateRecipient[0].controlIdentity,
            eventVerificationKey: duplicateRecipient.last!.eventVerificationKey
        )
        #expect(
            throws: Bridge.InitializationError.duplicateRecipient(
                duplicateRecipient[0].controlIdentity
            )
        ) {
            _ = try makeBridge(
                harness: harness,
                probe: probe,
                recipients: duplicateRecipient
            )
        }

        var mismatchedRecipients = harness.recipients
        mismatchedRecipients[mismatchedRecipients.count - 1] = .init(
            controlIdentity: foreignIdentity,
            eventVerificationKey: mismatchedRecipients.last!.eventVerificationKey
        )
        #expect(throws: Bridge.InitializationError.recipientSetMismatch) {
            _ = try makeBridge(
                harness: harness,
                probe: probe,
                recipients: mismatchedRecipients
            )
        }

        var duplicateEventIdentity = harness.recipients
        duplicateEventIdentity[duplicateEventIdentity.count - 1] = .init(
            controlIdentity: duplicateEventIdentity.last!.controlIdentity,
            eventVerificationKey: duplicateEventIdentity[0].eventVerificationKey
        )
        #expect(
            throws: Bridge.InitializationError.duplicateRecipientEventIdentity
        ) {
            _ = try makeBridge(
                harness: harness,
                probe: probe,
                recipients: duplicateEventIdentity
            )
        }

        var reusedControlIdentity = harness.recipients
        reusedControlIdentity[reusedControlIdentity.count - 1] = .init(
            controlIdentity: reusedControlIdentity.last!.controlIdentity,
            eventVerificationKey:
                harness.controlSigningKey.bip340VerificationKey
        )
        #expect(
            throws: Bridge.InitializationError
                .recipientEventIdentityReusesRosterControlIdentity
        ) {
            _ = try makeBridge(
                harness: harness,
                probe: probe,
                recipients: reusedControlIdentity
            )
        }

        var reusedSenderEventIdentity = harness.recipients
        reusedSenderEventIdentity[reusedSenderEventIdentity.count - 1] = .init(
            controlIdentity: reusedSenderEventIdentity.last!.controlIdentity,
            eventVerificationKey: harness.eventSigningKey.bip340VerificationKey
        )
        #expect(
            throws: Bridge.InitializationError
                .recipientEventIdentityReusesSenderEventIdentity
        ) {
            _ = try makeBridge(
                harness: harness,
                probe: probe,
                recipients: reusedSenderEventIdentity
            )
        }

        let substitutedManifest = try MosaicMainnetAlphaFixtures.makeManifest(
            election: harness.ledgerHarness.election,
            verificationKey: MosaicMainnetAlphaFixtures.rsaVerificationKey(),
            relaySetDigest: [UInt8](repeating: 0x45, count: 32)
        )
        #expect(
            throws: Bridge.Context.ValidationError.manifestProposalMismatch
        ) {
            _ = try Bridge.Context(
                validating: substitutedManifest,
                against: harness.bootstrap
            )
        }
        #expect(await probe.values().isEmpty)
    }

    @Test(
        "Accept complete recipient allocation for every roster capacity",
        arguments: [7, 8, 9]
    )
    func acceptEveryRosterCapacity(candidateCount: Int) async throws {
        let harness = try makeHarness(
            localRole: .conductor,
            candidateCount: candidateCount
        )
        let bridge = try makeBridge(
            harness: harness,
            probe: BatchProbe()
        )
        #expect(harness.recipients.count == candidateCount)
        #expect(
            await bridge.state
                == .ready(nextSequence: 0, lastPublishedPhase: nil)
        )
    }

    @Test(
        "Publish sequence-zero manifest and every fragment to every roster peer",
        .timeLimit(.minutes(1))
    )
    func publishManifestToCompleteRoster() async throws {
        let harness = try makeHarness(localRole: .conductor)
        let probe = BatchProbe()
        let timestampProbe = TimestampProbe(
            phaseStartUnixSeconds: harness.context.phaseStartUnixSeconds
        )
        let bridge = try makeBridge(
            harness: harness,
            probe: probe,
            timestampProbe: timestampProbe
        )

        try await bridge.publishManifest(
            expiryUnixSeconds: Self.expiryUnixSeconds
        )

        let batches = await probe.values()
        let reservation = try Alpha.AggregateReservation(
            aggregateKind: .completeManifest,
            aggregateDigest: Alpha.RoleSeedValidator.hash(
                domainSuffix: Alpha.AggregateKind.completeManifest
                    .digestDomainSuffix,
                fields: [harness.context.manifest.canonicalBytes]
            ),
            declaredCanonicalByteCount:
                harness.context.manifest.canonicalBytes.count
        )
        #expect(batches.count == reservation.fragmentCount + 1)
        #expect(batches.map(\.envelope.sequence) == Array(0 ..< UInt64(batches.count)))
        #expect(batches.first?.envelope.payloadType == .aggregateReservation)
        #expect(
            timestampProbe.values() == batches.map {
                .init(
                    phase: $0.envelope.phase,
                    sequence: $0.envelope.sequence,
                    expiryUnixSeconds: $0.envelope.expiryUnixSeconds
                )
            }
        )
        #expect(
            batches.dropFirst().allSatisfy {
                $0.envelope.payloadType == .aggregateFragment
            }
        )

        let rosterIdentities = harness.context.roster.controlIdentities
        for batch in batches {
            #expect(batch.envelope.phase == .manifestAgreement)
            #expect(
                batch.envelope.expiryUnixSeconds == Self.expiryUnixSeconds
            )
            #expect(
                batch.envelope.senderControlIdentity
                    == harness.context.localControlIdentity
            )
            #expect(
                batch.recipients.map(\.controlIdentity) == rosterIdentities
            )
            #expect(
                Set(
                    batch.recipients.map {
                        $0.giftWrap.event.identifier.rawRepresentation
                    }
                ).count == rosterIdentities.count
            )
            for recipient in batch.recipients {
                let opened = try open(
                    recipient,
                    harness: harness
                )
                #expect(opened.envelope == batch.envelope)
            }
        }

        let decodedReservation = try Alpha.CanonicalWireCodec
            .decodeAggregateReservation(
                from: try #require(batches.first).envelope.payload
            )
        let reassembledBytes = try batches.dropFirst().flatMap { batch in
            try Alpha.CanonicalWireCodec.decodeAggregateFragment(
                from: batch.envelope.payload,
                reservation: decodedReservation
            ).body
        }
        #expect(reassembledBytes == harness.context.manifest.canonicalBytes)
        #expect(
            await bridge.state == .ready(
                nextSequence: UInt64(batches.count),
                lastPublishedPhase: .manifestAgreement
            )
        )
    }

    @Test(
        "Continue a contributor stream with a separately signed transcript acknowledgement",
        .timeLimit(.minutes(2))
    )
    func publishContributorCommitAndAcknowledgement() async throws {
        let harness = try makeHarness(localRole: .contributor)
        let probe = BatchProbe()
        let bridge = try makeBridge(harness: harness, probe: probe)
        let playerCommit = try localPlayerCommit(for: harness)
        let reservationValidation = try reservationPublicationValidation(
            playerCommit: playerCommit,
            harness: harness
        )

        try await bridge.publishPlayerCommit(
            reservationValidation,
            expiryUnixSeconds: Self.expiryUnixSeconds
        )
        let afterCommit = await probe.values()
        let acknowledgementSequence = UInt64(afterCommit.count)
        let transcript = try MosaicUnsignedTransactionTranscriptFixtures
            .prepare(
                roster: harness.context.roster,
                manifest: harness.context.manifest.binding,
                profile: .opalMainnetAlpha
            ).transcript
        let inclusionValidation = try transcriptInclusionValidation(
            transcript: transcript,
            harness: harness
        )

        try await bridge.publishPreSignAcknowledgement(
            inclusionValidation,
            expiryUnixSeconds: Self.expiryUnixSeconds
        )

        let batches = await probe.values()
        let acknowledgementBatch = try #require(batches.last)
        let envelope = acknowledgementBatch.envelope
        #expect(envelope.sequence == acknowledgementSequence)
        #expect(envelope.phase == .transcriptAgreement)
        #expect(envelope.payloadType == .preSignAcknowledgement)
        #expect(acknowledgementBatch.recipients.count == 7)
        let submission = try Alpha.CanonicalWireCodec
            .decodePreSignAcknowledgementSubmission(
                from: envelope.payload,
                contributor: harness.context.localControlIdentity
            )
        #expect(submission.validation.transcriptRoot == transcript.transcriptRoot)
        #expect(
            submission.acknowledgement.rawRepresentation
                != envelope.controlSignature
        )
        #expect(
            await bridge.state == .ready(
                nextSequence: acknowledgementSequence + 1,
                lastPublishedPhase: .transcriptAgreement
            )
        )

        await #expect(
            throws: Bridge.Failure.phaseRollback(
                previous: .transcriptAgreement,
                next: .walletReservation
            )
        ) {
            try await bridge.publishPlayerCommit(
                reservationValidation,
                expiryUnixSeconds: Self.expiryUnixSeconds
            )
        }
        await #expect(throws: Bridge.Failure.inputAfterTermination) {
            try await bridge.publishPreSignAcknowledgement(
                inclusionValidation,
                expiryUnixSeconds: Self.expiryUnixSeconds
            )
        }
    }

    @Test("Reject a transcript acknowledgement before the contributor PlayerCommit")
    func rejectInvalidFirstPublication() async throws {
        let contributor = try makeHarness(localRole: .contributor)
        let contributorBridge = try makeBridge(
            harness: contributor,
            probe: BatchProbe()
        )
        let transcript = try MosaicUnsignedTransactionTranscriptFixtures
            .prepare(
                roster: contributor.context.roster,
                manifest: contributor.context.manifest.binding,
                profile: .opalMainnetAlpha
            ).transcript
        let validation = try transcriptInclusionValidation(
            transcript: transcript,
            harness: contributor
        )
        await #expect(throws: Bridge.Failure.invalidFirstPublication) {
            try await contributorBridge.publishPreSignAcknowledgement(
                validation,
                expiryUnixSeconds: Self.expiryUnixSeconds
            )
        }
    }

    @Test(
        "Reject reservation publication bound to foreign attempt material",
        arguments: ReservationSubstitution.allCases
    )
    private func rejectForeignReservationPublication(
        _ substitution: ReservationSubstitution
    ) async throws {
        let harness = try makeHarness(localRole: .contributor)
        let probe = BatchProbe()
        let bridge = try makeBridge(harness: harness, probe: probe)
        let playerCommit = try localPlayerCommit(for: harness)
        let substitutedManifest = try MosaicMainnetAlphaFixtures.makeManifest(
            election: harness.ledgerHarness.election,
            verificationKey: MosaicMainnetAlphaFixtures.rsaVerificationKey(),
            relaySetDigest: [UInt8](repeating: 0x45, count: 32)
        )
        let validation = try reservationPublicationValidation(
            playerCommit: playerCommit,
            harness: harness,
            attemptIdentifier: substitution == .attemptIdentifier
                ? .init(validatedBytes: [UInt8](repeating: 0xB1, count: 32))
                : nil,
            generationIdentifier: substitution == .generationIdentifier
                ? .init(opaqueBytes: [UInt8](repeating: 0xB2, count: 32))
                : nil,
            materialIdentifier: substitution == .materialIdentifier
                ? .init(opaqueBytes: [UInt8](repeating: 0xB3, count: 32))
                : nil,
            manifest: substitution == .manifest ? substitutedManifest : nil
        )

        await #expect(throws: Bridge.Failure.invalidPublication) {
            try await bridge.publishPlayerCommit(
                validation,
                expiryUnixSeconds: Self.expiryUnixSeconds
            )
        }
        #expect(await probe.values().isEmpty)
        #expect(await bridge.state == .terminal(.invalidPublication))
    }

    @Test("Reject a transcript validation for another manifest")
    func rejectForeignTranscript() async throws {
        let harness = try makeHarness(localRole: .contributor)
        let probe = BatchProbe()
        let bridge = try makeBridge(harness: harness, probe: probe)
        let playerCommit = try localPlayerCommit(for: harness)
        try await bridge.publishPlayerCommit(
            try reservationPublicationValidation(
                playerCommit: playerCommit,
                harness: harness
            ),
            expiryUnixSeconds: Self.expiryUnixSeconds
        )
        let acceptedBatchCount = await probe.values().count
        let foreignManifest = try MosaicMainnetAlphaFixtures.makeManifest(
            election: harness.ledgerHarness.election,
            verificationKey: MosaicMainnetAlphaFixtures.rsaVerificationKey(),
            relaySetDigest: [UInt8](repeating: 0x45, count: 32)
        )
        let foreignTranscript = try MosaicUnsignedTransactionTranscriptFixtures
            .prepare(
                roster: harness.context.roster,
                manifest: foreignManifest.binding,
                profile: .opalMainnetAlpha
            ).transcript

        await #expect(throws: Bridge.Failure.invalidPublication) {
            try await bridge.publishPreSignAcknowledgement(
                try transcriptInclusionValidation(
                    transcript: foreignTranscript,
                    harness: harness
                ),
                expiryUnixSeconds: Self.expiryUnixSeconds
            )
        }
        #expect(await probe.values().count == acceptedBatchCount)
        #expect(await bridge.state == .terminal(.invalidPublication))
    }

    @Test(
        "Terminalize after recipient-batch handoff failure without reusing its range",
        .timeLimit(.minutes(1))
    )
    func terminalizeHandoffFailure() async throws {
        let harness = try makeHarness(localRole: .conductor)
        let probe = BatchProbe(failureAtCount: 2)
        let bridge = try makeBridge(harness: harness, probe: probe)

        await #expect(throws: Bridge.Failure.handoffFailed) {
            try await bridge.publishManifest(
                expiryUnixSeconds: Self.expiryUnixSeconds
            )
        }
        #expect(await probe.values().count == 2)
        #expect(await bridge.state == .terminal(.handoffFailed))
        await #expect(throws: Bridge.Failure.inputAfterTermination) {
            try await bridge.publishManifest(
                expiryUnixSeconds: Self.expiryUnixSeconds
            )
        }
        #expect(await probe.values().count == 2)
    }

    @Test(
        "Concurrent publication terminalizes the shared sender sequence",
        .timeLimit(.minutes(1))
    )
    func rejectConcurrentPublication() async throws {
        let harness = try makeHarness(localRole: .conductor)
        let suspension = MosaicRuntimeCoordinatorSuspensionProbe()
        await suspension.arm()
        let probe = BatchProbe(suspension: suspension)
        let bridge = try makeBridge(harness: harness, probe: probe)
        await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try await bridge.publishManifest(
                    expiryUnixSeconds: Self.expiryUnixSeconds
                )
            }
            await suspension.waitUntilSuspended()

            await #expect(throws: Bridge.Failure.concurrentPublication) {
                try await bridge.publishManifest(
                    expiryUnixSeconds: Self.expiryUnixSeconds
                )
            }
            await suspension.resume()
            await #expect(throws: Bridge.Failure.concurrentPublication) {
                try await group.next()
            }
            group.cancelAll()
        }
        #expect(await bridge.state == .terminal(.concurrentPublication))
        #expect(await probe.values().count == 1)
    }

    @Test(
        "Cancellation after handoff claim terminalizes without advancing",
        .timeLimit(.minutes(1))
    )
    func terminalizeCancellation() async throws {
        let harness = try makeHarness(localRole: .conductor)
        let suspension = MosaicRuntimeCoordinatorSuspensionProbe()
        await suspension.arm()
        let probe = BatchProbe(suspension: suspension)
        let bridge = try makeBridge(harness: harness, probe: probe)

        await #expect(throws: Bridge.Failure.cancelled) {
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    try await bridge.publishManifest(
                        expiryUnixSeconds: Self.expiryUnixSeconds
                    )
                }
                await suspension.waitUntilSuspended()
                group.cancelAll()
                await suspension.resume()
                try await group.next()
            }
        }
        #expect(await bridge.state == .terminal(.cancelled))
        #expect(await probe.values().count == 1)
    }

    @Test(
        "Cancellation during wrapper construction suppresses external handoff",
        .timeLimit(.minutes(1))
    )
    func suppressHandoffAfterConstructionCancellation() async throws {
        let harness = try makeHarness(localRole: .conductor)
        let timestampProbe = TimestampProbe(
            phaseStartUnixSeconds: harness.context.phaseStartUnixSeconds,
            suspendsFirstRequest: true
        )
        let probe = BatchProbe()
        let bridge = try makeBridge(
            harness: harness,
            probe: probe,
            timestampProbe: timestampProbe
        )

        await #expect(throws: Bridge.Failure.cancelled) {
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    try await bridge.publishManifest(
                        expiryUnixSeconds: Self.expiryUnixSeconds
                    )
                }
                await timestampProbe.waitUntilRequested()
                group.cancelAll()
                timestampProbe.resume()
                try await group.next()
            }
        }
        #expect(await probe.values().isEmpty)
        #expect(await bridge.state == .terminal(.cancelled))
    }

    @Test("Fail closed when caller-owned cover timestamps are unavailable")
    func rejectUnavailableTimestamps() async throws {
        let harness = try makeHarness(localRole: .conductor)
        let probe = BatchProbe()
        let bridge = try makeBridge(
            harness: harness,
            probe: probe,
            timestampFailure: true
        )

        await #expect(throws: Bridge.Failure.giftWrapConstructionFailed) {
            try await bridge.publishManifest(
                expiryUnixSeconds: Self.expiryUnixSeconds
            )
        }
        #expect(await probe.values().isEmpty)
        #expect(
            await bridge.state == .terminal(.giftWrapConstructionFailed)
        )
    }

    @Test("Fail closed when control signing randomness is unavailable")
    func rejectUnavailableSigningRandomness() async throws {
        let harness = try makeHarness(localRole: .conductor)
        let probe = BatchProbe()
        let bridge = try makeBridge(
            harness: harness,
            probe: probe,
            signatureFailure: true
        )

        await #expect(throws: Bridge.Failure.signatureConstructionFailed) {
            try await bridge.publishManifest(
                expiryUnixSeconds: Self.expiryUnixSeconds
            )
        }
        #expect(await probe.values().isEmpty)
        #expect(
            await bridge.state == .terminal(.signatureConstructionFailed)
        )
    }

    private func makeHarness(
        localRole: OpalFusion.Mosaic.Role,
        candidateCount: Int = 7
    ) throws -> Harness {
        let ledgerHarness = try Fixture.makeHarness(
            candidateCount: candidateCount,
            localRole: localRole
        )
        let localScalar = try #require(
            MosaicMainnetAlphaFixtures.scalarByte(
                for: ledgerHarness.localControlIdentity
            )
        )
        let controlSigningKey = try signingKey(localScalar)
        let eventSigningKey = try signingKey(20)
        let bootstrap = Alpha.PostManifestRuntimeDriver.Bootstrap(
            validatedAttempt: Fixture.makeValidatedAttempt(
                election: ledgerHarness.election
            ),
            attemptIdentifier: ledgerHarness.attemptIdentifier,
            generationIdentifier: ledgerHarness.generationIdentifier,
            materialIdentifier: ledgerHarness.materialIdentifier,
            localControlIdentity: ledgerHarness.localControlIdentity,
            proposalValidation: ledgerHarness.proposalValidation
        )
        var recipientSigningKeys: [
            Attempt.ControlIdentity: OpalCrypto.Secp256k1.SigningKey
        ] = [:]
        let recipients = try ledgerHarness.election.result.roster
            .controlIdentities.enumerated().map { index, identity in
                let signingKey = try signingKey(UInt8(30 + index))
                recipientSigningKeys[identity] = signingKey
                return Bridge.Recipient(
                    controlIdentity: identity,
                    eventVerificationKey: signingKey.bip340VerificationKey
                )
            }
        return .init(
            ledgerHarness: ledgerHarness,
            bootstrap: bootstrap,
            context: try .init(
                validating: ledgerHarness.manifest,
                against: bootstrap
            ),
            controlSigningKey: controlSigningKey,
            eventSigningKey: eventSigningKey,
            recipients: recipients,
            recipientSigningKeys: recipientSigningKeys
        )
    }

    private func makeBridge(
        harness: Harness,
        probe: BatchProbe,
        controlSigningKey: OpalCrypto.Secp256k1.SigningKey? = nil,
        eventSigningKey: OpalCrypto.Secp256k1.SigningKey? = nil,
        recipients: [Bridge.Recipient]? = nil,
        timestampProbe: TimestampProbe? = nil,
        timestampFailure: Bool = false,
        signatureFailure: Bool = false
    ) throws -> Bridge {
        let phaseStart = harness.context.phaseStartUnixSeconds
        return try Bridge(
            context: harness.context,
            controlSigningKey:
                controlSigningKey ?? harness.controlSigningKey,
            eventSigningKey: eventSigningKey ?? harness.eventSigningKey,
            recipients: recipients ?? harness.recipients,
            dependencies: .init(
                makeLayerTimestamps: { request in
                    guard !timestampFailure else {
                        throw ProbeFailure.invalidTimestamps
                    }
                    if let timestampProbe {
                        return try timestampProbe.makeTimestamps(for: request)
                    }
                    return try .init(
                        phaseStartUnixSeconds: phaseStart,
                        currentUnixSeconds: Self.currentUnixSeconds,
                        sealCreatedAt: Self.currentUnixSeconds - 2,
                        giftWrapCreatedAt: Self.currentUnixSeconds - 1
                    )
                },
                makeSignatureAuxiliaryRandomness: {
                    guard !signatureFailure else {
                        throw ProbeFailure.injected
                    }
                    return try OpalCrypto.Signature.BIP340
                        .AuxiliaryRandomness(
                            rawRepresentation: Data(
                                repeating: 0xA5,
                                count: 32
                            )
                        )
                },
                handoffGiftWrapBatch: { batch in
                    try await probe.handoff(batch)
                }
            )
        )
    }

    private func localPlayerCommit(
        for harness: Harness
    ) throws -> Alpha.PlayerCommit {
        let prepared = try MosaicUnsignedTransactionTranscriptFixtures.prepare(
            roster: harness.context.roster,
            manifest: harness.context.manifest.binding,
            profile: .opalMainnetAlpha
        )
        return try #require(
            Fixture.makePlayerCommits(
                harness: harness.ledgerHarness,
                commitmentSet: prepared.commitmentSet
            ).first {
                $0.contributor == harness.context.localControlIdentity
            }
        )
    }

    private func reservationPublicationValidation(
        playerCommit: Alpha.PlayerCommit,
        harness: Harness,
        attemptIdentifier: LocalAttempt.AttemptIdentifier? = nil,
        generationIdentifier: LocalAttempt.GenerationIdentifier? = nil,
        materialIdentifier: LocalAttempt.MaterialIdentifier? = nil,
        manifest: Alpha.RoundManifest? = nil
    ) throws -> RuntimeSession.ReservationPublicationValidation {
        let lease = try OpalFusion.Host.MosaicReservationLease(
            reference: .init(
                identifier: UUID(
                    uuid: (
                        0, 0, 0, 0, 0, 0, 0, 0,
                        0, 0, 0, 0, 0, 0, 0, 65
                    )
                ),
                generation: 1
            ),
            expiresAt: Date(timeIntervalSince1970: 1_900_000_000),
            participantReservation: .init(
                inputs: [
                    .init(
                        outpointTransactionHashBytes:
                            [UInt8](repeating: 0x51, count: 32),
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
        )
        return try .init(
            validating: .init(
                attemptIdentifier:
                    attemptIdentifier ?? harness.context.attemptIdentifier,
                generationIdentifier:
                    generationIdentifier ?? harness.context.generationIdentifier,
                materialIdentifier:
                    materialIdentifier ?? harness.context.materialIdentifier,
                contributor: harness.context.localControlIdentity,
                manifest: manifest ?? harness.context.manifest,
                reservationLease: lease,
                playerCommit: playerCommit
            ),
            using: AcceptReservationPublication()
        )
    }

    private func transcriptInclusionValidation(
        transcript: OpalFusion.Mosaic.OpalV0
            .UnsignedTransactionTranscript,
        harness: Harness
    ) throws -> LocalAttempt.TranscriptInclusionValidation {
        try .init(
            attemptIdentifier: harness.context.attemptIdentifier,
            generationIdentifier: harness.context.generationIdentifier,
            contributor: harness.context.localControlIdentity,
            materialIdentifier: harness.context.materialIdentifier,
            transcript: transcript,
            using: AcceptTranscriptInclusion()
        )
    }

    private func open(
        _ recipient: Bridge.RecipientGiftWrap,
        harness: Harness
    ) throws -> Fixture.Ledger.ControlDelivery {
        let signingKey = try #require(
            harness.recipientSigningKeys[recipient.controlIdentity]
        )
        let opened = try Transport.openControl(
            recipient.giftWrap.event,
            context: .init(
                attemptIdentifier: harness.context.attemptIdentifier,
                generationIdentifier: harness.context.generationIdentifier,
                phaseStartUnixSeconds: harness.context.phaseStartUnixSeconds
            ),
            recipientSigningKey: signingKey,
            currentUnixSeconds: Self.currentUnixSeconds
        )
        guard case let .control(delivery) = opened.storage else {
            throw ProbeFailure.injected
        }
        return delivery
    }

    private func signingKey(
        _ scalarByte: UInt8
    ) throws -> OpalCrypto.Secp256k1.SigningKey {
        try .init(
            rawRepresentation: Data(repeating: 0, count: 31)
                + Data([scalarByte])
        )
    }

    private func controlIdentity(
        for signingKey: OpalCrypto.Secp256k1.SigningKey
    ) -> Attempt.ControlIdentity {
        .init(
            validatedBytes: Array(
                signingKey.bip340VerificationKey.rawRepresentation
            )
        )
    }
}

// OpalFusion+Mosaic+OpalMainnetAlpha+ReservationCoordinator.swift

import Foundation

extension OpalFusion.Mosaic.OpalMainnetAlpha {
    /// Coordinates one contributor's mainnet-alpha reservation boundary.
    ///
    /// Control and anonymous transport remain injected. The coordinator owns ordered local authority:
    /// attempt-fresh material, sealed publication, transcript inclusion, BCH signing, and exact
    /// commit ordering. Durable recovery and broadcast remain external.
    actor ReservationCoordinator {
        private enum QueuedInput: Sendable {
            case runtime(RuntimeSession.Input)
            case authenticatedControl(
                AdmissionLedger.ControlDelivery,
                PostManifestTransportIngress.RecoveredAdmission
            )
            case authenticatedAbort(
                OpalFusion.Mosaic.Attempt.Phase,
                OpalFusion.Mosaic.Attempt.AbortReason
            )
            case inputSourceTerminated(InputSourceTermination)
            case runtimeRecoveryBarrier(UUID)
        }

        private enum PendingDisposition: Sendable {
            case failure(Failure)
            case recovery(Recovery, fallbackFailure: Failure?)

            var failure: Failure? {
                switch self {
                case let .failure(failure):
                    return failure
                case let .recovery(_, fallbackFailure):
                    return fallbackFailure
                }
            }

            var recovery: Recovery? {
                guard case let .recovery(recovery, _) = self else {
                    return nil
                }
                return recovery
            }
        }

        private let context: RuntimeSession.Context
        private let dependencies: Dependencies
        private let inputStream: AsyncStream<QueuedInput>
        private let inputContinuation: AsyncStream<QueuedInput>.Continuation
        private let effectStream: AsyncStream<RuntimeSession.Effect>
        private let effectContinuation: AsyncStream<RuntimeSession.Effect>.Continuation
        private let dispositionGate: MosaicRuntimeCoordinatorDispositionGate
        private let admissionJournal: PostManifestAdmissionJournal?

        private var runtimeSession: RuntimeSession
        private var inputConsumerTask: Task<Void, Never>?
        private var effectConsumerTask: Task<Void, Never>?
        private var pendingEffectCount = 0
        private var effectDrainWaiters: [CheckedContinuation<Void, Never>] = []
        private var recoveryBarrierWaiters: [
            UUID: CheckedContinuation<Bool, Never>
        ] = [:]
        private var admittedManifest: RoundManifest?
        private var localContributionMaterial: LocalContributionMaterial?
        private var authorizationResponseValidation:
            AuthorizationResponseSetMaterialValidation?
        private var pendingAnonymousComponentPublications:
            [LocalAnonymousComponentPublication]?
        private var transcriptInclusionValidation: OpalFusion.Mosaic.LocalAttempt
            .TranscriptInclusionValidation?
        private var admittedAcknowledgements: [OpalFusion.Mosaic.Attempt
            .TranscriptAcknowledgementValidation]?
        private var previousOutputValidation: PreviousOutputResolver.Validation?
        private var completeTransactionValidation: CompleteTransactionValidation?
        private var queuedInputSourceTermination: InputSourceTermination?
        private var pendingDisposition: PendingDisposition?

        private(set) var state: State = .idle
        private(set) var reservationLifecycle: ReservationLifecycle = .unreserved

        var runtimeSessionState: RuntimeSession.State {
            runtimeSession.state
        }

        var runtimeSessionTerminalProtocolAbort: (
            phase: OpalFusion.Mosaic.Attempt.Phase,
            reason: OpalFusion.Mosaic.Attempt.AbortReason
        )? {
            runtimeSession.terminalProtocolAbort
        }

        init(
            runtimeSession: RuntimeSession,
            dependencies: Dependencies,
            admissionJournal: PostManifestAdmissionJournal? = nil
        ) throws(InitializationError) {
            guard dependencies.maximumPendingInputCount > 0 else {
                throw .invalidInputBufferLimit
            }
            let context = runtimeSession.context
            guard runtimeSession.state == .active(.manifestAgreement) else {
                throw .runtimeSessionNotFresh
            }
            guard context.localRole == .contributor else {
                throw .localPeerIsNotContributor
            }
            let (inputStream, inputContinuation) = AsyncStream<
                QueuedInput
            >.makeStream(
                bufferingPolicy: .bufferingOldest(
                    dependencies.maximumPendingInputCount
                )
            )
            let (effectStream, effectContinuation) = AsyncStream<
                RuntimeSession.Effect
            >.makeStream()
            self.context = context
            self.dependencies = dependencies
            self.runtimeSession = runtimeSession
            self.inputStream = inputStream
            self.inputContinuation = inputContinuation
            self.effectStream = effectStream
            self.effectContinuation = effectContinuation
            self.admissionJournal = admissionJournal
            dispositionGate = MosaicRuntimeCoordinatorDispositionGate()
        }

        /// Starts the ordered local-effect consumer once.
        func start() {
            guard state == .idle else {
                return
            }
            state = .running
            inputConsumerTask = Task { [weak self] in
                await self?.consumeInputs()
            }
            effectConsumerTask = Task { [weak self] in
                await self?.consumeEffects()
            }
        }

        /// Queues one already-authenticated control delivery.
        @discardableResult
        func submitControl(_ delivery: AdmissionLedger.ControlDelivery) -> Bool {
            enqueue(.runtime(.control(delivery)))
        }

        /// Queues one transport-authenticated delivery behind the write-ahead journal boundary.
        @discardableResult
        func submitAuthenticatedControl(
            _ delivery: AdmissionLedger.ControlDelivery,
            source: PostManifestTransportIngress.RecoveredAdmission
        ) -> Bool {
            enqueue(.authenticatedControl(delivery, source))
        }

        /// Queues one already signature/context-validated public abort.
        @discardableResult
        func submitAuthenticatedAbort(
            during phase: OpalFusion.Mosaic.Attempt.Phase,
            reason: OpalFusion.Mosaic.Attempt.AbortReason
        ) -> Bool {
            guard runtimeSession.state.phase == phase else { return false }
            return enqueue(.authenticatedAbort(phase, reason))
        }

        /// Waits behind every queued recovered delivery and its ordered local effects.
        func awaitRuntimeRecoveryReplay() async -> Bool {
            guard state == .running else { return false }
            return await withCheckedContinuation { continuation in
                let identifier = UUID()
                recoveryBarrierWaiters[identifier] = continuation
                guard enqueue(.runtimeRecoveryBarrier(identifier)) else {
                    completeRecoveryBarrier(identifier, result: false)
                    return
                }
            }
        }

        /// Rejects an in-place retry through the paired runtime.
        @discardableResult
        func requestRetry() -> Bool {
            enqueue(.runtime(.retryRequested))
        }

        /// Queues authenticated-source closure behind every previously accepted runtime input.
        @discardableResult
        func inputSourceDidTerminate(
            _ termination: InputSourceTermination
        ) -> Bool {
            guard enqueue(.inputSourceTerminated(termination)) else {
                return false
            }
            queuedInputSourceTermination = termination
            inputContinuation.finish()
            return true
        }

        /// Requests cancellation without cancelling an in-flight dependency call.
        func stop() {
            guard state == .running,
                  queuedInputSourceTermination == nil else {
                return
            }
            state = .stopping
            inputContinuation.finish()
            applyAndEnqueue(.cancel)
        }

        /// Waits until the paired runtime has terminated and reservation disposition has drained.
        func waitForTermination() async {
            let inputConsumerTask = inputConsumerTask
            let effectConsumerTask = effectConsumerTask
            await inputConsumerTask?.value
            await effectConsumerTask?.value
        }

        private func enqueue(_ input: QueuedInput) -> Bool {
            guard state == .running else {
                return false
            }
            switch inputContinuation.yield(input) {
            case .enqueued:
                return true
            case .dropped:
                failAndStop(.inputBufferOverflow)
                return false
            case .terminated:
                return false
            @unknown default:
                failAndStop(.inputBufferOverflow)
                return false
            }
        }

        private func consumeInputs() async {
            defer { failPendingRecoveryBarriers() }
            for await input in inputStream {
                if case let .runtimeRecoveryBarrier(identifier) = input {
                    completeRecoveryBarrier(
                        identifier,
                        result: state == .running
                    )
                    continue
                }
                guard state == .running else {
                    break
                }
                switch input {
                case let .runtime(runtimeInput):
                    applyAndEnqueue(runtimeInput)
                case let .authenticatedControl(delivery, source):
                    applyAuthenticatedControl(delivery, source: source)
                case let .authenticatedAbort(phase, reason):
                    guard runtimeSession.state.phase == phase else {
                        failAndStop(.runtime(.authenticatedAbortPhaseMismatch))
                        continue
                    }
                    applyAndEnqueue(.authenticatedAbort(reason))
                case let .inputSourceTerminated(termination):
                    queuedInputSourceTermination = nil
                    recordFailure(.inputSourceTerminated(termination))
                    state = .stopping
                    applyAndEnqueue(.cancel)
                case .runtimeRecoveryBarrier:
                    failAndStop(.recoveryBarrierMisordered)
                }
                await waitForEffectDrain()
            }
        }

        private func completeRecoveryBarrier(
            _ identifier: UUID,
            result: Bool
        ) {
            recoveryBarrierWaiters.removeValue(forKey: identifier)?
                .resume(returning: result)
        }

        private func failPendingRecoveryBarriers() {
            let waiters = recoveryBarrierWaiters.values
            recoveryBarrierWaiters.removeAll(keepingCapacity: true)
            for waiter in waiters {
                waiter.resume(returning: false)
            }
        }

        private func applyAuthenticatedControl(
            _ delivery: AdmissionLedger.ControlDelivery,
            source: PostManifestTransportIngress.RecoveredAdmission
        ) {
            var stagedRuntime = runtimeSession
            let application = stagedRuntime.applyAuthenticatedControl(delivery)
            if application.didConsumeReplayState {
                do {
                    try admissionJournal?.record(.init(
                        control: delivery,
                        source: source
                    ))
                } catch {
                    failAndStop(.admissionJournalFailed)
                    return
                }
            }
            runtimeSession = stagedRuntime
            enqueue(application.effects)
        }

        @discardableResult
        private func applyAndEnqueue(
            _ input: RuntimeSession.Input
        ) -> [RuntimeSession.Effect] {
            let effects = runtimeSession.apply(input: input)
            enqueue(effects)
            return effects
        }

        private func enqueue(_ effects: [RuntimeSession.Effect]) {
            for effect in effects {
                if case .localAttempt(
                    .walletReservationReleaseRequired
                ) = effect {
                    dispositionGate.requestRelease()
                }
                dependencies.runtimeEffectObserver(effect)
                pendingEffectCount += 1
                effectContinuation.yield(effect)
            }
        }

        private func consumeEffects() async {
            for await effect in effectStream {
                await handle(effect)
                pendingEffectCount -= 1
                if pendingEffectCount == 0 {
                    let waiters = effectDrainWaiters
                    effectDrainWaiters.removeAll(keepingCapacity: true)
                    for waiter in waiters {
                        waiter.resume()
                    }
                }
            }
        }

        private func waitForEffectDrain() async {
            guard pendingEffectCount > 0 else {
                return
            }
            await withCheckedContinuation { continuation in
                effectDrainWaiters.append(continuation)
            }
        }

        private func handle(_ effect: RuntimeSession.Effect) async {
            switch effect {
            case let .admission(admissionEffect):
                await handle(admissionEffect)

            case let .localAttempt(localEffect):
                await handle(localEffect)

            case let .reservationPublicationAccepted(reference):
                guard reservationReference == reference else {
                    failAndStop(.reservationPublicationLeaseMismatch)
                    return
                }

            case let .sessionTerminated(outcome):
                await finish(with: outcome)

            case .exactDuplicateIgnored, .inputRejected:
                break
            }
        }

        private func handle(_ effect: AdmissionLedger.Effect) async {
            switch effect {
            case let .manifestAdmitted(manifest):
                admittedManifest = manifest

            case let .authorizationResponseSetValidationRequired(
                responseSet,
                playerCommit
            ):
                validateAuthorizationResponses(
                    responseSet: responseSet,
                    playerCommit: playerCommit
                )

            case let .authorizationResponsesValidated(validation):
                if authorizationResponseValidation != validation {
                    failAndStop(.authorizationResponseValidationFailed)
                }

            case let .commitmentSetAdmitted(commitmentSet):
                await validateCommitmentAndPublishAnonymousComponents(
                    commitmentSet
                )

            case let .preSignAcknowledgementSetAdmitted(acknowledgements):
                admittedAcknowledgements = acknowledgements

            case let .completeTransactionValidationRequired(candidate):
                validateCompleteTransaction(candidate)

            case .aggregateReservationAccepted,
                 .aggregateFragmentAccepted,
                 .exactDuplicateIgnored,
                 .playerCommitAdmitted,
                 .playerCommitUnanimityReached,
                 .authorizationResponseSetAdmitted,
                 .componentSetAdmitted,
                 .anonymousComponentAdmitted,
                 .anonymousBCHSignatureAdmitted,
                 .bchSignatureSetReady,
                 .bchSignatureSetAdmitted,
                 .completeTransactionAdmitted,
                 .completeTransactionValidated,
                 .preSignAcknowledgementAdmitted,
                 .preSignAcknowledgementCollectionComplete,
                 .phaseAdvanced,
                 .attemptTerminated,
                 .inputRejected:
                break
            }
        }

        private func handle(
            _ effect: OpalFusion.Mosaic.LocalAttempt.Effect
        ) async {
            switch effect {
            case let .walletReservationEligible(
                contributor,
                materialIdentifier,
                manifestBinding
            ):
                guard contributor == context.localControlIdentity,
                      materialIdentifier == context.materialIdentifier else {
                    failAndStop(.effectContextMismatch)
                    return
                }
                guard let admittedManifest else {
                    failAndStop(.missingManifest)
                    return
                }
                guard admittedManifest.binding == manifestBinding else {
                    failAndStop(.effectContextMismatch)
                    return
                }
                await reserve(
                    for: .init(
                        context: context,
                        manifest: admittedManifest
                    )
                )

            case let .walletReservationReleaseRequired(
                contributor,
                materialIdentifier
            ):
                guard contributor == context.localControlIdentity,
                      materialIdentifier == context.materialIdentifier else {
                    failAndStop(.effectContextMismatch)
                    return
                }
                await releaseIfNeeded()

            case let .transcriptInclusionValidationRequired(
                contributor,
                materialIdentifier,
                transcript
            ):
                guard contributor == context.localControlIdentity,
                      materialIdentifier == context.materialIdentifier else {
                    failAndStop(.effectContextMismatch)
                    return
                }
                validateTranscriptInclusion(transcript)

            case let .preSignAcknowledgementRequired(
                contributor,
                materialIdentifier,
                roundIdentifier,
                transcriptRoot
            ):
                guard contributor == context.localControlIdentity,
                      materialIdentifier == context.materialIdentifier else {
                    failAndStop(.effectContextMismatch)
                    return
                }
                await publishPreSignAcknowledgement(
                    contributor: contributor,
                    roundIdentifier: roundIdentifier,
                    transcriptRoot: transcriptRoot
                )

            case let .bchSigningEligible(
                contributor,
                materialIdentifier,
                transcript
            ):
                guard contributor == context.localControlIdentity,
                      materialIdentifier == context.materialIdentifier else {
                    failAndStop(.effectContextMismatch)
                    return
                }
                await sign(transcript: transcript)

            case let .walletReservationCommitRequired(
                contributor,
                materialIdentifier
            ):
                guard contributor == context.localControlIdentity,
                      materialIdentifier == context.materialIdentifier else {
                    failAndStop(.effectContextMismatch)
                    return
                }
                await commitCompleteTransaction()

            case .attemptTerminated:
                break

            case let .inputRejected(failure):
                failAndStop(.localAttemptRejected(failure))
            }
        }

        private func reserve(
            for eligibility: ReservationEligibility
        ) async {
            guard reservationLifecycle == .unreserved else {
                failAndStop(.duplicateReservationEligibility)
                return
            }

            let request: OpalFusion.Host.MosaicReservationRequest
            do {
                request = try await dependencies.makeReservationRequest(
                    eligibility
                )
            } catch {
                failAndStop(.invalidReservationRequest)
                return
            }
            guard isValid(request, for: eligibility) else {
                failAndStop(.invalidReservationRequest)
                return
            }
            guard !dispositionGate.isReleaseRequested else {
                return
            }

            reservationLifecycle = .reservationInFlight
            let lease: OpalFusion.Host.MosaicReservationLease
            do {
                lease = try await reserveContribution(for: request)
            } catch {
                reservationLifecycle = .unreserved
                failAndStop(.reservationFailed)
                return
            }
            reservationLifecycle = .reserved(lease)
            guard lease.expiresAt == request.expiresAt else {
                failAndStop(.reservationLeaseExpirationMismatch)
                return
            }

            guard !dispositionGate.isReleaseRequested else {
                await releaseIfNeeded()
                return
            }
            guard dispositionGate.claimReservationPublication() else {
                await releaseIfNeeded()
                return
            }

            let execution = dependencies.execution
            let material: LocalContributionMaterial
            do {
                material = try await execution.makeLocalContributionMaterial(
                    eligibility,
                    lease
                )
            } catch {
                dispositionGate.finishReservationPublication()
                failAndStop(.localMaterialInvalid)
                return
            }
            do {
                try ReservationMaterialLeaseValidator.validate(
                    actualLease: lease,
                    materialLease: material.reservationLease
                )
            } catch {
                dispositionGate.finishReservationPublication()
                failAndStop(.reservationPublicationLeaseMismatch)
                return
            }
            let validation: RuntimeSession.ReservationPublicationValidation
            do {
                let request = RuntimeSession.ReservationPublicationRequest(
                    attemptIdentifier: context.attemptIdentifier,
                    generationIdentifier: context.generationIdentifier,
                    materialIdentifier: context.materialIdentifier,
                    contributor: context.localControlIdentity,
                    manifest: eligibility.manifest,
                    reservationLease: lease,
                    playerCommit: material.playerCommit
                )
                validation = try .init(
                    validating: request,
                    using: material
                )
            } catch {
                dispositionGate.finishReservationPublication()
                failAndStop(.localMaterialInvalid)
                return
            }
            guard !shouldStopBeforeSigning else {
                dispositionGate.finishReservationPublication()
                await releaseIfNeeded()
                return
            }
            localContributionMaterial = material
            do {
                try await execution.publishPlayerCommit(validation)
            } catch {
                dispositionGate.finishReservationPublication()
                failAndStop(.reservationPublicationFailed)
                return
            }
            dispositionGate.finishReservationPublication()

            guard !dispositionGate.isReleaseRequested else {
                await releaseIfNeeded()
                return
            }
            applyAndEnqueue(.reservationPublicationValidated(validation))
        }

        private func validateAuthorizationResponses(
            responseSet: AuthorizationResponseSet,
            playerCommit: PlayerCommit
        ) {
            guard let material = localContributionMaterial,
                  material.playerCommit == playerCommit else {
                failAndStop(.authorizationResponseValidationFailed)
                return
            }
            let validation: AuthorizationResponseSetMaterialValidation
            do {
                validation = try .init(
                    validating: responseSet,
                    material: material
                )
            } catch {
                failAndStop(.authorizationResponseValidationFailed)
                return
            }
            guard !shouldStopBeforeSigning else {
                return
            }
            let tokens = validation.componentAuthorizationTokens
            guard tokens.count == material.slots.count else {
                failAndStop(.authorizationResponseValidationFailed)
                return
            }
            var publications: [LocalAnonymousComponentPublication] = []
            publications.reserveCapacity(material.slots.count)
            do {
                for slot in material.slots {
                    guard tokens.indices.contains(slot.slot) else {
                        throw AnonymousPublicationError.tokenMissing
                    }
                    publications.append(
                        .init(
                            slot: slot.slot,
                            recipientEventIdentity: slot.recipientEventIdentity,
                            payload: try .init(
                                roundIdentifier:
                                    material.manifest.core.roundIdentifier,
                                authorizationToken: tokens[slot.slot],
                                component: slot.component
                            )
                        )
                    )
                }
            } catch {
                failAndStop(.authorizationResponseValidationFailed)
                return
            }
            authorizationResponseValidation = validation
            pendingAnonymousComponentPublications = publications
            applyAndEnqueue(
                .authorizationResponseSetValidated(
                    .init(validation: validation)
                )
            )
        }

        private func validateCommitmentAndPublishAnonymousComponents(
            _ commitmentSet: OpalFusion.Mosaic.OpalV0.CommitmentSet
        ) async {
            let execution = dependencies.execution
            guard let material = localContributionMaterial,
                  authorizationResponseValidation != nil,
                  let publications = pendingAnonymousComponentPublications else {
                failAndStop(.authorizationResponseValidationFailed)
                return
            }
            do {
                try material.validateCommitmentInclusion(in: commitmentSet)
            } catch {
                failAndStop(.commitmentInclusionValidationFailed)
                return
            }
            guard !shouldStopBeforeSigning else {
                return
            }
            let publicationValidation: AnonymousComponentPublicationValidation
            do {
                publicationValidation = try .init(
                    validating: publications,
                    material: material,
                    runtimeContext: context
                )
            } catch {
                failAndStop(.anonymousComponentPublicationFailed)
                return
            }
            do {
                try await execution.publishAnonymousComponents(
                    publicationValidation
                )
            } catch {
                failAndStop(.anonymousComponentPublicationFailed)
                return
            }
            guard !shouldStopBeforeSigning else {
                return
            }
            pendingAnonymousComponentPublications = nil
        }

        private func validateTranscriptInclusion(
            _ transcript: OpalFusion.Mosaic.OpalV0
                .UnsignedTransactionTranscript
        ) {
            guard let material = localContributionMaterial else {
                return
            }
            let validation: OpalFusion.Mosaic.LocalAttempt
                .TranscriptInclusionValidation
            do {
                validation = try .init(
                    attemptIdentifier: context.attemptIdentifier,
                    generationIdentifier: context.generationIdentifier,
                    contributor: context.localControlIdentity,
                    materialIdentifier: context.materialIdentifier,
                    transcript: transcript,
                    using: material
                )
            } catch {
                failAndStop(.transcriptInclusionValidationFailed)
                return
            }
            guard !shouldStopBeforeSigning else {
                return
            }
            transcriptInclusionValidation = validation
            applyAndEnqueue(.transcriptInclusionValidated(validation))
        }

        private func publishPreSignAcknowledgement(
            contributor: OpalFusion.Mosaic.Attempt.ControlIdentity,
            roundIdentifier: [UInt8],
            transcriptRoot: OpalFusion.Mosaic.Attempt.TranscriptRoot
        ) async {
            let execution = dependencies.execution
            guard let transcriptInclusionValidation,
                  transcriptInclusionValidation.contributor == contributor,
                  transcriptInclusionValidation.transcript.manifest
                    .roundIdentifier == roundIdentifier,
                  transcriptInclusionValidation.transcript.transcriptRoot
                    == transcriptRoot,
                  !shouldStopBeforeSigning else {
                return
            }
            do {
                try await execution.publishPreSignAcknowledgement(
                    transcriptInclusionValidation
                )
            } catch {
                failAndStop(.preSignAcknowledgementPublicationFailed)
            }
        }

        private func sign(
            transcript: OpalFusion.Mosaic.OpalV0
                .UnsignedTransactionTranscript
        ) async {
            let execution = dependencies.execution
            guard case let .reserved(lease) = reservationLifecycle,
                  let material = localContributionMaterial,
                  let authorizationResponseValidation,
                  let transcriptInclusionValidation,
                  transcriptInclusionValidation.transcript == transcript,
                  let admittedAcknowledgements else {
                failAndStop(.signingPrerequisiteMissing)
                return
            }
            guard !shouldStopBeforeSigning else {
                await releaseIfNeeded()
                return
            }

            let resolved: PreviousOutputResolver.Validation
            do {
                resolved = try await PreviousOutputResolver(
                    source: execution.previousOutputSource
                ).resolve(for: transcript)
            } catch {
                guard !shouldStopBeforeSigning else {
                    return
                }
                failAndStop(.previousOutputResolutionFailed)
                return
            }
            guard !shouldStopBeforeSigning else {
                return
            }

            let request: OpalFusion.Host.MosaicTransactionSigningRequest
            do {
                request = try SigningRequestBuilder.build(
                    context: context,
                    reservationPublication: try reservationPublicationValidation(
                        material: material
                    ),
                    transcriptInclusion: transcriptInclusionValidation,
                    acknowledgements: admittedAcknowledgements,
                    previousOutputs: resolved
                )
            } catch {
                failAndStop(.signingRequestFailed)
                return
            }
            guard dispositionGate.claimSigning() else {
                await releaseIfNeeded()
                return
            }

            previousOutputValidation = resolved
            reservationLifecycle = .signingMayHaveStarted(lease)
            let finalizedTransaction: OpalFusion.Host.FinalizedTransaction
            do {
                finalizedTransaction = try await execution.transactionHost
                    .finalizeMosaicTransaction(for: request)
            } catch {
                failAfterSigning(
                    .signingFailed,
                    reason: .signingFailed,
                    reference: lease.reference
                )
                return
            }
            reservationLifecycle = .locallySigned(lease, finalizedTransaction)
            guard state == .running,
                  !dispositionGate.isReleaseRequested else {
                requireRecovery(
                    reference: lease.reference,
                    reason: .signingMayHaveStarted
                )
                return
            }

            let publications: [LocalBCHSignaturePublication]
            do {
                publications = try LocalBCHSignatureBuilder.build(
                    finalizedTransaction: finalizedTransaction,
                    signingRequest: request,
                    transcript: transcript,
                    material: material,
                    authorizationValidation: authorizationResponseValidation
                )
            } catch {
                failAfterSigning(
                    .localBCHSignatureValidationFailed,
                    reason: .localBCHSignatureValidationFailed,
                    reference: lease.reference
                )
                return
            }
            do {
                let publicationValidation = try
                    AnonymousBCHSignaturePublicationValidation(
                        validating: publications,
                        transcriptInclusion:
                            transcriptInclusionValidation,
                        material: material,
                        runtimeContext: context
                    )
                try await execution.publishLocalBCHSignatures(
                    publicationValidation
                )
            } catch {
                failAfterSigning(
                    .localBCHSignaturePublicationFailed,
                    reason: .localBCHSignaturePublicationFailed,
                    reference: lease.reference
                )
                return
            }
            if state != .running || dispositionGate.isReleaseRequested {
                requireRecovery(
                    reference: lease.reference,
                    reason: .signingMayHaveStarted
                )
            }
        }

        private func validateCompleteTransaction(
            _ candidate: CompleteTransactionCandidate
        ) {
            guard let previousOutputValidation else {
                rejectCompleteTransaction(
                    candidate,
                    reason: .previousOutputResolutionFailed
                )
                return
            }
            let validation: CompleteTransactionValidation
            do {
                validation = try .init(
                    validating: candidate,
                    previousOutputs: previousOutputValidation
                )
            } catch {
                rejectCompleteTransaction(
                    candidate,
                    reason: .exactTransactionValidationFailed
                )
                return
            }
            completeTransactionValidation = validation
            applyAndEnqueue(.completeTransactionValidated(validation))
        }

        private func rejectCompleteTransaction(
            _ candidate: CompleteTransactionCandidate,
            reason: CompleteTransactionValidationRejection.Reason
        ) {
            if let reference = reservationReference {
                requireRecovery(
                    reference: reference,
                    reason: .completeTransactionValidationFailed
                )
            }
            recordFailure(.completeTransactionValidationFailed)
            applyAndEnqueue(
                .completeTransactionValidationFailed(
                    .init(candidate: candidate, reason: reason)
                )
            )
        }

        private func commitCompleteTransaction() async {
            let execution = dependencies.execution
            guard case let .locallySigned(lease, _) = reservationLifecycle,
                  let completeTransactionValidation else {
                if let reference = reservationReference {
                    requireRecovery(
                        reference: reference,
                        reason: .completeTransactionCommitFailed
                    )
                }
                recordFailure(.completeTransactionCommitFailed)
                return
            }
            do {
                try await execution.transactionHost.commitMosaicReservation(
                    lease.reference,
                    completeTransaction:
                        completeTransactionValidation.completeTransaction
                )
                reservationLifecycle = .committed(lease.reference)
            } catch {
                recordFailure(.completeTransactionCommitFailed)
                requireRecovery(
                    reference: lease.reference,
                    reason: .completeTransactionCommitFailed
                )
            }
        }

        private func reservationPublicationValidation(
            material: LocalContributionMaterial
        ) throws -> RuntimeSession.ReservationPublicationValidation {
            try .init(
                validating: .init(
                    attemptIdentifier: context.attemptIdentifier,
                    generationIdentifier: context.generationIdentifier,
                    materialIdentifier: context.materialIdentifier,
                    contributor: context.localControlIdentity,
                    manifest: material.manifest,
                    reservationLease: material.reservationLease,
                    playerCommit: material.playerCommit
                ),
                using: material
            )
        }

        private func reserveContribution(
            for request: OpalFusion.Host.MosaicReservationRequest
        ) async throws -> OpalFusion.Host.MosaicReservationLease {
            return try await dependencies.transactionHost
                .reserveMosaicContribution(for: request)
        }

        private func isValid(
            _ request: OpalFusion.Host.MosaicReservationRequest,
            for eligibility: ReservationEligibility
        ) -> Bool {
            let manifest = eligibility.manifest
            let requiredExcessFeeSatoshis: UInt64
            do {
                requiredExcessFeeSatoshis = try ContributionFeePolicy
                    .requiredExcessFeeSatoshis(
                        for: context.localControlIdentity,
                        in: context.roster
                    )
            } catch {
                return false
            }
            return eligibility.context == context
                && manifest.core.roster == context.roster
                && request.attemptIdentifier
                    == context.attemptIdentifier.validatedBytes
                && request.networkGenesisHash == manifest.core.networkGenesisHash
                && request.roundIdentifier == manifest.core.roundIdentifier
                && request.expiresAt
                    == dependencies.expectedReservationExpiration
                && request.componentCount == Int(manifest.core.componentCount)
                && request.feeRateSatoshisPerByte
                    == manifest.core.feeRateSatoshisPerByte
                && request.minimumExcessFeeSatoshis
                    == manifest.core.minimumExcessFeeSatoshis
                && request.maximumExcessFeeSatoshis
                    == manifest.core.maximumExcessFeeSatoshis
                && request.requiredExcessFeeSatoshis
                    == requiredExcessFeeSatoshis
                && request.transactionProfileIdentifier
                    == manifest.core.transactionProfileIdentifier
        }

        private func releaseIfNeeded() async {
            switch reservationLifecycle {
            case let .reserved(lease):
                do {
                    try await dependencies.transactionHost
                        .releaseMosaicReservation(lease.reference)
                    reservationLifecycle = .released(lease.reference)
                } catch {
                    reservationLifecycle = .releaseFailed(lease.reference)
                }

            case let .signingMayHaveStarted(lease),
                 let .locallySigned(lease, _):
                requireRecovery(
                    reference: lease.reference,
                    reason: pendingDisposition?.recovery?.reason
                        ?? .signingMayHaveStarted
                )

            case .unreserved, .reservationInFlight, .committed,
                 .released, .releaseFailed:
                break
            }
        }

        private func failAndStop(_ failure: Failure) {
            recordFailure(failure)
            guard state == .running else {
                return
            }
            state = .stopping
            inputContinuation.finish()
            applyAndEnqueue(.cancel)
        }

        private func failAfterSigning(
            _ failure: Failure,
            reason: Recovery.Reason,
            reference: OpalFusion.Host.MosaicReservationReference
        ) {
            recordFailure(failure)
            requireRecovery(reference: reference, reason: reason)
            guard state == .running else {
                return
            }
            state = .stopping
            inputContinuation.finish()
            applyAndEnqueue(.cancel)
        }

        private func requireRecovery(
            reference: OpalFusion.Host.MosaicReservationReference,
            reason: Recovery.Reason
        ) {
            let recovery = Recovery(
                reservationReference: reference,
                reason: reason
            )
            switch pendingDisposition {
            case nil:
                pendingDisposition = .recovery(
                    recovery,
                    fallbackFailure: nil
                )
            case let .failure(failure):
                pendingDisposition = .recovery(
                    recovery,
                    fallbackFailure: failure
                )
            case .recovery:
                break
            }
        }

        private func recordFailure(_ failure: Failure) {
            switch pendingDisposition {
            case nil:
                pendingDisposition = .failure(failure)
            case .failure:
                break
            case let .recovery(recovery, fallbackFailure):
                guard fallbackFailure == nil else { return }
                pendingDisposition = .recovery(
                    recovery,
                    fallbackFailure: failure
                )
            }
        }

        private func finish(with outcome: RuntimeSession.Outcome) async {
            inputContinuation.finish()
            if outcome == .completed {
                if case .committed = reservationLifecycle {
                    state = .terminal(.completed)
                } else if let reference = reservationReference {
                    state = .recoveryRequired(
                        pendingDisposition?.recovery ?? .init(
                            reservationReference: reference,
                            reason: .unexpectedRuntimeCompletion
                        )
                    )
                } else {
                    state = .terminal(.failed(.effectContextMismatch))
                }
                effectContinuation.finish()
                return
            }
            if case .reserved = reservationLifecycle {
                await releaseIfNeeded()
            }
            if case let .releaseFailed(reference) = reservationLifecycle {
                state = .recoveryRequired(
                    .init(
                        reservationReference: reference,
                        reason: .reservationReleaseFailed
                    )
                )
            } else if let reference = signingReservationReference {
                state = .recoveryRequired(
                    pendingDisposition?.recovery ?? .init(
                        reservationReference: reference,
                        reason: .signingMayHaveStarted
                    )
                )
            } else if let failure = pendingDisposition?.failure {
                state = .terminal(.failed(failure))
            } else {
                switch outcome {
                case let .failed(failure):
                    state = .terminal(.failed(.runtime(failure)))
                case let .cancelled(during: phase):
                    state = .terminal(.cancelled(during: phase))
                case .completed:
                    preconditionFailure("Handled before reservation disposition")
                }
            }
            effectContinuation.finish()
        }

        private var reservationReference:
            OpalFusion.Host.MosaicReservationReference? {
            switch reservationLifecycle {
            case let .reserved(lease),
                 let .signingMayHaveStarted(lease),
                 let .locallySigned(lease, _):
                lease.reference
            case let .committed(reference),
                 let .released(reference),
                 let .releaseFailed(reference):
                reference
            case .unreserved, .reservationInFlight:
                nil
            }
        }

        private var signingReservationReference:
            OpalFusion.Host.MosaicReservationReference? {
            switch reservationLifecycle {
            case let .signingMayHaveStarted(lease),
                 let .locallySigned(lease, _):
                lease.reference
            case .unreserved, .reservationInFlight, .reserved,
                 .committed, .released, .releaseFailed:
                nil
            }
        }

        private var shouldStopBeforeSigning: Bool {
            state != .running
                || dispositionGate.isReleaseRequested
                || pendingDisposition != nil
        }

        /// Returns the exact host-committed completion proof only after terminal completion.
        var terminalCompletionValidation: CompleteTransactionValidation? {
            guard state == .terminal(.completed) else { return nil }
            return completeTransactionValidation
        }

        private enum AnonymousPublicationError: Error {
            case tokenMissing
        }
    }
}

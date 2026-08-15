// OpalFusion+Mosaic+OpalMainnetAlpha+ConductorCoordinator.swift

import Foundation

extension OpalFusion.Mosaic.OpalMainnetAlpha {
    /// Executes one post-manifest conductor without wallet or broadcast authority.
    ///
    /// Every published document must return through authenticated admission before it can advance
    /// the paired runtime. Transport framing, event kinds, relay selection, and retry policy remain
    /// outside this actor.
    actor ConductorCoordinator {
        /// One coordinator-minted publication bound to the exact runtime material.
        struct PublicationValidation: Sendable, Equatable {
            let attemptIdentifier: Session.AttemptIdentifier
            let generationIdentifier: Session.GenerationIdentifier
            let materialIdentifier: Session.MaterialIdentifier
            let conductor: Session.ControlIdentity
            let manifestBinding: OpalFusion.Mosaic.Attempt.ManifestBinding
            let publication: Publication

            fileprivate init(
                context: Session.Context,
                manifestBinding: OpalFusion.Mosaic.Attempt.ManifestBinding,
                publication: Publication
            ) {
                attemptIdentifier = context.attemptIdentifier
                generationIdentifier = context.generationIdentifier
                materialIdentifier = context.materialIdentifier
                conductor = context.localControlIdentity
                self.manifestBinding = manifestBinding
                self.publication = publication
            }
        }

        private enum QueuedInput: Sendable {
            case control(Ledger.ControlDelivery)
            case authenticatedControl(
                Ledger.ControlDelivery,
                PostManifestTransportIngress.RecoveredAdmission
            )
            case anonymousComponent(Ledger.AnonymousDelivery)
            case anonymousBCHSignature(Ledger.AnonymousDelivery)
            case authenticatedAnonymousComponent(
                Ledger.AnonymousDelivery,
                PostManifestTransportIngress.RecoveredAdmission
            )
            case authenticatedAnonymousBCHSignature(
                Ledger.AnonymousDelivery,
                PostManifestTransportIngress.RecoveredAdmission
            )
            case authenticatedAbort(
                OpalFusion.Mosaic.Attempt.Phase,
                OpalFusion.Mosaic.Attempt.AbortReason
            )
            case inputSourceTerminated(InputSourceTermination)
            case retryRequested
            case runtimeRecoveryBarrier(UUID)
        }

        private enum OperationError: Error {
            case stopped
            case invalidAuthorizationLedgerEffect
        }

        private struct RoutedBCHSignatureValidator:
            AnonymousBCHSignatureAdmissionValidating
        {
            let previousOutputs: PreviousOutputResolver.Validation?

            func validateBCHSignatureAdmission(
                submission: BCHSignatureSubmission,
                acceptedInputComponent: OpalFusion.Mosaic.OpalV0.Component,
                transcript: OpalFusion.Mosaic.OpalV0
                    .UnsignedTransactionTranscript
            ) throws {
                guard let previousOutputs else {
                    throw OperationError.stopped
                }
                try BCHSignatureAdmissionValidator(
                    previousOutputs: previousOutputs
                ).validateBCHSignatureAdmission(
                    submission: submission,
                    acceptedInputComponent: acceptedInputComponent,
                    transcript: transcript
                )
            }
        }

        private let context: Session.Context
        private let dependencies: Dependencies
        private let inputStream: AsyncStream<QueuedInput>
        private let inputContinuation: AsyncStream<QueuedInput>.Continuation
        private let admissionJournal: PostManifestAdmissionJournal?

        private var runtimeSession: Session
        private var inputConsumerTask: Task<Void, Never>?
        private var playerCommits: [PlayerCommit]?
        private var expectedAuthorizationResponseSets: [
            OpalFusion.Mosaic.Attempt.ControlIdentity: AuthorizationResponseSet
        ] = [:]
        private var admittedManifestBinding: OpalFusion.Mosaic.Attempt
            .ManifestBinding?
        private var admittedAnonymousComponents: [
            AnonymousComponentAdmissionValidation
        ] = []
        private var transcript: OpalFusion.Mosaic.OpalV0
            .UnsignedTransactionTranscript?
        private var previousOutputValidation: PreviousOutputResolver.Validation?
        private var completeTransactionValidation: CompleteTransactionValidation?
        private var queuedInputSourceTermination: InputSourceTermination?
        private var pendingFailure: Failure?
        private var recoveryBarrierWaiters: [
            UUID: CheckedContinuation<Bool, Never>
        ] = [:]

        private(set) var state: State = .idle

        var runtimeSessionState: Session.State {
            runtimeSession.state
        }

        var runtimeSessionTerminalProtocolAbort: (
            phase: OpalFusion.Mosaic.Attempt.Phase,
            reason: OpalFusion.Mosaic.Attempt.AbortReason
        )? {
            runtimeSession.terminalProtocolAbort
        }

        init(
            runtimeSession: Session,
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
            guard context.localRole == .conductor else {
                throw .localPeerIsNotConductor
            }
            let (inputStream, inputContinuation) = AsyncStream<QueuedInput>
                .makeStream(
                    bufferingPolicy: .bufferingOldest(
                        dependencies.maximumPendingInputCount
                    )
                )
            self.context = context
            self.dependencies = dependencies
            self.runtimeSession = runtimeSession
            self.inputStream = inputStream
            self.inputContinuation = inputContinuation
            self.admissionJournal = admissionJournal
        }

        /// Starts the single ordered input consumer once.
        func start() {
            guard state == .idle else {
                return
            }
            state = .running
            inputConsumerTask = Task { [weak self] in
                await self?.consumeInputs()
            }
        }

        /// Queues one already-authenticated control delivery.
        @discardableResult
        func submitControl(_ delivery: Ledger.ControlDelivery) -> Bool {
            enqueue(.control(delivery))
        }

        /// Queues one transport-authenticated control delivery behind write-ahead admission.
        @discardableResult
        func submitAuthenticatedControl(
            _ delivery: Ledger.ControlDelivery,
            source: PostManifestTransportIngress.RecoveredAdmission
        ) -> Bool {
            enqueue(.authenticatedControl(delivery, source))
        }

        /// Queues one already-authenticated anonymous delivery by its envelope payload type.
        @discardableResult
        func submitAnonymous(
            _ delivery: Ledger.AnonymousDelivery
        ) -> Bool {
            switch delivery.envelope.payloadType {
            case .anonymousComponent:
                enqueue(.anonymousComponent(delivery))
            case .bchSignatureSubmission:
                enqueue(.anonymousBCHSignature(delivery))
            }
        }

        /// Queues one transport-authenticated anonymous delivery behind write-ahead admission.
        @discardableResult
        func submitAuthenticatedAnonymous(
            _ delivery: Ledger.AnonymousDelivery,
            source: PostManifestTransportIngress.RecoveredAdmission
        ) -> Bool {
            switch delivery.envelope.payloadType {
            case .anonymousComponent:
                enqueue(.authenticatedAnonymousComponent(delivery, source))
            case .bchSignatureSubmission:
                enqueue(.authenticatedAnonymousBCHSignature(delivery, source))
            }
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

        /// Waits behind every queued recovered delivery and all coordinator-owned effects.
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
            enqueue(.retryRequested)
        }

        /// Requests cancellation without cancelling an in-flight publication or resolver call.
        func stop() {
            guard queuedInputSourceTermination == nil else {
                return
            }
            beginStopping()
        }

        /// Reports unexpected loss of the authenticated input source.
        @discardableResult
        func inputSourceDidTerminate(
            _ termination: InputSourceTermination
        ) -> Bool {
            guard state == .running else {
                return false
            }
            switch inputContinuation.yield(.inputSourceTerminated(termination)) {
            case .enqueued:
                queuedInputSourceTermination = termination
                inputContinuation.finish()
                return true
            case .dropped:
                pendingFailure = pendingFailure ?? .inputBufferOverflow
                beginStopping()
                return false
            case .terminated:
                return false
            @unknown default:
                pendingFailure = pendingFailure ?? .inputBufferOverflow
                beginStopping()
                return false
            }
        }

        /// Waits until runtime termination and all ordered conductor work have drained.
        func waitForTermination() async {
            let inputConsumerTask = inputConsumerTask
            await inputConsumerTask?.value
        }

        private func enqueue(_ input: QueuedInput) -> Bool {
            guard state == .running else {
                return false
            }
            switch inputContinuation.yield(input) {
            case .enqueued:
                return true
            case .dropped:
                pendingFailure = pendingFailure ?? .inputBufferOverflow
                beginStopping()
                return false
            case .terminated:
                return false
            @unknown default:
                pendingFailure = pendingFailure ?? .inputBufferOverflow
                beginStopping()
                return false
            }
        }

        private func beginStopping() {
            guard state == .running else {
                return
            }
            state = .stopping
            inputContinuation.finish()
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
                await process(input)
                guard state == .running else {
                    break
                }
            }
            guard case .terminal = state else {
                await cancelRuntime()
                return
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

        private func process(_ input: QueuedInput) async {
            let effects: [Session.Effect]
            switch input {
            case let .control(delivery):
                effects = runtimeSession.apply(input: .control(delivery))
            case let .authenticatedControl(delivery, source):
                guard let stagedEffects = applyAuthenticatedControl(
                    delivery,
                    source: source
                )
                else { return }
                effects = stagedEffects
            case let .anonymousComponent(delivery):
                effects = runtimeSession.receiveAnonymousComponent(delivery)
            case let .anonymousBCHSignature(delivery):
                if case .active(.bchSigning) = runtimeSession.state,
                   previousOutputValidation == nil {
                    fail(.bchSignatureAdmissionUnavailable)
                    return
                }
                effects = runtimeSession.receiveAnonymousBCHSignature(
                    delivery,
                    using: RoutedBCHSignatureValidator(
                        previousOutputs: previousOutputValidation
                    )
                )
            case let .authenticatedAnonymousComponent(delivery, source):
                guard let stagedEffects = applyAuthenticatedAnonymousComponent(
                    delivery,
                    source: source
                ) else { return }
                effects = stagedEffects
            case let .authenticatedAnonymousBCHSignature(delivery, source):
                if case .active(.bchSigning) = runtimeSession.state,
                   previousOutputValidation == nil {
                    fail(.bchSignatureAdmissionUnavailable)
                    return
                }
                guard let stagedEffects = applyAuthenticatedAnonymousBCHSignature(
                    delivery,
                    source: source
                ) else { return }
                effects = stagedEffects
            case let .authenticatedAbort(phase, reason):
                guard runtimeSession.state.phase == phase else {
                    fail(.runtime(.authenticatedAbortPhaseMismatch))
                    return
                }
                effects = runtimeSession.apply(input: .authenticatedAbort(reason))
            case let .inputSourceTerminated(termination):
                queuedInputSourceTermination = nil
                pendingFailure = pendingFailure
                    ?? .inputSourceTerminated(termination)
                beginStopping()
                return
            case .retryRequested:
                effects = runtimeSession.apply(input: .retryRequested)
            case .runtimeRecoveryBarrier:
                fail(.recoveryBarrierMisordered)
                return
            }
            await handle(effects)
        }

        private func applyAuthenticatedControl(
            _ delivery: Ledger.ControlDelivery,
            source: PostManifestTransportIngress.RecoveredAdmission
        ) -> [Session.Effect]? {
            var stagedRuntime = runtimeSession
            let application = stagedRuntime.applyAuthenticatedControl(delivery)
            return install(
                stagedRuntime,
                effects: application.effects,
                record: application.didConsumeReplayState
                    ? .init(control: delivery, source: source)
                    : nil
            )
        }

        private func applyAuthenticatedAnonymousComponent(
            _ delivery: Ledger.AnonymousDelivery,
            source: PostManifestTransportIngress.RecoveredAdmission
        ) -> [Session.Effect]? {
            var stagedRuntime = runtimeSession
            let application = stagedRuntime
                .receiveAuthenticatedAnonymousComponent(delivery)
            return install(
                stagedRuntime,
                effects: application.effects,
                record: application.didConsumeReplayState
                    ? .init(anonymous: delivery, source: source)
                    : nil
            )
        }

        private func applyAuthenticatedAnonymousBCHSignature(
            _ delivery: Ledger.AnonymousDelivery,
            source: PostManifestTransportIngress.RecoveredAdmission
        ) -> [Session.Effect]? {
            var stagedRuntime = runtimeSession
            let application = stagedRuntime
                .receiveAuthenticatedAnonymousBCHSignature(
                    delivery,
                    using: RoutedBCHSignatureValidator(
                        previousOutputs: previousOutputValidation
                    )
                )
            return install(
                stagedRuntime,
                effects: application.effects,
                record: application.didConsumeReplayState
                    ? .init(anonymous: delivery, source: source)
                    : nil
            )
        }

        private func install(
            _ stagedRuntime: Session,
            effects: [Session.Effect],
            record: PostManifestAdmissionJournal.AcceptedRecord?
        ) -> [Session.Effect]? {
            do {
                if let record {
                    try admissionJournal?.record(record)
                }
            } catch {
                fail(.admissionJournalFailed)
                return nil
            }
            runtimeSession = stagedRuntime
            return effects
        }

        private func handle(_ effects: [Session.Effect]) async {
            for effect in effects {
                switch effect {
                case let .admission(admissionEffect):
                    await handle(admissionEffect)
                case let .localAttempt(localEffect):
                    handle(localEffect)
                case let .sessionTerminated(outcome):
                    finish(with: outcome)
                case .reservationPublicationAccepted:
                    fail(.unexpectedLocalAttemptEffect)
                case .exactDuplicateIgnored, .inputRejected:
                    break
                }
                guard state == .running || state == .stopping else {
                    return
                }
            }
        }

        private func handle(_ effect: OpalFusion.Mosaic.LocalAttempt.Effect) {
            switch effect {
            case .attemptTerminated:
                break
            case .walletReservationEligible,
                 .walletReservationReleaseRequired,
                 .transcriptInclusionValidationRequired,
                 .preSignAcknowledgementRequired,
                 .bchSigningEligible,
                 .walletReservationCommitRequired,
                 .inputRejected:
                fail(.unexpectedLocalAttemptEffect)
            }
        }

        private func handle(_ effect: Ledger.Effect) async {
            switch effect {
            case let .manifestAdmitted(manifest):
                guard dependencies.componentAuthorizationEvaluator.verificationKey
                        == manifest.core.componentAuthorizationVerificationKey,
                      dependencies.bchSignatureAuthorizationEvaluator.verificationKey
                        == manifest.core.bchSignatureAuthorizationVerificationKey else {
                    fail(.authorizationKeyMismatch)
                    return
                }
                admittedManifestBinding = manifest.binding

            case let .playerCommitUnanimityReached(commits):
                await issueAndPublishAuthorizationResponses(for: commits)

            case let .authorizationResponseSetAdmitted(responseSet):
                guard expectedAuthorizationResponseSets[responseSet.contributor]
                        == responseSet else {
                    fail(.authorizationResponseSetMismatch)
                    return
                }

            case let .anonymousComponentAdmitted(validation):
                admittedAnonymousComponents.append(validation)
                if admittedAnonymousComponents.count == expectedComponentCount {
                    await publishComponentSet()
                }

            case let .componentSetAdmitted(_, admittedTranscript):
                transcript = admittedTranscript
                await resolvePreviousOutputs(for: admittedTranscript)

            case let .preSignAcknowledgementCollectionComplete(submissions):
                await publishAcknowledgementSet(submissions)

            case let .bchSignatureSetReady(signatureSet):
                await publish(.bchSignatureSet(signatureSet))

            case let .bchSignatureSetAdmitted(signatureSet):
                await assembleAndPublishCompleteTransaction(signatureSet)

            case let .completeTransactionValidationRequired(candidate):
                await validateCompleteTransaction(candidate)

            case let .phaseAdvanced(context):
                if case .groupedCommitment = context {
                    await publishCommitmentSet()
                }

            case .aggregateReservationAccepted,
                 .aggregateFragmentAccepted,
                 .exactDuplicateIgnored,
                 .playerCommitAdmitted,
                 .authorizationResponseSetValidationRequired,
                 .authorizationResponsesValidated,
                 .commitmentSetAdmitted,
                 .anonymousBCHSignatureAdmitted,
                 .completeTransactionAdmitted,
                 .completeTransactionValidated,
                 .preSignAcknowledgementAdmitted,
                 .preSignAcknowledgementSetAdmitted,
                 .attemptTerminated,
                 .inputRejected:
                break
            }
        }

        private func issueAndPublishAuthorizationResponses(
            for commits: [PlayerCommit]
        ) async {
            guard playerCommits == nil,
                  commits.count == context.roster.contributors.count else {
                fail(.authorizationIssuanceFailed)
                return
            }
            playerCommits = commits

            var componentLedger = OpalFusion.Mosaic.OpalV0
                .AuthorizationIssuanceLedger(roster: context.roster)
            var bchSignatureLedger = OpalFusion.Mosaic.OpalV0
                .AuthorizationIssuanceLedger(roster: context.roster)
            do {
                let componentEvaluations = try collectAuthorizationRequests(
                    from: commits,
                    purpose: .component,
                    into: &componentLedger
                )
                let bchSignatureEvaluations = try collectAuthorizationRequests(
                    from: commits,
                    purpose: .bchSignature,
                    into: &bchSignatureLedger
                )
                try await evaluate(
                    componentEvaluations,
                    using: dependencies.componentAuthorizationEvaluator,
                    in: &componentLedger
                )
                try await evaluate(
                    bchSignatureEvaluations,
                    using: dependencies.bchSignatureAuthorizationEvaluator,
                    in: &bchSignatureLedger
                )
            } catch is OperationError {
                guard state == .running else { return }
                fail(.authorizationIssuanceFailed)
                return
            } catch {
                guard state == .running else { return }
                fail(.authorizationIssuanceFailed)
                return
            }
            guard state == .running else {
                return
            }
            let responseSets: [AuthorizationResponseSet]
            do {
                responseSets = try commits.map {
                    try .init(
                        playerCommit: $0,
                        componentIssuingFrom: componentLedger,
                        bchSignatureIssuingFrom: bchSignatureLedger
                    )
                }
            } catch {
                fail(.authorizationResponseSetConstructionFailed)
                return
            }
            for responseSet in responseSets {
                guard state == .running else { return }
                guard expectedAuthorizationResponseSets.updateValue(
                    responseSet,
                    forKey: responseSet.contributor
                ) == nil else {
                    fail(.authorizationResponseSetConstructionFailed)
                    return
                }
                await publish(.authorizationResponseSet(responseSet))
            }
        }

        private func collectAuthorizationRequests(
            from commits: [PlayerCommit],
            purpose: AuthorizationPurpose,
            into ledger: inout OpalFusion.Mosaic.OpalV0
                .AuthorizationIssuanceLedger
        ) throws -> [OpalFusion.Mosaic.OpalV0.AuthorizationIssuanceLedger
            .Evaluation] {
            var evaluations: [OpalFusion.Mosaic.OpalV0
                .AuthorizationIssuanceLedger.Evaluation] = []
            for commit in commits {
                let requests = switch purpose {
                case .component:
                    commit.componentAuthorizationRequests
                case .bchSignature:
                    commit.bchSignatureAuthorizationRequests
                }
                for request in requests {
                    let effects = ledger.apply(
                        input: .request(
                            contributor: commit.contributor,
                            slot: request.slot,
                            blindedMessage: request.blindedMessage
                        )
                    )
                    for effect in effects {
                        switch effect {
                        case let .evaluate(evaluation):
                            evaluations.append(evaluation)
                        case .terminated, .inputRejected:
                            throw OperationError.invalidAuthorizationLedgerEffect
                        case .deliver, .issuanceComplete:
                            throw OperationError.invalidAuthorizationLedgerEffect
                        }
                    }
                }
            }
            return evaluations
        }

        private func evaluate(
            _ evaluations: [OpalFusion.Mosaic.OpalV0
                .AuthorizationIssuanceLedger.Evaluation],
            using evaluator: OpalFusion.Mosaic.OpalV0.AuthorizationEvaluator,
            in ledger: inout OpalFusion.Mosaic.OpalV0
                .AuthorizationIssuanceLedger
        ) async throws {
            for evaluation in evaluations {
                await Task.yield()
                guard state == .running else {
                    throw OperationError.stopped
                }
                let response = OpalFusion.Mosaic.OpalV0
                    .AuthorizationIssuanceLedger.Response(
                        key: evaluation.key,
                        blindSignature: try evaluator.evaluate(
                            evaluation.blindedMessage
                        )
                    )
                let effects = ledger.apply(input: .evaluated(response))
                guard effects.allSatisfy({ effect in
                    switch effect {
                    case .deliver, .issuanceComplete:
                        true
                    case .evaluate, .terminated, .inputRejected:
                        false
                    }
                }) else {
                    throw OperationError.invalidAuthorizationLedgerEffect
                }
            }
        }

        private func publishCommitmentSet() async {
            guard let playerCommits else {
                fail(.commitmentSetConstructionFailed)
                return
            }
            let commitmentSet: OpalFusion.Mosaic.OpalV0.CommitmentSet
            do {
                commitmentSet = try .init(
                    profile: .opalMainnetAlpha,
                    commitments: playerCommits.flatMap {
                        $0.groupedCommitment.commitments
                    }
                )
            } catch {
                fail(.commitmentSetConstructionFailed)
                return
            }
            await publish(.commitmentSet(commitmentSet))
        }

        private func publishComponentSet() async {
            let componentSet: OpalFusion.Mosaic.OpalV0.ComponentSet
            do {
                componentSet = try .init(
                    profile: .opalMainnetAlpha,
                    components: admittedAnonymousComponents.map {
                        $0.payload.component
                    }
                )
            } catch {
                fail(.componentSetConstructionFailed)
                return
            }
            await publish(.componentSet(componentSet))
        }

        private func resolvePreviousOutputs(
            for transcript: OpalFusion.Mosaic.OpalV0
                .UnsignedTransactionTranscript
        ) async {
            guard previousOutputValidation == nil else {
                fail(.previousOutputResolutionFailed)
                return
            }
            let validation: PreviousOutputResolver.Validation
            do {
                validation = try await PreviousOutputResolver(
                    source: dependencies.previousOutputSource
                ).resolve(for: transcript)
            } catch {
                guard state == .running else { return }
                fail(.previousOutputResolutionFailed)
                return
            }
            guard state == .running else { return }
            previousOutputValidation = validation
        }

        private func publishAcknowledgementSet(
            _ submissions: [PreSignAcknowledgementSubmission]
        ) async {
            guard let transcript else {
                fail(.preSignAcknowledgementSetConstructionFailed)
                return
            }
            let set: PreSignAcknowledgementSet
            do {
                set = try .init(
                    roundIdentifier: transcript.manifest.roundIdentifier,
                    transcriptRoot: transcript.transcriptRoot.validatedBytes,
                    roster: context.roster,
                    submissions: submissions
                )
            } catch {
                fail(.preSignAcknowledgementSetConstructionFailed)
                return
            }
            await publish(.preSignAcknowledgementSet(set))
        }

        private func assembleAndPublishCompleteTransaction(
            _ signatureSet: BCHSignatureSet
        ) async {
            guard let transcript, let previousOutputValidation else {
                fail(.completeTransactionAssemblyFailed)
                return
            }
            let payload: CompleteTransactionPayload
            do {
                let completeTransaction = try CompleteTransactionAssembler
                    .assemble(
                        transcript: transcript,
                        signatureSet: signatureSet,
                        spentInputs: previousOutputValidation.spentInputs
                    )
                payload = try .init(
                    roundIdentifier: transcript.manifest.roundIdentifier,
                    transcriptRoot: transcript.transcriptRoot.validatedBytes,
                    completeTransaction: completeTransaction
                )
            } catch {
                fail(.completeTransactionAssemblyFailed)
                return
            }
            await publish(.completeTransaction(payload))
        }

        private func validateCompleteTransaction(
            _ candidate: CompleteTransactionCandidate
        ) async {
            guard let previousOutputValidation else {
                fail(.completeTransactionValidationFailed)
                return
            }
            let validation: CompleteTransactionValidation
            do {
                validation = try .init(
                    validating: candidate,
                    previousOutputs: previousOutputValidation
                )
            } catch {
                let effects = runtimeSession.apply(
                    input: .completeTransactionValidationFailed(
                        .init(
                            candidate: candidate,
                            reason: .exactTransactionValidationFailed
                        )
                    )
                )
                pendingFailure = pendingFailure
                    ?? .completeTransactionValidationFailed
                await handle(effects)
                return
            }
            let effects = runtimeSession.apply(
                input: .completeTransactionValidated(validation)
            )
            completeTransactionValidation = validation
            await handle(effects)
        }

        private func publish(_ publication: Publication) async {
            guard state == .running else {
                return
            }
            guard let admittedManifestBinding else {
                fail(.unexpectedLocalAttemptEffect)
                return
            }
            do {
                try await dependencies.handoffPublication(
                    .init(
                        context: context,
                        manifestBinding: admittedManifestBinding,
                        publication: publication
                    )
                )
            } catch {
                guard state == .running else { return }
                fail(.publicationFailed(publication.kind))
                return
            }
        }

        private func fail(_ failure: Failure) {
            pendingFailure = pendingFailure ?? failure
            beginStopping()
        }

        private func cancelRuntime() async {
            guard case .terminal = runtimeSession.state else {
                let effects = runtimeSession.apply(input: .cancel)
                await handle(effects)
                if case .terminal = state {
                    return
                }
                state = .terminal(.failed(pendingFailure ?? .unexpectedLocalAttemptEffect))
                return
            }
            if case let .terminal(outcome) = runtimeSession.state {
                finish(with: outcome)
            }
        }

        private func finish(with outcome: Session.Outcome) {
            guard case .terminal = state else {
                inputContinuation.finish()
                switch outcome {
                case .completed:
                    state = .terminal(.completed)
                case let .failed(failure):
                    state = .terminal(
                        .failed(pendingFailure ?? .runtime(failure))
                    )
                case let .cancelled(during: phase):
                    if let pendingFailure {
                        state = .terminal(.failed(pendingFailure))
                    } else {
                        state = .terminal(.cancelled(during: phase))
                    }
                }
                return
            }
        }

        private var expectedComponentCount: Int {
            context.roster.contributors.count * componentCountPerContributor
        }

        /// Returns the exact previous-output-validated completion only after terminal completion.
        var terminalCompletionValidation: CompleteTransactionValidation? {
            guard state == .terminal(.completed) else { return nil }
            return completeTransactionValidation
        }
    }
}

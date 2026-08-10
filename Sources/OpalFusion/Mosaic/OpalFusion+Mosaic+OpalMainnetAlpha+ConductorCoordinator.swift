// OpalFusion+Mosaic+OpalMainnetAlpha+ConductorCoordinator.swift

extension OpalFusion.Mosaic.OpalMainnetAlpha {
    /// Executes one post-manifest conductor without wallet or broadcast authority.
    ///
    /// Every published document must return through authenticated admission before it can advance
    /// the paired runtime. Transport framing, event kinds, relay selection, and retry policy remain
    /// outside this actor.
    actor ConductorCoordinator {
        private enum QueuedInput: Sendable {
            case control(Ledger.ControlDelivery)
            case anonymousComponent(Ledger.AnonymousDelivery)
            case anonymousBCHSignature(Ledger.AnonymousDelivery)
            case inputSourceTerminated(InputSourceTermination)
            case retryRequested
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

        private var runtimeSession: Session
        private var inputConsumerTask: Task<Void, Never>?
        private var playerCommits: [PlayerCommit]?
        private var expectedAuthorizationResponseSets: [
            OpalFusion.Mosaic.Attempt.ControlIdentity: AuthorizationResponseSet
        ] = [:]
        private var admittedAnonymousComponents: [
            AnonymousComponentAdmissionValidation
        ] = []
        private var transcript: OpalFusion.Mosaic.OpalV0
            .UnsignedTransactionTranscript?
        private var previousOutputValidation: PreviousOutputResolver.Validation?
        private var pendingFailure: Failure?

        private(set) var state: State = .idle

        var runtimeSessionState: Session.State {
            runtimeSession.state
        }

        init(
            runtimeSession: Session,
            dependencies: Dependencies
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

        /// Queues one already-authenticated component-mailbox delivery.
        @discardableResult
        func submitAnonymousComponent(
            _ delivery: Ledger.AnonymousDelivery
        ) -> Bool {
            enqueue(.anonymousComponent(delivery))
        }

        /// Queues one already-authenticated BCH-signature mailbox delivery.
        @discardableResult
        func submitAnonymousBCHSignature(
            _ delivery: Ledger.AnonymousDelivery
        ) -> Bool {
            enqueue(.anonymousBCHSignature(delivery))
        }

        /// Rejects an in-place retry through the paired runtime.
        @discardableResult
        func requestRetry() -> Bool {
            enqueue(.retryRequested)
        }

        /// Requests cancellation without cancelling an in-flight publication or resolver call.
        func stop() {
            beginStopping()
        }

        /// Reports unexpected loss of the authenticated input source.
        func inputSourceDidTerminate(_ termination: InputSourceTermination) {
            guard state == .running else {
                return
            }
            switch inputContinuation.yield(.inputSourceTerminated(termination)) {
            case .enqueued:
                pendingFailure = pendingFailure
                    ?? .inputSourceTerminated(termination)
                inputContinuation.finish()
            case .dropped:
                pendingFailure = .inputBufferOverflow
                beginStopping()
            case .terminated:
                break
            @unknown default:
                pendingFailure = .inputBufferOverflow
                beginStopping()
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
                pendingFailure = .inputBufferOverflow
                beginStopping()
                return false
            case .terminated:
                return false
            @unknown default:
                pendingFailure = .inputBufferOverflow
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
            for await input in inputStream {
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

        private func process(_ input: QueuedInput) async {
            let effects: [Session.Effect]
            switch input {
            case let .control(delivery):
                effects = runtimeSession.apply(input: .control(delivery))
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
            case let .inputSourceTerminated(termination):
                pendingFailure = pendingFailure
                    ?? .inputSourceTerminated(termination)
                beginStopping()
                return
            case .retryRequested:
                effects = runtimeSession.apply(input: .retryRequested)
            }
            await handle(effects)
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
            await handle(effects)
        }

        private func publish(_ publication: Publication) async {
            guard state == .running else {
                return
            }
            do {
                try await dependencies.handoffPublication(publication)
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
    }
}

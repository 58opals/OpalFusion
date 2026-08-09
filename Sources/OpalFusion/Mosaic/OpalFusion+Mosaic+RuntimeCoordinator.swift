// OpalFusion+Mosaic+RuntimeCoordinator.swift

extension OpalFusion.Mosaic {
    /// Executes one local contributor's ordered host effects above a runtime-session driver.
    ///
    /// The coordinator never owns private keys, transport routing, durable recovery, or broadcast.
    /// It drains reducer outputs in order, treats a late reservation as disposable, and permanently
    /// stops automatic release once wallet signing may have begun. A retry requires a new instance.
    actor RuntimeCoordinator {
        private let driver: RuntimeSessionDriver
        private let dependencies: Dependencies
        private let context: AttemptContext
        private let outputStream: AsyncStream<RuntimeSessionDriver.Output>
        private let outputContinuation: AsyncStream<RuntimeSessionDriver.Output>.Continuation
        private let dispositionGate: MosaicRuntimeCoordinatorDispositionGate

        private var outputConsumerTask: Task<Void, Never>?
        private var driverWaitTask: Task<Void, Never>?
        private var cancellationRequested = false
        private var pendingFailure: Failure?
        private var pendingRecovery: Recovery?
        private var pendingAttemptOutcome: Attempt.Outcome?
        private var inputSourceTermination: RuntimeSessionDriver.InputSourceTermination?

        private(set) var state: State = .idle
        private(set) var reservationLifecycle: ReservationLifecycle = .unreserved

        init(
            runtimeSession: RuntimeSession,
            dependencies: Dependencies
        ) throws {
            guard runtimeSession.localRole == .contributor else {
                throw Failure.localPeerIsNotContributor
            }

            let context = AttemptContext(
                attemptIdentifier: runtimeSession.attemptIdentifier,
                generationIdentifier: runtimeSession.generationIdentifier,
                materialIdentifier: runtimeSession.materialIdentifier,
                contributor: runtimeSession.localControlIdentity,
                profile: runtimeSession.configuration.profile
            )
            let (outputStream, outputContinuation) = AsyncStream<
                RuntimeSessionDriver.Output
            >.makeStream()
            let dispositionGate = MosaicRuntimeCoordinatorDispositionGate()
            self.context = context
            self.dependencies = dependencies
            self.outputStream = outputStream
            self.outputContinuation = outputContinuation
            self.dispositionGate = dispositionGate
            self.driver = try RuntimeSessionDriver(
                runtimeSession: runtimeSession,
                dependencies: .init(
                    openInputStream: dependencies.openInputStream,
                    closeInputSource: dependencies.closeInputSource,
                    outputSink: { output in
                        dispositionGate.observe(output)
                        outputContinuation.yield(output)
                    }
                )
            )
        }

        /// Starts ordered output execution once. Later calls are idempotent.
        func start() async {
            guard state == .idle else {
                return
            }
            state = .running

            outputConsumerTask = Task { [weak self] in
                await self?.consumeOutputs()
            }
            await driver.start()
            driverWaitTask = Task { [driver, outputContinuation] in
                await driver.waitForTermination()
                outputContinuation.finish()
            }
        }

        /// Requests local cancellation without cancelling in-flight wallet work.
        func stop() async {
            guard state == .running || state == .stopping else {
                return
            }
            cancellationRequested = true
            state = .stopping
            await driver.stop()
        }

        /// Waits until the driver has stopped and every queued disposition has completed.
        func waitForTermination() async {
            let driverWaitTask = driverWaitTask
            let outputConsumerTask = outputConsumerTask
            await driverWaitTask?.value
            await outputConsumerTask?.value
        }

        private func consumeOutputs() async {
            for await output in outputStream {
                await handle(output)
            }
            finishAfterDrain()
        }

        private func handle(_ output: RuntimeSessionDriver.Output) async {
            switch output {
            case let .runtimeEffect(.localAttempt(effect)):
                await handle(effect)
            case let .inputSourceTerminated(termination):
                inputSourceTermination = termination
            case .runtimeEffect(.exactDuplicateIgnored),
                 .runtimeEffect(.authenticatedInputRejected),
                 .runtimeEffect(.hostResultRejected):
                break
            }
        }

        private func handle(_ effect: LocalAttempt.Effect) async {
            switch effect {
            case let .walletReservationEligible(
                contributor,
                materialIdentifier,
                manifest
            ):
                guard contributor == context.contributor,
                      materialIdentifier == context.materialIdentifier else {
                    await failAndStop(.effectContextMismatch)
                    return
                }
                await reserve(
                    for: .init(context: context, manifest: manifest)
                )

            case let .transcriptInclusionValidationRequired(
                contributor,
                materialIdentifier,
                transcript
            ):
                guard contributor == context.contributor,
                      materialIdentifier == context.materialIdentifier else {
                    await failAndStop(.effectContextMismatch)
                    return
                }
                await validateTranscriptInclusion(
                    .init(context: context, transcript: transcript)
                )

            case let .preSignAcknowledgementRequired(
                contributor,
                materialIdentifier,
                roundIdentifier,
                transcriptRoot
            ):
                guard contributor == context.contributor,
                      materialIdentifier == context.materialIdentifier else {
                    await failAndStop(.effectContextMismatch)
                    return
                }
                await publishPreSignAcknowledgement(
                    .init(
                        context: context,
                        roundIdentifier: roundIdentifier,
                        transcriptRoot: transcriptRoot
                    )
                )

            case let .bchSigningEligible(
                contributor,
                materialIdentifier,
                transcript
            ):
                guard contributor == context.contributor,
                      materialIdentifier == context.materialIdentifier else {
                    await failAndStop(.effectContextMismatch)
                    return
                }
                await sign(
                    for: .init(context: context, transcript: transcript)
                )

            case let .walletReservationReleaseRequired(
                contributor,
                materialIdentifier
            ):
                guard contributor == context.contributor,
                      materialIdentifier == context.materialIdentifier else {
                    await failAndStop(.effectContextMismatch)
                    return
                }
                await releaseIfSafe()

            case let .walletReservationCommitRequired(
                contributor,
                materialIdentifier
            ):
                guard contributor == context.contributor,
                      materialIdentifier == context.materialIdentifier else {
                    await failAndStop(.effectContextMismatch)
                    return
                }
                await commitCompleteTransaction()

            case let .attemptTerminated(outcome):
                pendingAttemptOutcome = outcome

            case let .inputRejected(failure):
                await failAndStop(.localResultRejected(failure))
            }
        }

        private func reserve(
            for eligibility: ReservationEligibility
        ) async {
            guard reservationLifecycle == .unreserved else {
                await failAndStop(.duplicateReservationEligibility)
                return
            }
            reservationLifecycle = .reservationInFlight

            let request: OpalFusion.Host.MosaicReservationRequest
            do {
                request = try await dependencies.makeReservationRequest(eligibility)
            } catch {
                reservationLifecycle = .unreserved
                await failAndStop(.reservationRequestFailed)
                return
            }
            if shouldStopBeforeSigning {
                reservationLifecycle = .unreserved
                return
            }

            let lease: OpalFusion.Host.MosaicReservationLease
            do {
                lease = try await dependencies.transactionHost
                    .reserveMosaicContribution(for: request)
            } catch {
                reservationLifecycle = .unreserved
                await failAndStop(.reservationFailed)
                return
            }
            reservationLifecycle = .reserved(lease)

            if shouldStopBeforeSigning {
                await releaseIfSafe()
                return
            }
            guard !cancellationRequested,
                  pendingFailure == nil,
                  dispositionGate.claimReservationPublication() else {
                await releaseIfSafe()
                return
            }
            do {
                try await dependencies.publishReservedContribution(
                    eligibility,
                    lease
                )
            } catch {
                dispositionGate.finishReservationPublication()
                await failAndStop(.reservationPublicationFailed)
                return
            }
            dispositionGate.finishReservationPublication()
        }

        private func validateTranscriptInclusion(
            _ request: TranscriptInclusionRequest
        ) async {
            guard !shouldStopBeforeSigning else {
                return
            }
            let validation: LocalAttempt.TranscriptInclusionValidation
            do {
                validation = try await dependencies
                    .validateTranscriptInclusion(request)
            } catch {
                await failAndStop(.transcriptInclusionValidationFailed)
                return
            }
            guard !shouldStopBeforeSigning else {
                return
            }
            _ = await driver.submit(
                .local(.transcriptInclusionValidated(validation))
            )
        }

        private func publishPreSignAcknowledgement(
            _ publication: PreSignPublication
        ) async {
            guard !shouldStopBeforeSigning else {
                return
            }
            do {
                try await dependencies.publishPreSignAcknowledgement(publication)
            } catch {
                await failAndStop(.preSignPublicationFailed)
            }
        }

        private func sign(
            for eligibility: SigningEligibility
        ) async {
            guard case let .reserved(lease) = reservationLifecycle else {
                await failAndStop(.missingReservation)
                return
            }

            let request: OpalFusion.Host.MosaicTransactionSigningRequest
            do {
                request = try await dependencies.makeSigningRequest(
                    eligibility,
                    lease
                )
            } catch {
                await failAndStop(.signingRequestFailed)
                return
            }
            guard !cancellationRequested,
                  pendingFailure == nil,
                  dispositionGate.claimSigning() else {
                await releaseIfSafe()
                return
            }

            reservationLifecycle = .signingMayHaveStarted(lease)
            let finalizedTransaction: OpalFusion.Host.FinalizedTransaction
            do {
                finalizedTransaction = try await dependencies.transactionHost
                    .finalizeMosaicTransaction(for: request)
            } catch {
                requireRecovery(reference: lease.reference, reason: .signingFailed)
                await stopDriverAfterFailure(.signingFailed)
                return
            }
            reservationLifecycle = .locallySigned(lease, finalizedTransaction)

            guard !shouldStopBeforeSigning else {
                requireRecovery(
                    reference: lease.reference,
                    reason: .cancellationAfterSigningMayHaveStarted
                )
                return
            }
            do {
                try await dependencies.validateAndPublishLocalSignatures(
                    eligibility,
                    request,
                    finalizedTransaction
                )
            } catch {
                requireRecovery(
                    reference: lease.reference,
                    reason: .localSignaturePublicationFailed
                )
                await stopDriverAfterFailure(.localSignaturePublicationFailed)
            }
        }

        private func releaseIfSafe() async {
            switch reservationLifecycle {
            case let .reserved(lease):
                do {
                    try await dependencies.transactionHost
                        .releaseMosaicReservation(lease.reference)
                    reservationLifecycle = .released(lease.reference)
                } catch {
                    pendingFailure = pendingFailure ?? .reservationReleaseFailed
                    requireRecovery(
                        reference: lease.reference,
                        reason: .reservationReleaseFailed
                    )
                }

            case let .signingMayHaveStarted(lease),
                 let .locallySigned(lease, _):
                requireRecovery(
                    reference: lease.reference,
                    reason: .cancellationAfterSigningMayHaveStarted
                )

            case .unreserved, .reservationInFlight, .committed, .released:
                break
            }
        }

        private func commitCompleteTransaction() async {
            guard case let .locallySigned(lease, _) = reservationLifecycle else {
                await failAndStop(.missingReservation)
                return
            }
            let completeTransaction: OpalFusion.Host.MosaicCompleteTransaction
            do {
                completeTransaction = try await dependencies
                    .loadValidatedCompleteTransaction(
                        .init(context: context),
                        lease
                    )
            } catch {
                pendingFailure = .completeTransactionUnavailable
                requireRecovery(
                    reference: lease.reference,
                    reason: .completeTransactionUnavailable
                )
                return
            }
            do {
                try await dependencies.transactionHost
                    .commitMosaicReservation(
                        lease.reference,
                        completeTransaction: completeTransaction
                    )
                reservationLifecycle = .committed(lease.reference)
            } catch {
                pendingFailure = .completeTransactionCommitFailed
                requireRecovery(
                    reference: lease.reference,
                    reason: .completeTransactionCommitFailed
                )
            }
        }

        private func failAndStop(_ failure: Failure) async {
            pendingFailure = pendingFailure ?? failure
            await stopDriverAfterFailure(failure)
        }

        private func stopDriverAfterFailure(_ failure: Failure) async {
            guard state == .running || state == .stopping else {
                return
            }
            pendingFailure = pendingFailure ?? failure
            state = .stopping
            await driver.stop()
        }

        private func requireRecovery(
            reference: OpalFusion.Host.MosaicReservationReference,
            reason: Recovery.Reason
        ) {
            pendingRecovery = pendingRecovery ?? .init(
                reservationReference: reference,
                reason: reason
            )
        }

        private func finishAfterDrain() {
            if let pendingRecovery {
                state = .recoveryRequired(pendingRecovery)
                return
            }
            if let pendingFailure {
                state = .terminal(.failed(pendingFailure))
                return
            }
            guard let pendingAttemptOutcome else {
                state = .terminal(.failed(.driverEndedWithoutOutcome))
                return
            }

            switch pendingAttemptOutcome {
            case .completed:
                guard case .committed = reservationLifecycle else {
                    if let reference = reservationReference {
                        state = .recoveryRequired(
                            .init(
                                reservationReference: reference,
                                reason: .reservationDispositionMissing
                            )
                        )
                    } else {
                        state = .terminal(
                            .failed(.completedWithoutCommittedReservation)
                        )
                    }
                    return
                }
                state = .terminal(.completed)

            case let .failed(failure):
                if let reference = undisposedReservationReference {
                    state = .recoveryRequired(
                        .init(
                            reservationReference: reference,
                            reason: .reservationDispositionMissing
                        )
                    )
                } else {
                    state = .terminal(.failed(.runtime(failure)))
                }

            case let .cancelled(cancellation):
                if let reference = undisposedReservationReference {
                    state = .recoveryRequired(
                        .init(
                            reservationReference: reference,
                            reason: .reservationDispositionMissing
                        )
                    )
                } else {
                    state = .terminal(
                        .cancelled(
                            cancellation,
                            inputSource: inputSourceTermination
                        )
                    )
                }
            }
        }

        private var reservationReference: OpalFusion.Host.MosaicReservationReference? {
            switch reservationLifecycle {
            case let .reserved(lease),
                 let .signingMayHaveStarted(lease),
                 let .locallySigned(lease, _):
                lease.reference
            case let .committed(reference), let .released(reference):
                reference
            case .unreserved, .reservationInFlight:
                nil
            }
        }

        private var undisposedReservationReference:
            OpalFusion.Host.MosaicReservationReference? {
            switch reservationLifecycle {
            case let .reserved(lease),
                 let .signingMayHaveStarted(lease),
                 let .locallySigned(lease, _):
                lease.reference
            case .unreserved, .reservationInFlight, .committed, .released:
                nil
            }
        }

        private var shouldStopBeforeSigning: Bool {
            cancellationRequested
                || dispositionGate.isReleaseRequested
                || pendingFailure != nil
        }
    }
}

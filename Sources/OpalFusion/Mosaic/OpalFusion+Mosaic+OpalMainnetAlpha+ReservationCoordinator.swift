// OpalFusion+Mosaic+OpalMainnetAlpha+ReservationCoordinator.swift

extension OpalFusion.Mosaic.OpalMainnetAlpha {
    /// Binds one actual contributor lease to the sealed publication accepted by a mainnet-alpha session.
    ///
    /// This coordinator owns only the reservation boundary. Material construction, control transport,
    /// transcript inclusion, BCH signing, commit, recovery persistence, and broadcast remain external.
    actor ReservationCoordinator {
        private let context: RuntimeSession.Context
        private let dependencies: Dependencies
        private let effectStream: AsyncStream<RuntimeSession.Effect>
        private let effectContinuation: AsyncStream<RuntimeSession.Effect>.Continuation
        private let dispositionGate: MosaicRuntimeCoordinatorDispositionGate

        private var runtimeSession: RuntimeSession
        private var effectConsumerTask: Task<Void, Never>?
        private var admittedManifest: RoundManifest?
        private var pendingFailure: Failure?

        private(set) var state: State = .idle
        private(set) var reservationLifecycle: ReservationLifecycle = .unreserved

        var runtimeSessionState: RuntimeSession.State {
            runtimeSession.state
        }

        init(
            runtimeSession: RuntimeSession,
            dependencies: Dependencies
        ) throws(InitializationError) {
            let context = runtimeSession.context
            guard runtimeSession.state == .active(.manifestAgreement) else {
                throw .runtimeSessionNotFresh
            }
            guard context.localRole == .contributor else {
                throw .localPeerIsNotContributor
            }
            let (effectStream, effectContinuation) = AsyncStream<
                RuntimeSession.Effect
            >.makeStream()
            self.context = context
            self.dependencies = dependencies
            self.runtimeSession = runtimeSession
            self.effectStream = effectStream
            self.effectContinuation = effectContinuation
            dispositionGate = MosaicRuntimeCoordinatorDispositionGate()
        }

        /// Starts the ordered reservation-effect consumer once.
        func start() {
            guard state == .idle else {
                return
            }
            state = .running
            effectConsumerTask = Task { [weak self] in
                await self?.consumeEffects()
            }
        }

        /// Submits one already-authenticated runtime input.
        ///
        /// Reservation-publication validation is accepted only from the coordinator's exact
        /// host-lease path and cannot be injected through this method.
        @discardableResult
        func submit(_ input: RuntimeSession.Input) -> Bool {
            guard state == .running else {
                return false
            }
            guard case .reservationPublicationValidated = input else {
                applyAndEnqueue(input)
                return true
            }
            return false
        }

        /// Requests cancellation without cancelling an in-flight host reservation or publication.
        func stop() {
            guard state == .running else {
                return
            }
            state = .stopping
            applyAndEnqueue(.cancel)
        }

        /// Waits until the paired runtime has terminated and reservation disposition has drained.
        func waitForTermination() async {
            let effectConsumerTask = effectConsumerTask
            await effectConsumerTask?.value
        }

        private func applyAndEnqueue(_ input: RuntimeSession.Input) {
            enqueue(runtimeSession.apply(input: input))
        }

        private func enqueue(_ effects: [RuntimeSession.Effect]) {
            for effect in effects {
                if case .localAttempt(
                    .walletReservationReleaseRequired
                ) = effect {
                    dispositionGate.requestRelease()
                }
                dependencies.runtimeEffectObserver(effect)
                effectContinuation.yield(effect)
            }
        }

        private func consumeEffects() async {
            for await effect in effectStream {
                await handle(effect)
            }
        }

        private func handle(_ effect: RuntimeSession.Effect) async {
            switch effect {
            case let .admission(.manifestAdmitted(manifest)):
                admittedManifest = manifest

            case let .localAttempt(localEffect):
                await handle(localEffect)

            case let .reservationPublicationAccepted(reference):
                guard case let .reserved(lease) = reservationLifecycle,
                      lease.reference == reference else {
                    failAndStop(.reservationPublicationLeaseMismatch)
                    return
                }

            case let .sessionTerminated(outcome):
                await finish(with: outcome)

            case .admission, .exactDuplicateIgnored, .inputRejected:
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

            case .transcriptInclusionValidationRequired,
                 .preSignAcknowledgementRequired,
                 .attemptTerminated,
                 .inputRejected:
                break

            case .bchSigningEligible,
                 .walletReservationCommitRequired:
                failAndStop(.effectContextMismatch)
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
                lease = try await dependencies.transactionHost
                    .reserveMosaicContribution(for: request)
            } catch {
                reservationLifecycle = .unreserved
                failAndStop(.reservationFailed)
                return
            }
            reservationLifecycle = .reserved(lease)

            guard !dispositionGate.isReleaseRequested else {
                await releaseIfNeeded()
                return
            }
            guard dispositionGate.claimReservationPublication() else {
                await releaseIfNeeded()
                return
            }

            let validation: RuntimeSession.ReservationPublicationValidation
            do {
                validation = try await dependencies
                    .validateAndPublishReservedContribution(
                        eligibility,
                        lease
                    )
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
            guard validation.request.reservationReference == lease.reference else {
                failAndStop(.reservationPublicationLeaseMismatch)
                return
            }
            applyAndEnqueue(.reservationPublicationValidated(validation))
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
            guard case let .reserved(lease) = reservationLifecycle else {
                return
            }
            do {
                try await dependencies.transactionHost
                    .releaseMosaicReservation(lease.reference)
                reservationLifecycle = .released(lease.reference)
            } catch {
                reservationLifecycle = .releaseFailed(lease.reference)
            }
        }

        private func failAndStop(_ failure: Failure) {
            pendingFailure = pendingFailure ?? failure
            guard state == .running else {
                return
            }
            state = .stopping
            applyAndEnqueue(.cancel)
        }

        private func finish(with outcome: RuntimeSession.Outcome) async {
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
            } else if let pendingFailure {
                state = .terminal(.failed(pendingFailure))
            } else {
                switch outcome {
                case let .failed(failure):
                    state = .terminal(.failed(.runtime(failure)))
                case let .cancelled(during: phase):
                    state = .terminal(.cancelled(during: phase))
                }
            }
            effectContinuation.finish()
        }
    }
}

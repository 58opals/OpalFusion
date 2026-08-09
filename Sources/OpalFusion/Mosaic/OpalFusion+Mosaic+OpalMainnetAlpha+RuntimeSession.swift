// OpalFusion+Mosaic+OpalMainnetAlpha+RuntimeSession.swift

extension OpalFusion.Mosaic.OpalMainnetAlpha {
    /// Owns one paired admission ledger and local attempt through transcript agreement.
    ///
    /// This reducer translates only typed documents admitted by `AdmissionLedger`. A contributor's
    /// wallet-reservation phase cannot advance until an external material owner seals the exact
    /// reservation reference and published `PlayerCommit` to this attempt, generation, and material
    /// identity. The bridge deliberately does not admit the acknowledgement set into BCH signing;
    /// the mainnet-alpha runtime driver remains disabled.
    struct RuntimeSession: Sendable {
        private struct LocalAttemptPhaseTransitionValidator:
            AdmissionLedger.PhaseTransitionValidating
        {
            enum Rejection: Error {
                case stateMismatch
                case transcriptMismatch
            }

            let attemptIdentifier: AttemptIdentifier
            let generationIdentifier: GenerationIdentifier
            let observedContext: AdmissionLedger.PhaseContext

            func validatePhaseTransition(
                _ request: AdmissionLedger.PhaseTransitionRequest
            ) throws {
                guard request.attemptIdentifier == attemptIdentifier,
                      request.generationIdentifier == generationIdentifier else {
                    throw Rejection.stateMismatch
                }
                switch (request.to, observedContext) {
                case let (
                    .transcriptAgreement(expected),
                    .transcriptAgreement(observed)
                ):
                    guard expected == observed else {
                        throw Rejection.transcriptMismatch
                    }
                default:
                    guard request.to == observedContext else {
                        throw Rejection.stateMismatch
                    }
                }
            }
        }

        private let attemptIdentifier: AttemptIdentifier
        private let generationIdentifier: GenerationIdentifier
        private let materialIdentifier: MaterialIdentifier
        private let localControlIdentity: ControlIdentity
        private let localRole: OpalFusion.Mosaic.Role
        private let roster: OpalFusion.Mosaic.Attempt.Roster

        private var localAttempt: OpalFusion.Mosaic.LocalAttempt
        private var admissionLedger: AdmissionLedger
        private var admittedManifest: RoundManifest?
        private var admittedLocalPlayerCommit: PlayerCommit?
        private var admittedCommitmentSet: OpalFusion.Mosaic.OpalV0.CommitmentSet?
        private var admittedTranscript: AdmissionLedger.Transcript?
        private var reservationPublication: ReservationPublicationValidation?

        private(set) var state: State = .active(.manifestAgreement)

        var localAttemptState: OpalFusion.Mosaic.Attempt.State {
            localAttempt.state
        }

        var admissionLedgerState: AdmissionLedger.State {
            admissionLedger.state
        }

        init(
            validatedAttempt: OpalFusion.Mosaic.Attempt,
            attemptIdentifier: AttemptIdentifier,
            generationIdentifier: GenerationIdentifier,
            materialIdentifier: MaterialIdentifier,
            localControlIdentity: ControlIdentity,
            proposalValidation: ManifestProposalValidation
        ) throws(InitializationError) {
            guard validatedAttempt.configuration.profile == .opalMainnetAlpha else {
                throw .unsupportedProfile(validatedAttempt.configuration.profile)
            }
            guard case let .manifestAgreement(roleElection) = validatedAttempt.state else {
                throw .attemptNotReady
            }
            guard proposalValidation.context.roleElection == roleElection,
                  proposalValidation.core.roster == roleElection.roster else {
                throw .proposalValidationMismatch
            }

            let localAttempt: OpalFusion.Mosaic.LocalAttempt
            do {
                localAttempt = try .init(
                    validatedAttempt: validatedAttempt,
                    attemptIdentifier: attemptIdentifier,
                    generationIdentifier: generationIdentifier,
                    materialIdentifier: materialIdentifier,
                    localControlIdentity: localControlIdentity
                )
            } catch {
                throw .localAttemptBindingFailed
            }
            let admissionLedger: AdmissionLedger
            do {
                admissionLedger = try .init(
                    attemptIdentifier: attemptIdentifier,
                    generationIdentifier: generationIdentifier,
                    localControlIdentity: localControlIdentity,
                    proposalValidation: proposalValidation
                )
            } catch {
                throw .admissionLedgerBindingFailed
            }

            self.attemptIdentifier = attemptIdentifier
            self.generationIdentifier = generationIdentifier
            self.materialIdentifier = materialIdentifier
            self.localControlIdentity = localControlIdentity
            self.localRole = localAttempt.localRole
            self.roster = roleElection.roster
            self.localAttempt = localAttempt
            self.admissionLedger = admissionLedger
        }

        mutating func apply(input: Input) -> [Effect] {
            guard case .active = state else {
                return [.inputRejected(.inputAfterTermination)]
            }

            switch input {
            case let .control(delivery):
                return receiveAdmissionEffects(
                    admissionLedger.apply(input: .control(delivery))
                )
            case let .authorizationResponseSetValidated(delivery):
                return receiveAdmissionEffects(
                    admissionLedger.apply(
                        input: .authorizationResponseSetValidated(delivery)
                    )
                )
            case let .reservationPublicationValidated(validation):
                return receiveReservationPublication(validation)
            case let .transcriptInclusionValidated(validation):
                return receiveTranscriptInclusion(validation)
            case .cancel:
                return cancel()
            case .retryRequested:
                return rejectInPlaceRetry()
            }
        }

        mutating func receiveAnonymousComponent<Validator>(
            _ delivery: AdmissionLedger.AnonymousComponentDelivery,
            using validator: Validator
        ) -> [Effect]
        where Validator: AnonymousComponentAdmissionValidating {
            guard case .active = state else {
                return [.inputRejected(.inputAfterTermination)]
            }
            return receiveAdmissionEffects(
                admissionLedger.receiveAnonymousComponent(
                    delivery,
                    using: validator
                )
            )
        }

        private mutating func receiveReservationPublication(
            _ validation: ReservationPublicationValidation
        ) -> [Effect] {
            if let reservationPublication {
                guard reservationPublication == validation else {
                    return terminate(with: .reservationPublicationMismatch)
                }
                return [.exactDuplicateIgnored]
            }
            guard localRole == .contributor,
                  case .active(.walletReservation) = state,
                  let admittedManifest else {
                return terminate(with: .reservationPublicationUnavailable)
            }
            let request = validation.request
            guard request.attemptIdentifier == attemptIdentifier,
                  request.generationIdentifier == generationIdentifier,
                  request.materialIdentifier == materialIdentifier,
                  request.contributor == localControlIdentity,
                  request.manifest == admittedManifest,
                  request.playerCommit.contributor == localControlIdentity,
                  request.playerCommit.roundIdentifier
                    == admittedManifest.core.roundIdentifier else {
                return terminate(with: .reservationPublicationMismatch)
            }
            if let admittedLocalPlayerCommit,
               admittedLocalPlayerCommit != request.playerCommit {
                return terminate(with: .reservationPublicationMismatch)
            }

            reservationPublication = validation
            var effects: [Effect] = [
                .reservationPublicationAccepted(request.reservationReference)
            ]
            effects.append(contentsOf: advanceIfReady())
            return effects
        }

        private mutating func receiveTranscriptInclusion(
            _ validation: OpalFusion.Mosaic.LocalAttempt
                .TranscriptInclusionValidation
        ) -> [Effect] {
            let localEffects = localAttempt.apply(
                input: .init(
                    attemptIdentifier: attemptIdentifier,
                    generationIdentifier: generationIdentifier,
                    validatedTranscriptInclusion: validation
                )
            )
            var effects = localEffects.map(Effect.localAttempt)
            if let failure = localAttemptTerminalFailure {
                terminateAdmissionLedgerForBridgeMismatch()
                let outcome = Outcome.failed(.localAttempt(failure))
                state = .terminal(outcome)
                effects.append(.sessionTerminated(outcome))
            }
            return effects
        }

        private mutating func receiveAdmissionEffects(
            _ admissionEffects: [AdmissionLedger.Effect]
        ) -> [Effect] {
            var effects: [Effect] = []
            for admissionEffect in admissionEffects {
                if case let .attemptTerminated(outcome) = admissionEffect {
                    effects.append(contentsOf: terminate(from: outcome))
                    return effects
                }

                effects.append(.admission(admissionEffect))
                switch admissionEffect {
                case let .manifestAdmitted(manifest):
                    admittedManifest = manifest
                case let .playerCommitAdmitted(playerCommit)
                    where playerCommit.contributor == localControlIdentity:
                    admittedLocalPlayerCommit = playerCommit
                    if let reservationPublication,
                       reservationPublication.request.playerCommit
                        != playerCommit {
                        effects.append(
                            contentsOf: terminate(
                                with: .reservationPublicationMismatch
                            )
                        )
                        return effects
                    }
                case .playerCommitAdmitted:
                    break
                case let .commitmentSetAdmitted(commitmentSet):
                    admittedCommitmentSet = commitmentSet
                case let .componentSetAdmitted(_, transcript):
                    admittedTranscript = transcript
                case .aggregateReservationAccepted,
                     .aggregateFragmentAccepted,
                     .exactDuplicateIgnored,
                     .playerCommitUnanimityReached,
                     .authorizationResponseSetAdmitted,
                     .authorizationResponseSetValidationRequired,
                     .authorizationResponsesValidated,
                     .anonymousComponentAdmitted,
                     .preSignAcknowledgementAdmitted,
                     .preSignAcknowledgementCollectionComplete,
                     .preSignAcknowledgementSetAdmitted,
                     .phaseAdvanced,
                     .inputRejected,
                     .attemptTerminated:
                    break
                }
            }
            effects.append(contentsOf: advanceIfReady())
            return effects
        }

        private mutating func advanceIfReady() -> [Effect] {
            guard case let .active(phase) = state else {
                return []
            }

            switch phase {
            case .manifestAgreement:
                guard let manifest = admittedManifest else {
                    return []
                }
                let validations: [OpalFusion.Mosaic.Attempt
                    .ManifestSignatureValidation]
                do {
                    validations = try manifest.signatures.map {
                        try .init(validating: $0, for: manifest.binding)
                    }
                } catch {
                    return terminate(with: .phaseSynchronizationFailed)
                }
                return advance(
                    to: .walletReservation,
                    using: .manifestSignaturesValidated(validations)
                )

            case .walletReservation:
                if localRole == .contributor {
                    guard let admittedLocalPlayerCommit,
                          let reservationPublication,
                          reservationPublication.request.playerCommit
                            == admittedLocalPlayerCommit else {
                        return []
                    }
                }
                return advance(
                    to: .groupedCommitment,
                    using: .walletReservationsPrepared(
                        contributors: roster.contributors
                    )
                )

            case .groupedCommitment:
                guard let admittedCommitmentSet else {
                    return []
                }
                if localRole == .contributor {
                    guard let admittedLocalPlayerCommit,
                          admittedLocalPlayerCommit.groupedCommitment
                            .commitments.allSatisfy(
                                admittedCommitmentSet.commitments.contains
                            ) else {
                        return terminate(
                            with: .localCommitmentSetMismatch
                        )
                    }
                }
                return advance(
                    to: .anonymousComponentSubmission,
                    using: .groupedCommitmentSetReceived(
                        admittedCommitmentSet
                    )
                )

            case .anonymousComponentSubmission:
                guard let admittedTranscript else {
                    return []
                }
                return advance(
                    to: .transcriptAgreement(admittedTranscript),
                    using: .anonymousComponentSetReceived(
                        admittedTranscript.componentSet
                    )
                )

            case .transcriptAgreement, .bchSigning,
                 .discovery, .candidateSetAgreement,
                 .controlRosterAgreement, .roleSelection:
                return []
            }
        }

        private mutating func advance(
            to nextContext: AdmissionLedger.PhaseContext,
            using attemptInput: OpalFusion.Mosaic.Attempt.Input
        ) -> [Effect] {
            guard let request = admissionLedger.phaseTransitionRequestIfReady(
                to: nextContext
            ) else {
                return []
            }

            let localEffects = localAttempt.apply(
                input: .init(
                    attemptIdentifier: attemptIdentifier,
                    generationIdentifier: generationIdentifier,
                    attemptInput: attemptInput
                )
            )
            var effects = localEffects.map(Effect.localAttempt)
            if let failure = localAttemptTerminalFailure {
                terminateAdmissionLedgerForBridgeMismatch()
                let outcome = Outcome.failed(.localAttempt(failure))
                state = .terminal(outcome)
                effects.append(.sessionTerminated(outcome))
                return effects
            }
            guard let observedContext = localAttemptPhaseContext else {
                effects.append(
                    contentsOf: terminate(with: .phaseSynchronizationFailed)
                )
                return effects
            }

            let validation: AdmissionLedger.PhaseTransitionValidation
            do {
                validation = try .init(
                    validating: request,
                    using: LocalAttemptPhaseTransitionValidator(
                        attemptIdentifier: attemptIdentifier,
                        generationIdentifier: generationIdentifier,
                        observedContext: observedContext
                    )
                )
            } catch LocalAttemptPhaseTransitionValidator.Rejection
                .transcriptMismatch {
                effects.append(contentsOf: terminate(with: .transcriptMismatch))
                return effects
            } catch {
                effects.append(
                    contentsOf: terminate(with: .phaseSynchronizationFailed)
                )
                return effects
            }
            let synchronizationEffects = admissionLedger.synchronize(
                using: validation
            )
            guard synchronizationEffects == [.phaseAdvanced(nextContext)] else {
                effects.append(
                    contentsOf: terminate(with: .phaseSynchronizationFailed)
                )
                return effects
            }
            effects.append(
                contentsOf: synchronizationEffects.map {
                    Effect.admission($0)
                }
            )
            state = .active(nextContext.phase)
            return effects
        }

        private var localAttemptPhaseContext:
            AdmissionLedger.PhaseContext? {
            switch localAttempt.state {
            case .manifestAgreement:
                return .manifestAgreement
            case .walletReservation:
                return .walletReservation
            case .groupedCommitment:
                return .groupedCommitment
            case .anonymousComponentSubmission:
                return .anonymousComponentSubmission
            case let .transcriptAgreement(_, transcript):
                return .transcriptAgreement(transcript)
            case let .bchSigning(_, transcript):
                return .bchSigning(transcript)
            case .discovery, .candidateSetAgreement,
                 .controlRosterAgreement, .roleSelection,
                 .terminal:
                return nil
            }
        }

        private mutating func cancel() -> [Effect] {
            guard case let .active(phase) = state else {
                return [.inputRejected(.inputAfterTermination)]
            }
            let localEffects = localAttempt.apply(
                input: .init(
                    attemptIdentifier: attemptIdentifier,
                    generationIdentifier: generationIdentifier,
                    attemptInput: .cancel
                )
            )
            _ = admissionLedger.apply(input: .cancel)
            let outcome = Outcome.cancelled(during: phase)
            state = .terminal(outcome)
            return localEffects.map(Effect.localAttempt)
                + [.sessionTerminated(outcome)]
        }

        private mutating func rejectInPlaceRetry() -> [Effect] {
            let localEffects = localAttempt.apply(
                input: .init(
                    attemptIdentifier: attemptIdentifier,
                    generationIdentifier: generationIdentifier,
                    attemptInput: .retryRequested
                )
            )
            _ = admissionLedger.apply(input: .retryRequested)
            let outcome = Outcome.failed(.inPlaceRetryNotPermitted)
            state = .terminal(outcome)
            return localEffects.map(Effect.localAttempt)
                + [.sessionTerminated(outcome)]
        }

        private mutating func terminate(
            from admissionOutcome: AdmissionLedger.Outcome
        ) -> [Effect] {
            switch admissionOutcome {
            case let .failed(failure):
                return terminate(with: .admission(failure))
            case let .cancelled(during: phase):
                let localEffects = localAttempt.apply(
                    input: .init(
                        attemptIdentifier: attemptIdentifier,
                        generationIdentifier: generationIdentifier,
                        attemptInput: .cancel
                    )
                )
                let outcome = Outcome.cancelled(during: phase)
                state = .terminal(outcome)
                return localEffects.map(Effect.localAttempt)
                    + [.sessionTerminated(outcome)]
            }
        }

        private mutating func terminate(with failure: Failure) -> [Effect] {
            guard case .active = state else {
                return [.inputRejected(.inputAfterTermination)]
            }
            let admissionWasActive: Bool
            if case .active = admissionLedger.state {
                admissionWasActive = true
            } else {
                admissionWasActive = false
            }
            if admissionWasActive {
                terminateAdmissionLedgerForBridgeMismatch()
            }

            var effects: [Effect] = []
            if case .terminal = localAttempt.state {
                // The local reducer already emitted its ordered disposition and terminal effects.
            } else {
                effects = localAttempt.apply(
                    input: .init(
                        attemptIdentifier: attemptIdentifier,
                        generationIdentifier: generationIdentifier,
                        attemptInput: .abort(.invalidAuthenticatedMessage)
                    )
                ).map(Effect.localAttempt)
            }
            let outcome = Outcome.failed(failure)
            state = .terminal(outcome)
            effects.append(.sessionTerminated(outcome))
            return effects
        }

        private mutating func terminateAdmissionLedgerForBridgeMismatch() {
            _ = admissionLedger.terminateForRuntimeSessionBridgeMismatch()
        }

        private var localAttemptTerminalFailure:
            OpalFusion.Mosaic.Attempt.Failure? {
            guard case let .terminal(.failed(failure)) = localAttempt.state else {
                return nil
            }
            return failure
        }
    }
}

// OpalFusion+Mosaic+RuntimeSession.swift

extension OpalFusion.Mosaic {
    /// Routes already-authenticated post-admission facts into one local attempt.
    ///
    /// Transport and wire adapters remain responsible for canonical decoding,
    /// outer-event signature verification, expiry, network, protocol, and round validation.
    /// This value owns embedded manifest and transcript signature verification,
    /// attempt/generation binding, sender membership, replay, sequence, phase, and terminal
    /// discipline.
    struct RuntimeSession: Sendable {
        private var localAttempt: LocalAttempt
        private var replayIndex = AuthenticatedReplayIndex()
        private let roster: Attempt.Roster

        var state: Attempt.State {
            localAttempt.state
        }

        var configuration: OpalFusion.Mosaic.Configuration {
            localAttempt.configuration
        }

        var attemptIdentifier: LocalAttempt.AttemptIdentifier {
            localAttempt.attemptIdentifier
        }

        var generationIdentifier: LocalAttempt.GenerationIdentifier {
            localAttempt.generationIdentifier
        }

        var materialIdentifier: LocalAttempt.MaterialIdentifier {
            localAttempt.materialIdentifier
        }

        var localControlIdentity: Attempt.ControlIdentity {
            localAttempt.localControlIdentity
        }

        var localRole: OpalFusion.Mosaic.Role {
            localAttempt.localRole
        }

        init(localAttempt: LocalAttempt) throws {
            guard case let .manifestAgreement(roleElection) = localAttempt.state else {
                throw Failure.attemptNotReady
            }
            self.localAttempt = localAttempt
            self.roster = roleElection.roster
        }

        mutating func apply(input: Input) -> [Effect] {
            switch input {
            case let .local(operation):
                let localInput: LocalAttempt.Input
                switch operation {
                case .cancel:
                    localInput = .init(
                        attemptIdentifier: localAttempt.attemptIdentifier,
                        generationIdentifier: localAttempt.generationIdentifier,
                        attemptInput: .cancel
                    )
                case .retryRequested:
                    localInput = .init(
                        attemptIdentifier: localAttempt.attemptIdentifier,
                        generationIdentifier: localAttempt.generationIdentifier,
                        attemptInput: .retryRequested
                    )
                case let .transcriptInclusionValidated(validation):
                    localInput = .init(
                        attemptIdentifier: localAttempt.attemptIdentifier,
                        generationIdentifier: localAttempt.generationIdentifier,
                        validatedTranscriptInclusion: validation
                    )
                }
                return localize(localAttempt.apply(input: localInput))

            case let .hostResult(result):
                guard configuration.profile == .opalV0 else {
                    let failure = Failure.unsupportedLegacyHostResultProfile(
                        configuration.profile
                    )
                    var effects: [Effect] = [.hostResultRejected(failure)]
                    effects.append(
                        contentsOf: localize(
                            localAttempt.apply(
                                input: .init(
                                    attemptIdentifier:
                                        localAttempt.attemptIdentifier,
                                    generationIdentifier:
                                        localAttempt.generationIdentifier,
                                    attemptInput: .abort(
                                        .invalidAuthenticatedMessage
                                    )
                                )
                            )
                        )
                    )
                    return effects
                }
                return localize(localAttempt.apply(input: result.localInput))

            case let .authenticated(message):
                return receive(message)
            }
        }

        private mutating func receive(
            _ message: AuthenticatedMessage
        ) -> [Effect] {
            guard message.attemptIdentifier == localAttempt.attemptIdentifier else {
                return [
                    .authenticatedInputRejected(
                        .attemptIdentifierMismatch
                    )
                ]
            }
            guard message.generationIdentifier == localAttempt.generationIdentifier else {
                return [
                    .authenticatedInputRejected(
                        .generationIdentifierMismatch
                    )
                ]
            }
            guard roster.controlIdentities.contains(message.sender) else {
                return [.authenticatedInputRejected(.senderNotInRoster)]
            }
            if case .terminal = localAttempt.state {
                if replayIndex.containsExactDuplicate(message) {
                    return [.exactDuplicateIgnored]
                }
                return localize(
                    localAttempt.apply(
                        input: message.terminalRejectionInput()
                    )
                )
            }

            switch replayIndex.record(
                message,
                profile: localAttempt.configuration.profile
            ) {
            case .accepted:
                break
            case .duplicate:
                return [.exactDuplicateIgnored]
            case let .gap(expectedSequence, receivedSequence):
                return terminateAuthenticatedViolation(
                    failure: .sequenceGap(
                        expected: expectedSequence,
                        received: receivedSequence
                    ),
                    reason: .invalidAuthenticatedMessage
                )
            case let .stale(greatestAcceptedSequence):
                return [
                    .authenticatedInputRejected(
                        .staleSequence(
                            greatestAccepted: greatestAcceptedSequence,
                            received: message.sequence
                        )
                    )
                ]
            case .conflict:
                return terminateAuthenticatedViolation(
                    failure: .sequenceConflict,
                    reason: .equivocation
                )
            }

            guard message.phase == localAttempt.state.phase else {
                return terminateAuthenticatedViolation(
                    failure: .phaseMismatch,
                    reason: .invalidAuthenticatedMessage
                )
            }

            if case .transcriptAcknowledgementSet = message.authenticatedFact,
               message.sender != roster.conductor {
                return terminateAuthenticatedViolation(
                    failure: .transcriptAcknowledgementPublisherIsNotConductor,
                    reason: .invalidAuthenticatedMessage
                )
            }
            switch message.authenticatedFact {
            case .groupedCommitmentSet,
                 .anonymousComponentSet:
                guard message.sender == roster.conductor else {
                    return terminateAuthenticatedViolation(
                        failure: .aggregateSetPublisherIsNotConductor(
                            during: message.phase
                        ),
                        reason: .invalidAuthenticatedMessage
                    )
                }
            case .manifestSignatureSet, .transcriptAcknowledgementSet, .abort:
                break
            }

            do {
                return localize(
                    localAttempt.apply(
                        input: try message.localInput(
                            expectedManifestSignatureCount:
                                roster.candidateCount,
                            expectedTranscriptAcknowledgementCount:
                                roster.contributors.count,
                            transcriptAcknowledgementProfile:
                                localAttempt.configuration.profile
                        )
                    )
                )
            } catch {
                return terminateAuthenticatedViolation(
                    failure: error,
                    reason: .invalidAuthenticatedMessage
                )
            }
        }

        private mutating func terminateAuthenticatedViolation(
            failure: Failure,
            reason: Attempt.AbortReason
        ) -> [Effect] {
            var effects: [Effect] = [.authenticatedInputRejected(failure)]
            effects.append(
                contentsOf: localize(
                    localAttempt.apply(
                        input: .init(
                            attemptIdentifier: localAttempt.attemptIdentifier,
                            generationIdentifier: localAttempt.generationIdentifier,
                            attemptInput: .abort(reason)
                        )
                    )
                )
            )
            return effects
        }

        private func localize(_ effects: [LocalAttempt.Effect]) -> [Effect] {
            effects.map(Effect.localAttempt)
        }
    }
}

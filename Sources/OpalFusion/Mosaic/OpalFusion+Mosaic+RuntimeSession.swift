// OpalFusion+Mosaic+RuntimeSession.swift

extension OpalFusion.Mosaic {
    /// Routes already-authenticated post-admission facts into one local attempt.
    ///
    /// Transport and wire adapters remain responsible for canonical decoding,
    /// outer-event signature verification, expiry, network, protocol, and round validation.
    /// This value owns embedded manifest-signature verification, attempt/generation binding,
    /// sender membership, replay, sequence, phase, and terminal discipline.
    struct RuntimeSession: Sendable {
        private var localAttempt: LocalAttempt
        private var replayIndex = AuthenticatedReplayIndex()
        private let roster: Attempt.Roster

        var state: Attempt.State {
            localAttempt.state
        }

        init(localAttempt: LocalAttempt) throws {
            guard case let .manifestAgreement(roster) = localAttempt.state else {
                throw Failure.attemptNotReady
            }
            self.localAttempt = localAttempt
            self.roster = roster
        }

        mutating func apply(input: Input) -> [Effect] {
            switch input {
            case let .local(operation):
                return localize(
                    localAttempt.apply(
                        input: .init(
                            attemptIdentifier: localAttempt.attemptIdentifier,
                            generationIdentifier: localAttempt.generationIdentifier,
                            validatedFact: operation.attemptInput
                        )
                    )
                )

            case let .hostResult(result):
                return localize(
                    localAttempt.apply(
                        input: .init(
                            attemptIdentifier: localAttempt.attemptIdentifier,
                            generationIdentifier: localAttempt.generationIdentifier,
                            validatedFact: result.attemptInput
                        )
                    )
                )

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

            switch replayIndex.record(message) {
            case .accepted:
                break
            case .duplicate:
                return [.exactDuplicateIgnored]
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

            do {
                return localize(
                    localAttempt.apply(
                        input: try message.validatedLocalInput(
                            expectedManifestSignatureCount:
                                roster.candidateCount
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
                            validatedFact: .abort(reason)
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

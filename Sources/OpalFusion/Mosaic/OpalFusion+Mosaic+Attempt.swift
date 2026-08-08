// OpalFusion+Mosaic+Attempt.swift

extension OpalFusion.Mosaic {
    /// A deterministic, transport-independent reducer for one profile-bound Mosaic attempt.
    ///
    /// Construct a new value for every retry. Cryptographic, transport, clock, and host adapters
    /// must validate their own facts before converting them into an `Input`.
    struct Attempt: Sendable {
        let configuration: Configuration
        private(set) var state: State

        init(configuration: Configuration) {
            self.configuration = configuration
            self.state = .discovery
        }

        mutating func apply(input: Input) -> [Effect] {
            if case .terminal = state {
                return [.inputRejected(.inputAfterTermination)]
            }

            guard let phase = state.phase else {
                return [.inputRejected(.inputAfterTermination)]
            }

            switch input {
            case let .abort(reason):
                return terminate(
                    with: .failed(.aborted(during: phase, reason: reason))
                )
            case .cancel:
                return terminate(
                    with: .cancelled(.requested(during: phase))
                )
            case .retryRequested:
                return terminate(with: .failed(.inPlaceRetryNotPermitted))
            default:
                break
            }

            switch (state, input) {
            case let (.discovery, .discoveryCompleted(candidateCount)):
                let rosterPolicy = configuration.rosterPolicy
                guard (rosterPolicy.minimumCandidateCount
                    ... rosterPolicy.maximumCandidateCount).contains(candidateCount) else {
                    return terminate(
                        with: .failed(.invalidCandidateCount(actual: candidateCount))
                    )
                }
                state = .candidateSetAgreement(candidateCount: candidateCount)
                return []

            case let (
                .candidateSetAgreement(candidateCount),
                .candidateSetAgreementValidated
            ):
                state = .controlRosterAgreement(candidateCount: candidateCount)
                return []

            case let (
                .controlRosterAgreement(candidateCount),
                .controlRosterValidated(controlIdentities)
            ):
                guard controlIdentities.count == candidateCount else {
                    return terminate(
                        with: .failed(
                            .controlIdentityCountMismatch(
                                expected: candidateCount,
                                actual: controlIdentities.count
                            )
                        )
                    )
                }
                var uniqueControlIdentities: Set<ControlIdentity> = []
                for controlIdentity in controlIdentities {
                    guard uniqueControlIdentities.insert(controlIdentity).inserted else {
                        return terminate(
                            with: .failed(.duplicateControlIdentity(controlIdentity))
                        )
                    }
                }
                state = .roleSelection(controlIdentities: controlIdentities)
                return []

            case let (
                .roleSelection(controlIdentities),
                .rolesSelected(roster)
            ):
                guard roster.candidateCount == controlIdentities.count,
                      Set(roster.controlIdentities) == Set(controlIdentities) else {
                    return terminate(
                        with: .failed(.selectedRolesDoNotMatchControlRoster)
                    )
                }
                state = .manifestAgreement(roster: roster)
                return []

            case let (
                .manifestAgreement(roster),
                .manifestSignaturesValidated(validatedSignatures)
            ):
                let agreement: ManifestAgreement
                do {
                    agreement = try ManifestAgreement(
                        roster: roster,
                        validatedSignatures: validatedSignatures
                    )
                } catch let validationError as ManifestAgreement.ValidationError {
                    return terminate(
                        with: .failed(
                            .invalidManifestAgreement(validationError)
                        )
                    )
                } catch {
                    preconditionFailure(
                        "ManifestAgreement only throws its declared validation errors."
                    )
                }
                state = .walletReservation(
                    roster: roster,
                    manifest: agreement.binding
                )
                return [
                    .walletReservationEligible(
                        contributors: roster.contributors,
                        manifest: agreement.binding
                    )
                ]

            case let (
                .walletReservation(roster, manifest),
                .walletReservationsPrepared(contributors)
            ):
                if let failure = contributorSetFailure(
                    contributors,
                    roster: roster,
                    phase: .walletReservation
                ) {
                    return terminate(with: .failed(failure))
                }
                state = .groupedCommitment(roster: roster, manifest: manifest)
                return []

            case let (
                .groupedCommitment(roster, manifest),
                .groupedCommitmentsValidated(contributors)
            ):
                if let failure = contributorSetFailure(
                    contributors,
                    roster: roster,
                    phase: .groupedCommitment
                ) {
                    return terminate(with: .failed(failure))
                }
                state = .anonymousComponentSubmission(
                    roster: roster,
                    manifest: manifest
                )
                return []

            case let (
                .anonymousComponentSubmission(roster, manifest),
                .anonymousComponentsValidated(contributors)
            ):
                if let failure = contributorSetFailure(
                    contributors,
                    roster: roster,
                    phase: .anonymousComponentSubmission
                ) {
                    return terminate(with: .failed(failure))
                }
                state = .transcriptAgreement(roster: roster, manifest: manifest)
                return []

            case let (
                .transcriptAgreement(roster, manifest),
                .transcriptAgreementValidated(acknowledgements)
            ):
                let contributors = acknowledgements.map(\.contributor)
                if contributors.contains(roster.conductor) {
                    return terminate(
                        with: .failed(
                            .conductorUsedContributorInput(during: .transcriptAgreement)
                        )
                    )
                }
                guard identitiesExactlyMatch(
                    contributors,
                    expected: roster.contributors
                ) else {
                    return terminate(
                        with: .failed(.transcriptAgreementNotUnanimous)
                    )
                }
                guard acknowledgements.allSatisfy({
                    $0.profile == configuration.profile
                }) else {
                    return terminate(
                        with: .failed(.transcriptAcknowledgementProfileMismatch)
                    )
                }
                guard acknowledgements.allSatisfy({
                    $0.roundIdentifier == manifest.roundIdentifier
                }) else {
                    return terminate(
                        with: .failed(.transcriptRoundIdentifierMismatch)
                    )
                }
                guard let transcriptRoot = acknowledgements.first?.transcriptRoot,
                      acknowledgements.allSatisfy({ $0.transcriptRoot == transcriptRoot }) else {
                    return terminate(
                        with: .failed(.transcriptRootDisagreement)
                    )
                }
                state = .bchSigning(
                    roster: roster,
                    manifest: manifest,
                    transcriptRoot: transcriptRoot
                )
                return [
                    .bchSigningEligible(
                        contributors: roster.contributors,
                        transcriptRoot: transcriptRoot
                    )
                ]

            case let (
                .bchSigning(roster, _, _),
                .signedTransactionValidated(contributorSigners)
            ):
                if let failure = contributorSetFailure(
                    contributorSigners,
                    roster: roster,
                    phase: .bchSigning
                ) {
                    return terminate(with: .failed(failure))
                }
                return terminate(with: .completed)

            default:
                return terminate(
                    with: .failed(
                        .invalidTransition(from: phase, received: input.kind)
                    )
                )
            }
        }

        private func identitiesExactlyMatch(
            _ identities: [ControlIdentity],
            expected: [ControlIdentity]
        ) -> Bool {
            identities.count == expected.count
                && Set(identities).count == identities.count
                && Set(identities) == Set(expected)
        }

        private func contributorSetFailure(
            _ contributors: [ControlIdentity],
            roster: Roster,
            phase: Phase
        ) -> Failure? {
            if contributors.contains(roster.conductor) {
                return .conductorUsedContributorInput(during: phase)
            }
            guard identitiesExactlyMatch(
                contributors,
                expected: roster.contributors
            ) else {
                return .contributorSetMismatch(during: phase)
            }
            return nil
        }

        private mutating func terminate(with outcome: Outcome) -> [Effect] {
            var effects: [Effect] = []
            if outcome != .completed, let roster = state.reservationRoster {
                effects.append(
                    .walletReservationReleaseRequired(
                        contributors: roster.contributors
                    )
                )
            }
            state = .terminal(outcome)
            effects.append(.attemptTerminated(outcome))
            return effects
        }
    }
}

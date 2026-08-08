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
                .controlRosterValidated(controlRoster)
            ):
                guard controlRoster.candidateCount == candidateCount else {
                    return terminate(
                        with: .failed(
                            .controlIdentityCountMismatch(
                                expected: candidateCount,
                                actual: controlRoster.candidateCount
                            )
                        )
                    )
                }
                state = .roleSelection(.awaitingCommitments(controlRoster))
                return []

            case let (
                .roleSelection(.awaitingCommitments(controlRoster)),
                .roleCommitmentsReceived(commitments)
            ):
                let commitmentSet: RoleCommitmentSet
                do {
                    commitmentSet = try .init(
                        controlRoster: controlRoster,
                        commitments: commitments
                    )
                } catch {
                    return terminate(
                        with: .failed(.invalidRoleCommitmentSet(error))
                    )
                }
                state = .roleSelection(
                    .awaitingElectionValidation(commitmentSet)
                )
                return []

            case let (
                .roleSelection(.awaitingElectionValidation(commitmentSet)),
                .roleElectionValidated(validation)
            ):
                let roleElection: RoleElectionResult
                do {
                    roleElection = try .init(
                        profile: configuration.profile,
                        commitmentSet: commitmentSet,
                        validation: validation
                    )
                } catch {
                    return terminate(
                        with: .failed(
                            .invalidRoleElectionValidation(error)
                        )
                    )
                }
                state = .manifestAgreement(roleElection: roleElection)
                return []

            case let (
                .manifestAgreement(roleElection),
                .manifestSignaturesValidated(validatedSignatures)
            ):
                let roster = roleElection.roster
                let agreement: ManifestAgreement
                do {
                    agreement = try ManifestAgreement(
                        roster: roster,
                        validatedSignatures: validatedSignatures
                    )
                } catch {
                    return terminate(
                        with: .failed(
                            .invalidManifestAgreement(error)
                        )
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
                .groupedCommitmentSetReceived(commitmentSet)
            ):
                let validation: CommitmentSetValidation
                do {
                    validation = try .init(
                        profile: configuration.profile,
                        roster: roster,
                        commitmentSet: commitmentSet
                    )
                } catch {
                    return terminate(with: .failed(.invalidCommitmentSet(error)))
                }
                state = .anonymousComponentSubmission(
                    roster: roster,
                    manifest: manifest,
                    commitmentSet: validation
                )
                return []

            case let (
                .anonymousComponentSubmission(roster, manifest, commitmentSet),
                .anonymousComponentSetReceived(componentSet)
            ):
                let transcript: OpalFusion.Mosaic.OpalV0.UnsignedTransactionTranscript
                do {
                    transcript = try .init(
                        profile: configuration.profile,
                        roster: roster,
                        manifest: manifest,
                        commitmentSet: commitmentSet,
                        componentSet: componentSet
                    )
                } catch {
                    return terminate(
                        with: .failed(.invalidUnsignedTransactionTranscript(error))
                    )
                }
                state = .transcriptAgreement(
                    roster: roster,
                    transcript: transcript
                )
                return [
                    .transcriptInclusionValidationRequired(
                        contributors: roster.contributors,
                        transcript: transcript
                    )
                ]

            case let (
                .transcriptAgreement(roster, transcript),
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
                    $0.roundIdentifier == transcript.manifest.roundIdentifier
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
                guard transcriptRoot == transcript.transcriptRoot else {
                    return terminate(
                        with: .failed(
                            .transcriptRootMismatch(
                                expected: transcript.transcriptRoot,
                                received: transcriptRoot
                            )
                        )
                    )
                }
                state = .bchSigning(
                    roster: roster,
                    transcript: transcript
                )
                return [
                    .bchSigningEligible(
                        contributors: roster.contributors,
                        transcript: transcript
                    )
                ]

            case let (
                .bchSigning(roster, _),
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

        mutating func fail(with failure: Failure) -> [Effect] {
            guard case .terminal = state else {
                return terminate(with: .failed(failure))
            }
            return [.inputRejected(.inputAfterTermination)]
        }
    }
}

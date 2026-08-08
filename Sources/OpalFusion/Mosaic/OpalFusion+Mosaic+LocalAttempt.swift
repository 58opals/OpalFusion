// OpalFusion+Mosaic+LocalAttempt.swift

extension OpalFusion.Mosaic {
    /// A peer-local view over one validated aggregate Mosaic attempt.
    ///
    /// The value binds one control identity, role, generation, and material identity. Construct a distinct value with fresh identifiers and material for every retry.
    struct LocalAttempt: Sendable {
        let attemptIdentifier: AttemptIdentifier
        let generationIdentifier: GenerationIdentifier
        let materialIdentifier: MaterialIdentifier
        let localControlIdentity: Attempt.ControlIdentity
        let localRole: OpalFusion.Mosaic.Role

        private var aggregateAttempt: Attempt
        private(set) var hasReservationEligibility: Bool
        private(set) var hasReservationDisposition: Bool

        var state: Attempt.State {
            aggregateAttempt.state
        }

        var configuration: OpalFusion.Mosaic.Configuration {
            aggregateAttempt.configuration
        }

        init(
            validatedAttempt: Attempt,
            attemptIdentifier: AttemptIdentifier,
            generationIdentifier: GenerationIdentifier,
            materialIdentifier: MaterialIdentifier,
            localControlIdentity: Attempt.ControlIdentity
        ) throws {
            guard case let .manifestAgreement(roleElection) = validatedAttempt.state else {
                throw Failure.attemptNotReadyForLocalBinding
            }
            let roster = roleElection.roster
            guard let localMember = roster.members.first(where: {
                $0.controlIdentity == localControlIdentity
            }) else {
                throw Failure.localControlIdentityNotInRoster(localControlIdentity)
            }

            self.aggregateAttempt = validatedAttempt
            self.attemptIdentifier = attemptIdentifier
            self.generationIdentifier = generationIdentifier
            self.materialIdentifier = materialIdentifier
            self.localControlIdentity = localControlIdentity
            self.localRole = localMember.role
            self.hasReservationEligibility = false
            self.hasReservationDisposition = false
        }

        mutating func apply(input: Input) -> [Effect] {
            guard input.attemptIdentifier == attemptIdentifier else {
                return [
                    .inputRejected(
                        .attemptIdentifierMismatch(
                            expected: attemptIdentifier,
                            received: input.attemptIdentifier
                        )
                    )
                ]
            }
            guard input.generationIdentifier == generationIdentifier else {
                return [
                    .inputRejected(
                        .generationIdentifierMismatch(
                            expected: generationIdentifier,
                            received: input.generationIdentifier
                        )
                    )
                ]
            }

            let aggregateEffects = aggregateAttempt.apply(input: input.validatedFact)
            return localize(aggregateEffects: aggregateEffects)
        }

        private mutating func localize(
            aggregateEffects: [Attempt.Effect]
        ) -> [Effect] {
            var localEffects: [Effect] = []

            for aggregateEffect in aggregateEffects {
                switch aggregateEffect {
                case let .walletReservationEligible(contributors, manifest):
                    guard isEligibleContributor(in: contributors),
                          !hasReservationEligibility else {
                        continue
                    }
                    hasReservationEligibility = true
                    localEffects.append(
                        .walletReservationEligible(
                            contributor: localControlIdentity,
                            materialIdentifier: materialIdentifier,
                            manifest: manifest
                        )
                    )

                case let .bchSigningEligible(contributors, transcriptRoot):
                    guard isEligibleContributor(in: contributors) else {
                        continue
                    }
                    localEffects.append(
                        .bchSigningEligible(
                            contributor: localControlIdentity,
                            materialIdentifier: materialIdentifier,
                            transcriptRoot: transcriptRoot
                        )
                    )

                case let .walletReservationReleaseRequired(contributors):
                    guard isEligibleContributor(in: contributors),
                          hasReservationEligibility,
                          !hasReservationDisposition else {
                        continue
                    }
                    hasReservationDisposition = true
                    localEffects.append(
                        .walletReservationReleaseRequired(
                            contributor: localControlIdentity,
                            materialIdentifier: materialIdentifier
                        )
                    )

                case let .attemptTerminated(outcome):
                    if outcome == .completed,
                       localRole == .contributor,
                       hasReservationEligibility,
                       !hasReservationDisposition {
                        hasReservationDisposition = true
                        localEffects.append(
                            .walletReservationCommitRequired(
                                contributor: localControlIdentity,
                                materialIdentifier: materialIdentifier
                            )
                        )
                    }
                    localEffects.append(.attemptTerminated(outcome))

                case let .inputRejected(failure):
                    localEffects.append(.inputRejected(.attemptFailure(failure)))
                }
            }

            return localEffects
        }

        private func isEligibleContributor(
            in contributors: [Attempt.ControlIdentity]
        ) -> Bool {
            localRole == .contributor && contributors.contains(localControlIdentity)
        }
    }
}

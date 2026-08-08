// MosaicSemanticValidator+ValidationGroup1.swift

@testable import OpalFusion
import Testing

extension MosaicSemanticValidator {
    @Test("Peer-local attempts bind every validated roster identity to its selected role")
    func validateLocalIdentityAndRoleBinding() throws {
        for candidateCount in 7 ... 9 {
            let simulator = try Self.makeSimulator(candidateCount: candidateCount)

            #expect(simulator.localAttempts.count == candidateCount)
            for member in simulator.roster.members {
                let localAttempt = Self.findLocalAttempt(
                    for: member.controlIdentity,
                    in: simulator
                )
                #expect(localAttempt.localControlIdentity == member.controlIdentity)
                #expect(localAttempt.localRole == member.role)
                #expect(localAttempt.state == .manifestAgreement(roster: simulator.roster))
            }
        }

        let roster = try Self.makeRoster(candidateCount: 7)
        let validatedAttempt = Self.makeValidatedAttempt(roster: roster)
        let unknownControlIdentity = Self.makeControlIdentity(position: 20)

        #expect(
            throws: LocalAttempt.Failure.localControlIdentityNotInRoster(
                unknownControlIdentity
            )
        ) {
            _ = try LocalAttempt(
                validatedAttempt: validatedAttempt,
                attemptIdentifier: .init(validatedBytes: [0x11]),
                generationIdentifier: .init(opaqueBytes: [0x21]),
                materialIdentifier: .init(opaqueBytes: [0x31]),
                localControlIdentity: unknownControlIdentity
            )
        }
    }

    @Test("Seven eight and nine peer-local engines complete with contributor-only authority effects")
    func validateSuccessfulPeerCountsAndLocalEffects() throws {
        for candidateCount in 7 ... 9 {
            var simulator = try Self.makeSimulator(candidateCount: candidateCount)

            Self.complete(simulator: &simulator)

            for member in simulator.roster.members {
                let localAttempt = Self.findLocalAttempt(
                    for: member.controlIdentity,
                    in: simulator
                )
                let effects = simulator.effectJournal[member.controlIdentity] ?? []

                #expect(localAttempt.state == .terminal(.completed))
                if member.role == .contributor {
                    #expect(Self.countReservationEligibility(in: effects) == 1)
                    #expect(Self.countSigningEligibility(in: effects) == 1)
                    #expect(Self.countReleaseRequirements(in: effects) == 0)
                    #expect(Self.countCommitRequirements(in: effects) == 1)
                    #expect(localAttempt.hasReservationEligibility)
                    #expect(localAttempt.hasReservationDisposition)
                } else {
                    #expect(Self.countContributorAuthorityEffects(in: effects) == 0)
                    #expect(!localAttempt.hasReservationEligibility)
                    #expect(!localAttempt.hasReservationDisposition)
                }
            }
        }
    }

    @Test("Duplicate delivery follows aggregate terminal semantics without repeating reservation disposition")
    func validateDuplicateDeliverySemantics() throws {
        var simulator = try Self.makeSimulator()
        let manifestFact = Attempt.Input.manifestSignaturesValidated(
            Self.makeManifestSignatureValidations(
                roster: simulator.roster,
                manifest: Self.manifestA
            )
        )
        _ = simulator.broadcast(validatedFact: manifestFact)

        _ = simulator.broadcast(validatedFact: manifestFact)

        let failure = Attempt.Failure.invalidTransition(
            from: .walletReservation,
            received: .manifestSignaturesValidated
        )
        for member in simulator.roster.members {
            let localAttempt = Self.findLocalAttempt(
                for: member.controlIdentity,
                in: simulator
            )
            let effects = simulator.effectJournal[member.controlIdentity] ?? []
            #expect(localAttempt.state == .terminal(.failed(failure)))

            if member.role == .contributor {
                #expect(Self.countReservationEligibility(in: effects) == 1)
                #expect(Self.countReleaseRequirements(in: effects) == 1)
                #expect(Self.countCommitRequirements(in: effects) == 0)
            } else {
                #expect(Self.countContributorAuthorityEffects(in: effects) == 0)
            }
        }

        let terminalDuplicateEffects = simulator.broadcast(validatedFact: manifestFact)
        for member in simulator.roster.members {
            #expect(
                terminalDuplicateEffects[member.controlIdentity]
                    == [.inputRejected(.attemptFailure(.inputAfterTermination))]
            )
            let effects = simulator.effectJournal[member.controlIdentity] ?? []
            #expect(Self.countReleaseRequirements(in: effects) <= 1)
            #expect(Self.countCommitRequirements(in: effects) == 0)
        }
    }
}

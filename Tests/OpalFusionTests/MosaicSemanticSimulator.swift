// MosaicSemanticSimulator.swift

@testable import OpalFusion

struct MosaicSemanticSimulator {
    typealias Attempt = OpalFusion.Mosaic.Attempt
    typealias LocalAttempt = OpalFusion.Mosaic.LocalAttempt

    let roleElection: Attempt.RoleElectionResult
    let attemptIdentifier: LocalAttempt.AttemptIdentifier
    let generationIdentifier: LocalAttempt.GenerationIdentifier

    private(set) var localAttempts: [LocalAttempt]
    private(set) var effectJournal: [Attempt.ControlIdentity: [LocalAttempt.Effect]]

    init(
        validatedAttempt: Attempt,
        attemptIdentifier: LocalAttempt.AttemptIdentifier,
        generationIdentifier: LocalAttempt.GenerationIdentifier,
        materialIdentifiers: [LocalAttempt.MaterialIdentifier]
    ) throws {
        guard case let .manifestAgreement(roleElection) = validatedAttempt.state else {
            throw MosaicSemanticSimulationFailure.attemptNotReady
        }
        let roster = roleElection.roster
        guard materialIdentifiers.count == roster.members.count else {
            throw MosaicSemanticSimulationFailure.materialIdentifierCountMismatch(
                expected: roster.members.count,
                actual: materialIdentifiers.count
            )
        }

        self.roleElection = roleElection
        self.attemptIdentifier = attemptIdentifier
        self.generationIdentifier = generationIdentifier
        self.localAttempts = try zip(roster.members, materialIdentifiers).map {
            member, materialIdentifier in
            try LocalAttempt(
                validatedAttempt: validatedAttempt,
                attemptIdentifier: attemptIdentifier,
                generationIdentifier: generationIdentifier,
                materialIdentifier: materialIdentifier,
                localControlIdentity: member.controlIdentity
            )
        }
        self.effectJournal = Dictionary(
            uniqueKeysWithValues: roster.controlIdentities.map { ($0, []) }
        )
    }

    var roster: Attempt.Roster {
        roleElection.roster
    }

    mutating func broadcast(
        validatedFact: Attempt.Input
    ) -> [Attempt.ControlIdentity: [LocalAttempt.Effect]] {
        deliver(
            validatedFact: validatedFact,
            to: roster.controlIdentities
        )
    }

    mutating func deliver(
        validatedFact: Attempt.Input,
        to recipients: [Attempt.ControlIdentity]
    ) -> [Attempt.ControlIdentity: [LocalAttempt.Effect]] {
        var deliveryEffects: [Attempt.ControlIdentity: [LocalAttempt.Effect]] = [:]

        for localAttemptIndex in localAttempts.indices {
            let localControlIdentity = localAttempts[localAttemptIndex].localControlIdentity
            guard recipients.contains(localControlIdentity) else {
                continue
            }
            let input = LocalAttempt.Input(
                attemptIdentifier: attemptIdentifier,
                generationIdentifier: generationIdentifier,
                validatedFact: validatedFact
            )
            let effects = localAttempts[localAttemptIndex].apply(input: input)
            deliveryEffects[localControlIdentity] = effects
            effectJournal[localControlIdentity, default: []].append(contentsOf: effects)
        }

        return deliveryEffects
    }

    mutating func deliver(
        input: LocalAttempt.Input,
        to recipient: Attempt.ControlIdentity
    ) -> [LocalAttempt.Effect] {
        guard let localAttemptIndex = localAttempts.firstIndex(where: {
            $0.localControlIdentity == recipient
        }) else {
            preconditionFailure("The semantic simulator recipient must belong to its validated roster")
        }

        let effects = localAttempts[localAttemptIndex].apply(input: input)
        effectJournal[recipient, default: []].append(contentsOf: effects)
        return effects
    }
}

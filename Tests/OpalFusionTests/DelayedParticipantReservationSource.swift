// DelayedParticipantReservationSource.swift

@testable import OpalFusion
import Foundation

actor DelayedParticipantReservationSource: OpalFusion.Host.ParticipantReservationSource {
    private let participantInputs: [OpalFusion.Host.ParticipantInput]
    private let participantOutputs: [OpalFusion.Host.ParticipantOutput]
    private let delay: Duration
    private var requestedRoundIdentifiers: [OpalFusion.Round.Identifier] = []
    private var requestedReservationContexts: [OpalFusion.Host.ParticipantReservationContext] = []
    private var requestRecords: [TimedRoundRequestRecord] = []

    init(
        participantInputs: [OpalFusion.Host.ParticipantInput],
        participantOutputs: [OpalFusion.Host.ParticipantOutput] = [],
        delay: Duration = .zero
    ) {
        self.participantInputs = participantInputs
        self.participantOutputs = participantOutputs
        self.delay = delay
        self.requestedRoundIdentifiers = []
    }

    func reserveParticipant(
        for roundIdentifier: OpalFusion.Round.Identifier
    ) async throws -> OpalFusion.Host.ParticipantReservation {
        try await reserveParticipantReservation(for: roundIdentifier)
    }

    func reserveParticipant(
        for context: OpalFusion.Host.ParticipantReservationContext
    ) async throws -> OpalFusion.Host.ParticipantReservation {
        requestedReservationContexts.append(context)
        return try await reserveParticipantReservation(for: context.roundIdentifier)
    }

    private func reserveParticipantReservation(
        for roundIdentifier: OpalFusion.Round.Identifier
    ) async throws -> OpalFusion.Host.ParticipantReservation {
        requestedRoundIdentifiers.append(roundIdentifier)
        requestRecords.append(
            .init(
                roundIdentifier: roundIdentifier,
                recordedAt: Date()
            )
        )

        if delay > .zero {
            try await Task.sleep(for: delay)
        }

        return .init(
            inputs: participantInputs,
            outputs: participantOutputs
        )
    }

    var requestedRounds: [OpalFusion.Round.Identifier] {
        requestedRoundIdentifiers
    }

    var requestedContexts: [OpalFusion.Host.ParticipantReservationContext] {
        requestedReservationContexts
    }

    var timedRequestRecords: [TimedRoundRequestRecord] {
        requestRecords
    }
}

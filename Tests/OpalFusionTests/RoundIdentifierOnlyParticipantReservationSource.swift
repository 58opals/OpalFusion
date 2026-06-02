// RoundIdentifierOnlyParticipantReservationSource.swift

import OpalFusion

actor RoundIdentifierOnlyParticipantReservationSource: OpalFusion.Host.ParticipantReservationSource {
    private let reservation: OpalFusion.Host.ParticipantReservation
    private var roundIdentifiers: [OpalFusion.Round.Identifier] = []

    init(
        reservation: OpalFusion.Host.ParticipantReservation
    ) {
        self.reservation = reservation
    }

    func reserveParticipant(
        for roundIdentifier: OpalFusion.Round.Identifier
    ) async throws -> OpalFusion.Host.ParticipantReservation {
        roundIdentifiers.append(roundIdentifier)
        return reservation
    }

    var requestedRounds: [OpalFusion.Round.Identifier] {
        roundIdentifiers
    }
}

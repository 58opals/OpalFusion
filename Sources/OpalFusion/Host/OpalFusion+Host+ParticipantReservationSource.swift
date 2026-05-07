// OpalFusion+Host+ParticipantReservationSource.swift

public extension OpalFusion.Host {
    /// Supplies the host's reserved inputs and outputs for a specific round.
    protocol ParticipantReservationSource: Sendable {
        func participantReservation(
            for roundIdentifier: OpalFusion.Round.Identifier
        ) async throws -> OpalFusion.Host.ParticipantReservation

        func participantReservation(
            for context: OpalFusion.Host.ParticipantReservationContext
        ) async throws -> OpalFusion.Host.ParticipantReservation
    }
}

public extension OpalFusion.Host.ParticipantReservationSource {
    func participantReservation(
        for context: OpalFusion.Host.ParticipantReservationContext
    ) async throws -> OpalFusion.Host.ParticipantReservation {
        try await participantReservation(for: context.roundIdentifier)
    }
}

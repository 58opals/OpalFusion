// OpalFusion+Host+ParticipantReservationSource.swift

public extension OpalFusion.Host {
    /// Supplies the host's reserved inputs and outputs for a specific round.
    protocol ParticipantReservationSource: Sendable {
        func reserveParticipant(
            for roundIdentifier: OpalFusion.Round.Identifier
        ) async throws -> OpalFusion.Host.ParticipantReservation

        func reserveParticipant(
            for context: OpalFusion.Host.ParticipantReservationContext
        ) async throws -> OpalFusion.Host.ParticipantReservation
    }
}

public extension OpalFusion.Host.ParticipantReservationSource {
    func reserveParticipant(
        for context: OpalFusion.Host.ParticipantReservationContext
    ) async throws -> OpalFusion.Host.ParticipantReservation {
        try await reserveParticipant(for: context.roundIdentifier)
    }
}

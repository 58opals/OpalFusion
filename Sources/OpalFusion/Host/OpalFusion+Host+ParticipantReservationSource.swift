// OpalFusion+Host+ParticipantReservationSource.swift

public extension OpalFusion.Host {
    /// Supplies the host's reserved inputs and outputs for a specific round.
    protocol ParticipantReservationSource: Sendable {
        func participantReservation(
            for roundIdentifier: OpalFusion.Round.Identifier
        ) async throws -> OpalFusion.Host.ParticipantReservation
    }
}

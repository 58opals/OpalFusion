// OpalFusion+Host+ParticipantReservationSource.swift

public extension OpalFusion.Host {
    /// Supplies host-owned participant inputs and outputs for a specific CashFusion coordinator round.
    ///
    /// Implementations may consult wallet state or SwiftData snapshots, but OpalFusion receives only the reservation material needed for the fusion protocol and does not own those snapshots.
    protocol ParticipantReservationSource: Sendable {
        func reserveParticipant(
            for roundIdentifier: OpalFusion.Round.Identifier
        ) async throws -> OpalFusion.Host.ParticipantReservation

        func reserveParticipant(
            for context: OpalFusion.Host.ParticipantReservationContext
        ) async throws -> OpalFusion.Host.ParticipantReservation
    }
}

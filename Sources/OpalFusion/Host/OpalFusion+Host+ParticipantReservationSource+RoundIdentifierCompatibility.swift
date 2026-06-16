// OpalFusion+Host+ParticipantReservationSource+RoundIdentifierCompatibility.swift

public extension OpalFusion.Host.ParticipantReservationSource {
    func reserveParticipant(
        for context: OpalFusion.Host.ParticipantReservationContext
    ) async throws -> OpalFusion.Host.ParticipantReservation {
        try await reserveParticipant(for: context.roundIdentifier)
    }
}

// OpalFusion+Host+ParticipantInputProvider.swift

public extension OpalFusion.Host {
    protocol ParticipantInputProvider: Sendable {
        func reservedInputs(
            for roundIdentifier: OpalFusion.Round.Identifier
        ) async throws -> [OpalFusion.Host.ParticipantInput]

        func participantReservation(
            for roundIdentifier: OpalFusion.Round.Identifier
        ) async throws -> OpalFusion.Host.ParticipantReservation
    }
}

public extension OpalFusion.Host.ParticipantInputProvider {
    func participantReservation(
        for roundIdentifier: OpalFusion.Round.Identifier
    ) async throws -> OpalFusion.Host.ParticipantReservation {
        .init(
            inputs: try await reservedInputs(for: roundIdentifier),
            outputs: []
        )
    }
}

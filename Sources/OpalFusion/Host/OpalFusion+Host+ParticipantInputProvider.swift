// OpalFusion+Host+ParticipantInputProvider.swift

public extension OpalFusion.Host {
    protocol ParticipantInputProvider: Sendable {
        func reservedInputs(
            for roundIdentifier: OpalFusion.Round.Identifier
        ) async throws -> [OpalFusion.Host.ParticipantInput]
    }
}

// HostParticipantInputProviderAdapter.swift

import OpalFusion

struct HostParticipantInputProviderAdapter: OpalFusion.Host.ParticipantInputProvider {
    let participantInputs: [OpalFusion.Host.ParticipantInput]

    func reservedInputs(
        for roundIdentifier: OpalFusion.Round.Identifier
    ) async throws -> [OpalFusion.Host.ParticipantInput] {
        participantInputs
    }
}

// HostParticipantInputProviderAdapter.swift

import OpalFusion

struct HostParticipantInputProviderAdapter: OpalFusion.Host.ParticipantInputProvider {
    let participantInputs: [OpalFusion.Host.ParticipantInput]
    let participantOutputs: [OpalFusion.Host.ParticipantOutput]

    init(
        participantInputs: [OpalFusion.Host.ParticipantInput],
        participantOutputs: [OpalFusion.Host.ParticipantOutput] = []
    ) {
        self.participantInputs = participantInputs
        self.participantOutputs = participantOutputs
    }

    func reservedInputs(
        for roundIdentifier: OpalFusion.Round.Identifier
    ) async throws -> [OpalFusion.Host.ParticipantInput] {
        participantInputs
    }

    func participantReservation(
        for roundIdentifier: OpalFusion.Round.Identifier
    ) async throws -> OpalFusion.Host.ParticipantReservation {
        .init(
            inputs: participantInputs,
            outputs: participantOutputs
        )
    }
}

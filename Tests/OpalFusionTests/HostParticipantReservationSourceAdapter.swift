// HostParticipantReservationSourceAdapter.swift

import OpalFusion

struct HostParticipantReservationSourceAdapter: OpalFusion.Host.ParticipantReservationSource {
    let participantInputs: [OpalFusion.Host.ParticipantInput]
    let participantOutputs: [OpalFusion.Host.ParticipantOutput]

    init(
        participantInputs: [OpalFusion.Host.ParticipantInput],
        participantOutputs: [OpalFusion.Host.ParticipantOutput] = []
    ) {
        self.participantInputs = participantInputs
        self.participantOutputs = participantOutputs
    }

    func reserveParticipant(
        for roundIdentifier: OpalFusion.Round.Identifier
    ) async throws -> OpalFusion.Host.ParticipantReservation {
        .init(
            inputs: participantInputs,
            outputs: participantOutputs
        )
    }
}

// OpalFusion+Execution+ProductionWorkflow+PlayerCommitInput.swift

import Foundation

extension OpalFusion.Execution.ProductionWorkflow {
    func requirePlayerCommitInput(
        round: OpalFusion.Execution.RoundContext
    ) throws -> (
        reservation: OpalFusion.Host.ParticipantReservation,
        startRound: OpalFusion.ProtocolModel.StartRound,
        numberOfComponents: Int
    ) {
        guard let reservation = round.participantReservation else {
            throw OpalFusion.Execution.WorkflowFailure.invalidParticipantReservation(
                "Participant reservation was not loaded"
            )
        }
        guard let startRound = round.startRound else {
            throw OpalFusion.Execution.WorkflowFailure.protocolValidationFailed(
                "StartRound must be present before player commit construction"
            )
        }

        let numberOfComponents = Int(round.serverHello.numberOfComponents)
        guard reservation.inputs.isEmpty == false else {
            throw OpalFusion.Execution.WorkflowFailure.invalidParticipantReservation(
                "At least one participant input is required"
            )
        }
        guard reservation.outputs.isEmpty == false else {
            throw OpalFusion.Execution.WorkflowFailure.invalidParticipantReservation(
                "At least one participant output is required"
            )
        }
        guard reservation.inputs.count + reservation.outputs.count <= numberOfComponents else {
            throw OpalFusion.Execution.WorkflowFailure.invalidParticipantReservation(
                "Participant reservation exceeds the server component limit"
            )
        }
        guard startRound.blindNoncePoints.count == numberOfComponents else {
            throw OpalFusion.Execution.WorkflowFailure.protocolValidationFailed(
                "Coordinator returned the wrong number of blind nonce points"
            )
        }

        return (reservation, startRound, numberOfComponents)
    }
}

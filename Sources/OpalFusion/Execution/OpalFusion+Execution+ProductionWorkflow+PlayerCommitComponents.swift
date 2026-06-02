// OpalFusion+Execution+ProductionWorkflow+PlayerCommitComponents.swift

import Foundation

extension OpalFusion.Execution.ProductionWorkflow {
    func appendInputComponentMaterials(
        from reservation: OpalFusion.Host.ParticipantReservation,
        feeRateSatoshisPerKb: UInt64,
        components: inout [OpalFusion.Execution.LocalComponentMaterial],
        reservationInputOutpoints: inout Set<InputOutpoint>
    ) throws {
        for (index, input) in reservation.inputs.enumerated() {
            guard reservationInputOutpoints.insert(.init(input)).inserted else {
                throw OpalFusion.Execution.WorkflowFailure.invalidParticipantReservation(
                    "Participant reservation contains duplicate input outpoints"
                )
            }
            guard input.amountSatoshis <= OpalFusion.Execution.ProtocolPrimitives.maximumMoneySatoshis else {
                throw OpalFusion.Execution.WorkflowFailure.invalidParticipantReservation(
                    "Participant input at index \(index) exceeds the maximum BCH money supply"
                )
            }

            let publicKey = try OpalFusion.Execution.ProtocolPrimitives
                .validateSupportedParticipantInput(
                    input,
                    inputIndex: index
                )

            let componentPayload = OpalFusion.Commitment.ComponentPayload.input(
                .init(
                    outpointTransactionHash: input.outpointTransactionHashBytes,
                    outpointIndex: input.outpointIndex,
                    publicKey: publicKey,
                    amountSatoshis: input.amountSatoshis
                )
            )
            let fee = try checkedComponentFee(
                sizeBytes: OpalFusion.Execution.ProtocolPrimitives.inputSize(for: publicKey),
                feeRateSatoshisPerKb: feeRateSatoshisPerKb
            )
            components.append(
                try buildComponentMaterial(
                    originalSlot: index,
                    payload: componentPayload,
                    contributionSatoshis: Int64(input.amountSatoshis) - Int64(fee)
                )
            )
        }
    }

    func appendOutputComponentMaterials(
        from reservation: OpalFusion.Host.ParticipantReservation,
        feeRateSatoshisPerKb: UInt64,
        components: inout [OpalFusion.Execution.LocalComponentMaterial]
    ) throws {
        for (index, output) in reservation.outputs.enumerated() {
            guard output.amountSatoshis <= OpalFusion.Execution.ProtocolPrimitives.maximumMoneySatoshis else {
                throw OpalFusion.Execution.WorkflowFailure.invalidParticipantReservation(
                    "Participant output at index \(index) exceeds the maximum BCH money supply"
                )
            }

            let minimumAmount = OpalFusion.Execution.ProtocolPrimitives.minimumOutputAmount(
                for: output.lockingScriptBytes,
                baseline: baseline
            )
            guard output.amountSatoshis >= minimumAmount else {
                throw OpalFusion.Execution.WorkflowFailure.invalidParticipantReservation(
                    "Participant output at index \(index) is below the minimum allowed amount"
                )
            }

            let componentPayload = OpalFusion.Commitment.ComponentPayload.output(
                .init(
                    lockingScript: output.lockingScriptBytes,
                    amountSatoshis: output.amountSatoshis
                )
            )
            let fee = try checkedComponentFee(
                sizeBytes: OpalFusion.Execution.ProtocolPrimitives.outputSize(
                    for: output.lockingScriptBytes
                ),
                feeRateSatoshisPerKb: feeRateSatoshisPerKb
            )
            let amount = Int64(output.amountSatoshis)
            let signedFee = Int64(fee)
            guard signedFee <= Int64.max - amount else {
                throw OpalFusion.Execution.WorkflowFailure.protocolValidationFailed(
                    "Coordinator component fee rate was too large"
                )
            }
            components.append(
                try buildComponentMaterial(
                    originalSlot: reservation.inputs.count + index,
                    payload: componentPayload,
                    contributionSatoshis: -(amount + signedFee)
                )
            )
        }
    }
}

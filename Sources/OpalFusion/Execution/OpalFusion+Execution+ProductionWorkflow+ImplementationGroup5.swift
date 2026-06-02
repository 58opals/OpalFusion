// OpalFusion+Execution+ProductionWorkflow+ImplementationGroup5.swift

import Foundation
import OpalCrypto
import OpalDiagnostics

extension OpalFusion.Execution.ProductionWorkflow {
    func makeTransactionTemplate(
        decodedComponents: [OpalFusion.Execution.DecodedComponent],
        sessionHash: [UInt8]
    ) throws -> (
        transaction: OpalFusion.Execution.BCHTransaction,
        inputComponentIndices: [Int]
    ) {
        var inputs: [OpalFusion.Execution.BCHTransaction.Input] = []
        var outputs: [OpalFusion.Execution.BCHTransaction.Output] = [
            .init(
                amountSatoshis: 0,
                lockingScript: OpalFusion.Execution.ProtocolPrimitives
                    .makeSessionHashLockingScript(
                        sessionHash: sessionHash,
                        baseline: baseline
                    )
            )
        ]
        var inputComponentIndices: [Int] = []
        var inputOutpoints = Set<InputOutpoint>()

        for (componentIndex, component) in decodedComponents.enumerated() {
            switch component.payload {
            case let .input(inputComponent):
                guard inputOutpoints.insert(.init(inputComponent)).inserted else {
                    throw OpalFusion.Execution.WorkflowFailure.protocolValidationFailed(
                        "Coordinator returned duplicate input outpoints"
                    )
                }

                inputs.append(
                    .init(
                        previousTransactionHashLittleEndian: Array(
                            inputComponent.outpointTransactionHash.reversed()
                        ),
                        previousOutputIndex: inputComponent.outpointIndex,
                        unlockingScript: [],
                        sequence: 0xFFFF_FFFF
                    )
                )
                inputComponentIndices.append(componentIndex)
            case let .output(outputComponent):
                outputs.append(
                    .init(
                        amountSatoshis: outputComponent.amountSatoshis,
                        lockingScript: outputComponent.lockingScript
                    )
                )
            case .blank:
                break
            }
        }

        return (
            .init(
                version: 1,
                inputs: inputs,
                outputs: outputs,
                lockTime: 0
            ),
            inputComponentIndices
        )
    }

    func makeLocalInputReferences(
        reservation: OpalFusion.Host.ParticipantReservation,
        playerCommitMaterial: OpalFusion.Execution.PlayerCommitMaterial,
        myComponentIndices: [Int],
        transactionInputComponentIndices: [Int]
    ) throws -> [OpalFusion.Execution.LocalInputReference] {
        var references: [OpalFusion.Execution.LocalInputReference] = []
        let localComponentsByComponentIndex = Dictionary(
            uniqueKeysWithValues: zip(
                myComponentIndices,
                playerCommitMaterial.componentsByCommitmentOrder
            ).map { ($0, $1) }
        )

        for (transactionInputIndex, componentIndex) in transactionInputComponentIndices.enumerated() {
            guard let localComponent = localComponentsByComponentIndex[componentIndex] else {
                continue
            }
            guard case .input = localComponent.payload else {
                continue
            }
            let reservationInputIndex = localComponent.originalSlot
            guard reservation.inputs.indices.contains(reservationInputIndex) else {
                throw OpalFusion.Execution.WorkflowFailure.protocolValidationFailed(
                    "Local reservation input mapping was inconsistent"
                )
            }
            references.append(
                .init(
                    transactionInputIndex: transactionInputIndex,
                    componentIndex: componentIndex,
                    reservationInputIndex: reservationInputIndex,
                    originalSlot: localComponent.originalSlot,
                    participantInput: reservation.inputs[reservationInputIndex]
                )
            )
        }

        return references
    }

    func validateFinalizedTransaction(
        _ finalizedTransaction: OpalFusion.Execution.BCHTransaction,
        against template: OpalFusion.Execution.BCHTransaction,
        localInputReferences: [OpalFusion.Execution.LocalInputReference]
    ) throws {
        guard finalizedTransaction.version == template.version else {
            throw OpalFusion.Execution.BCHTransactionError.templateMismatch(
                "Finalized transaction version did not match the unsigned template"
            )
        }
        guard finalizedTransaction.lockTime == template.lockTime else {
            throw OpalFusion.Execution.BCHTransactionError.templateMismatch(
                "Finalized transaction locktime did not match the unsigned template"
            )
        }
        guard finalizedTransaction.inputs.count == template.inputs.count else {
            throw OpalFusion.Execution.BCHTransactionError.templateMismatch(
                "Finalized transaction input count did not match the unsigned template"
            )
        }
        guard finalizedTransaction.outputs == template.outputs else {
            throw OpalFusion.Execution.BCHTransactionError.templateMismatch(
                "Finalized transaction outputs did not match the unsigned template"
            )
        }

        let localInputIndices = Set(localInputReferences.map(\.transactionInputIndex))
        for (inputIndex, (finalizedInput, templateInput)) in zip(
            finalizedTransaction.inputs.indices,
            zip(finalizedTransaction.inputs, template.inputs)
        ) {
            guard finalizedInput.previousTransactionHashLittleEndian ==
                templateInput.previousTransactionHashLittleEndian,
                  finalizedInput.previousOutputIndex == templateInput.previousOutputIndex,
                  finalizedInput.sequence == templateInput.sequence else {
                throw OpalFusion.Execution.BCHTransactionError.templateMismatch(
                    "Finalized transaction input \(inputIndex) did not match the unsigned template"
                )
            }

            if localInputIndices.contains(inputIndex) == false,
               finalizedInput.unlockingScript.isEmpty == false {
                throw OpalFusion.Execution.BCHTransactionError.templateMismatch(
                    "Finalized transaction included signatures for non-local inputs"
                )
            }
        }
    }
}

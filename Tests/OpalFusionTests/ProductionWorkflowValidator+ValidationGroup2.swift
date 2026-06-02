// ProductionWorkflowValidator+ValidationGroup2.swift

@testable import OpalFusion
import Foundation
import OpalCrypto
import Testing

extension ProductionWorkflowValidator {
    @Test("Production workflow rejects invalid participant reservations early")
    func validateParticipantReservationFailures() throws {
        do {
            var scenario = try ProductionWorkflowTestFixtures.makeScenario()
            let invalidInput = OpalFusion.Host.ParticipantInput(
                outpointTransactionHashBytes: scenario.reservation.inputs[0].outpointTransactionHashBytes,
                outpointIndex: scenario.reservation.inputs[0].outpointIndex,
                amountSatoshis: scenario.reservation.inputs[0].amountSatoshis,
                lockingScriptBytes: scenario.reservation.inputs[0].lockingScriptBytes
            )
            let invalidReservation = OpalFusion.Host.ParticipantReservation(
                inputs: [invalidInput],
                outputs: scenario.reservation.outputs
            )
            scenario.round.participantReservation = invalidReservation
            _ = try scenario.workflow.buildPlayerCommit(round: &scenario.round)
            Issue.record("Expected missing public-key reservation to fail")
        } catch let error as OpalFusion.Execution.WorkflowFailure {
            #expect(error == .missingParticipantInputPublicKey(index: 0))
        }

        do {
            var scenario = try ProductionWorkflowTestFixtures.makeScenario()
            scenario.round.participantReservation = .init(
                inputs: scenario.reservation.inputs,
                outputs: []
            )
            _ = try scenario.workflow.buildPlayerCommit(round: &scenario.round)
            Issue.record("Expected empty-output reservation to fail")
        } catch let error as OpalFusion.Execution.WorkflowFailure {
            #expect(
                error == .invalidParticipantReservation(
                    "At least one participant output is required"
                )
            )
        }

        do {
            var scenario = try ProductionWorkflowTestFixtures.makeScenario()
            scenario.round.participantReservation = .init(
                inputs: scenario.reservation.inputs,
                outputs: [scenario.reservation.outputs[0], scenario.reservation.outputs[0], scenario.reservation.outputs[0]]
            )
            _ = try scenario.workflow.buildPlayerCommit(round: &scenario.round)
            Issue.record("Expected oversized reservation to fail")
        } catch let error as OpalFusion.Execution.WorkflowFailure {
            #expect(
                error == .invalidParticipantReservation(
                    "Participant reservation exceeds the server component limit"
                )
            )
        }

        do {
            var scenario = try ProductionWorkflowTestFixtures.makeScenario()
            scenario.round.participantReservation = .init(
                inputs: [
                    .init(
                        outpointTransactionHashBytes: scenario.reservation.inputs[0].outpointTransactionHashBytes,
                        outpointIndex: scenario.reservation.inputs[0].outpointIndex,
                        amountSatoshis: scenario.reservation.inputs[0].amountSatoshis,
                        lockingScriptBytes: scenario.reservation.inputs[0].lockingScriptBytes,
                        publicKey: [UInt8](repeating: 0x04, count: 65)
                    )
                ],
                outputs: scenario.reservation.outputs
            )
            _ = try scenario.workflow.buildPlayerCommit(round: &scenario.round)
            Issue.record("Expected malformed public-key reservation to fail")
        } catch let error as OpalFusion.Execution.WorkflowFailure {
            #expect(
                error == .invalidParticipantReservation(
                    "Participant input at index 0 must provide the compressed public key required for standard P2PKH support"
                )
            )
        }

        do {
            var scenario = try ProductionWorkflowTestFixtures.makeScenario()
            scenario.round.participantReservation = .init(
                inputs: [
                    .init(
                        outpointTransactionHashBytes: [UInt8](repeating: 0xAB, count: 31),
                        outpointIndex: scenario.reservation.inputs[0].outpointIndex,
                        amountSatoshis: scenario.reservation.inputs[0].amountSatoshis,
                        lockingScriptBytes: scenario.reservation.inputs[0].lockingScriptBytes,
                        publicKey: scenario.reservation.inputs[0].publicKey
                    )
                ],
                outputs: scenario.reservation.outputs
            )
            _ = try scenario.workflow.buildPlayerCommit(round: &scenario.round)
            Issue.record("Expected short previous transaction hash reservation to fail")
        } catch let error as OpalFusion.Execution.WorkflowFailure {
            #expect(
                error == .invalidParticipantReservation(
                    "Participant input at index 0 previous transaction hash must be 32 bytes"
                )
            )
        }

        do {
            var scenario = try ProductionWorkflowTestFixtures.makeScenario()
            scenario.round.participantReservation = .init(
                inputs: [
                    .init(
                        outpointTransactionHashBytes: scenario.reservation.inputs[0].outpointTransactionHashBytes,
                        outpointIndex: scenario.reservation.inputs[0].outpointIndex,
                        amountSatoshis: scenario.reservation.inputs[0].amountSatoshis,
                        lockingScriptBytes: [0x51],
                        publicKey: scenario.reservation.inputs[0].publicKey
                    )
                ],
                outputs: scenario.reservation.outputs
            )
            _ = try scenario.workflow.buildPlayerCommit(round: &scenario.round)
            Issue.record("Expected non-P2PKH reservation to fail")
        } catch let error as OpalFusion.Execution.WorkflowFailure {
            #expect(
                error == .unsupportedExecution(
                    OpalFusion.Execution.ProtocolPrimitives.supportedParticipantInputSummary
                )
            )
        }

        do {
            var scenario = try ProductionWorkflowTestFixtures.makeScenario()
            let input = scenario.reservation.inputs[0]
            let inputFee = OpalFusion.Execution.ProtocolPrimitives.componentFee(
                sizeBytes: OpalFusion.Execution.ProtocolPrimitives.inputSize(
                    for: input.publicKey ?? []
                ),
                feeRateSatoshisPerKb: scenario.serverHello.componentFeeRateSatoshisPerKb
            )
            let outputFee = OpalFusion.Execution.ProtocolPrimitives.componentFee(
                sizeBytes: OpalFusion.Execution.ProtocolPrimitives.outputSize(
                    for: scenario.reservation.outputs[0].lockingScriptBytes
                ),
                feeRateSatoshisPerKb: scenario.serverHello.componentFeeRateSatoshisPerKb
            )
            let outputAmount = (input.amountSatoshis * 2) - (inputFee * 2) - outputFee - 250
            scenario.round.participantReservation = .init(
                inputs: [input, input],
                outputs: [
                    .init(
                        lockingScriptBytes: scenario.reservation.outputs[0].lockingScriptBytes,
                        amountSatoshis: outputAmount
                    )
                ]
            )
            _ = try scenario.workflow.buildPlayerCommit(round: &scenario.round)
            Issue.record("Expected duplicate participant input outpoint to fail")
        } catch let error as OpalFusion.Execution.WorkflowFailure {
            #expect(
                error == .invalidParticipantReservation(
                    "Participant reservation contains duplicate input outpoints"
                )
            )
        }
    }
}

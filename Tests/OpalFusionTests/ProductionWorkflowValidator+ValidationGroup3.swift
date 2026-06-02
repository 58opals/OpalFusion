// ProductionWorkflowValidator+ValidationGroup3.swift

@testable import OpalFusion
import Foundation
import OpalCrypto
import Testing

extension ProductionWorkflowValidator {
    @Test("Production workflow rejects compressed-length participant keys that are not curve points")
    func validateParticipantReservationRejectsInvalidCompressedPublicKey() throws {
        let invalidCompressedPublicKey = [UInt8](arrayLiteral: 0x02)
            + [UInt8](repeating: 0x00, count: 32)

        do {
            var scenario = try ProductionWorkflowTestFixtures.makeScenario()
            scenario.round.participantReservation = .init(
                inputs: [
                    .init(
                        outpointTransactionHashBytes: scenario.reservation.inputs[0].outpointTransactionHashBytes,
                        outpointIndex: scenario.reservation.inputs[0].outpointIndex,
                        amountSatoshis: scenario.reservation.inputs[0].amountSatoshis,
                        lockingScriptBytes: ProductionWorkflowTestFixtures.p2pkhLockingScript(
                            publicKey: invalidCompressedPublicKey
                        ),
                        publicKey: invalidCompressedPublicKey
                    )
                ],
                outputs: scenario.reservation.outputs
            )
            _ = try scenario.workflow.buildPlayerCommit(round: &scenario.round)
            Issue.record("Expected invalid curve-point reservation to fail")
        } catch let error as OpalFusion.Execution.WorkflowFailure {
            #expect(
                error == .invalidParticipantReservation(
                    "Participant input at index 0 must provide the compressed public key required for standard P2PKH support"
                )
            )
        }
    }

    @Test("Production workflow rejects participant amounts above the BCH money supply")
    func validateParticipantReservationRejectsImpossibleAmounts() throws {
        var scenario = try ProductionWorkflowTestFixtures.makeScenario()
        let impossibleInputAmount: UInt64 = 3_000_000_000_000_000
        let inputFee = OpalFusion.Execution.ProtocolPrimitives.componentFee(
            sizeBytes: OpalFusion.Execution.ProtocolPrimitives.inputSize(
                for: scenario.reservation.inputs[0].publicKey ?? []
            ),
            feeRateSatoshisPerKb: scenario.serverHello.componentFeeRateSatoshisPerKb
        )
        let outputFee = OpalFusion.Execution.ProtocolPrimitives.componentFee(
            sizeBytes: OpalFusion.Execution.ProtocolPrimitives.outputSize(
                for: scenario.reservation.outputs[0].lockingScriptBytes
            ),
            feeRateSatoshisPerKb: scenario.serverHello.componentFeeRateSatoshisPerKb
        )
        let impossibleOutputAmount = impossibleInputAmount - inputFee - outputFee - 250

        scenario.round.participantReservation = .init(
            inputs: [
                .init(
                    outpointTransactionHashBytes: scenario.reservation.inputs[0].outpointTransactionHashBytes,
                    outpointIndex: scenario.reservation.inputs[0].outpointIndex,
                    amountSatoshis: impossibleInputAmount,
                    lockingScriptBytes: scenario.reservation.inputs[0].lockingScriptBytes,
                    publicKey: scenario.reservation.inputs[0].publicKey
                )
            ],
            outputs: [
                .init(
                    lockingScriptBytes: scenario.reservation.outputs[0].lockingScriptBytes,
                    amountSatoshis: impossibleOutputAmount
                )
            ]
        )

        do {
            _ = try scenario.workflow.buildPlayerCommit(round: &scenario.round)
            Issue.record("Expected impossible participant amount to fail")
        } catch let error as OpalFusion.Execution.WorkflowFailure {
            #expect(
                error == .invalidParticipantReservation(
                    "Participant input at index 0 exceeds the maximum BCH money supply"
                )
            )
        }
    }

    @Test("Production workflow rejects coordinator fee rates that exceed safe arithmetic range")
    func validateCoordinatorFeeRateOverflowRejection() throws {
        var scenario = try ProductionWorkflowTestFixtures.makeScenario()
        let startRound = scenario.round.startRound
        let identifier = scenario.round.identifier
        let participantReservation = scenario.round.participantReservation
        let serverHello = OpalFusion.ProtocolModel.ServerHello(
            tiers: scenario.serverHello.tiers,
            numberOfComponents: scenario.serverHello.numberOfComponents,
            componentFeeRateSatoshisPerKb: UInt64.max,
            minimumExcessFeeSatoshis: scenario.serverHello.minimumExcessFeeSatoshis,
            maximumExcessFeeSatoshis: scenario.serverHello.maximumExcessFeeSatoshis,
            donationAddress: scenario.serverHello.donationAddress
        )
        scenario.round = .init(
            fusionBegin: scenario.fusionBegin,
            serverHello: serverHello,
            deadlines: scenario.round.deadlines
        )
        scenario.round.startRound = startRound
        scenario.round.identifier = identifier
        scenario.round.participantReservation = participantReservation

        do {
            _ = try scenario.workflow.buildPlayerCommit(round: &scenario.round)
            Issue.record("Expected impossible coordinator fee rate to fail")
        } catch let error as OpalFusion.Execution.WorkflowFailure {
            #expect(
                error == .protocolValidationFailed(
                    "Coordinator component fee rate was too large"
                )
            )
        }
    }

    @Test("Production workflow clamps impossible dust-limit inputs without trapping")
    func validateDustLimitOverflowClampsToMaximum() {
        #expect(
            OpalFusion.Execution.ProtocolPrimitives.dustLimit(
                lockingScriptLength: Int.max
            ) == UInt64.max
        )
        #expect(
            OpalFusion.Execution.ProtocolPrimitives.dustLimit(
                lockingScriptLength: -1
            ) == UInt64.max
        )
    }

    @Test("Production workflow encodes long session-hash script pushes with PUSHDATA opcodes")
    func validateLongSessionHashScriptPushEncoding() {
        let longLokad = [UInt8](repeating: 0xAA, count: 76)
        let longSessionHash = [UInt8](repeating: 0xBB, count: 76)
        let baseline = OpalFusion.Transport.BaselineConfiguration(
            protocolIdentity: .init(
                versionBytes: [0x01],
                fusionLokadId: longLokad,
                minimumOutputAmountSatoshis: 10_000
            ),
            framing: ProductionWorkflowTestFixtures.baseline.framing,
            covertTiming: ProductionWorkflowTestFixtures.baseline.covertTiming,
            roundTiming: ProductionWorkflowTestFixtures.baseline.roundTiming
        )

        let script = OpalFusion.Execution.ProtocolPrimitives.makeSessionHashLockingScript(
            sessionHash: longSessionHash,
            baseline: baseline
        )

        #expect(script == [0x6A, 0x4C, 76] + longLokad + [0x4C, 76] + longSessionHash)
    }
}

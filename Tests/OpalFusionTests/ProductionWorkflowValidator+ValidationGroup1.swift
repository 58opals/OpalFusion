// ProductionWorkflowValidator+ValidationGroup1.swift

@testable import OpalFusion
import Foundation
import OpalCrypto
import Testing

extension ProductionWorkflowValidator {
    @Test("Production workflow builds a real PlayerCommit from participant reservation")
    func validatePlayerCommitMaterialization() throws {
        var scenario = try ProductionWorkflowTestFixtures.makeScenario()

        let playerCommit = try scenario.buildPlayerCommit()

        guard let material = scenario.round.executionMaterial.playerCommitMaterial else {
            Issue.record("Expected player-commit material to be cached in round context")
            return
        }

        #expect(playerCommit.initialCommitments.count == 3)
        #expect(playerCommit.blindSignatureRequests.count == 3)
        #expect(material.componentsByCommitmentOrder.count == 3)
        #expect(
            material.componentsByCommitmentOrder.contains { component in
                if case .blank = component.payload {
                    return true
                }
                return false
            }
        )
        #expect(
            playerCommit.randomNumberCommitment
                == OpalFusion.Execution.ProtocolPrimitives.sha256(material.randomNumber)
        )
        let expectedPedersenTotalNonce = try OpalFusion.Execution.ProtocolPrimitives
            .sumNoncesModOrder(
                material.componentsByCommitmentOrder.map(\.proofMaterial.pedersenNonce)
            )
        #expect(
            playerCommit.pedersenTotalNonce == expectedPedersenTotalNonce
        )
        #expect(
            playerCommit.excessFeeSatoshis >= scenario.serverHello.minimumExcessFeeSatoshis
        )
        #expect(
            playerCommit.excessFeeSatoshis <= scenario.serverHello.maximumExcessFeeSatoshis
        )
    }

    @Test("Production workflow reduces Pedersen nonce sums after carry folding")
    func validatePedersenNonceSumReducesFoldedCarry() throws {
        var orderMinusOne = Scalar256Value.order.bytes32
        orderMinusOne[31] -= 1
        let maximumNonce = [UInt8](repeating: 0xFF, count: 32)
        var expected = Scalar256Value.twoTo256MinusOrder.bytes32
        expected[31] -= 2

        let sum = try OpalFusion.Execution.ProtocolPrimitives.sumNoncesModOrder(
            [orderMinusOne, maximumNonce]
        )

        #expect(sum == expected)
    }

    @Test("Production workflow rejects invalid secure-random byte counts without trapping")
    func validateRandomBytesRejectsNegativeCounts() throws {
        do {
            _ = try OpalFusion.Execution.ProtocolPrimitives.randomBytes(count: -1)
            Issue.record("Expected negative secure-random byte count to fail")
        } catch let error as OpalFusion.Execution.WorkflowFailure {
            #expect(
                error == .unsupportedExecution(
                    "Secure random byte count must not be negative"
                )
            )
        }
    }

    @Test("Production workflow rejects invalid StartRound signing keys")
    func validateStartRoundRejectsInvalidBlindSigningKeys() throws {
        let invalidCompressedPublicKey = [UInt8](arrayLiteral: 0x02)
            + [UInt8](repeating: 0x00, count: 32)

        do {
            var scenario = try ProductionWorkflowTestFixtures.makeScenario()
            scenario.round.startRound = .init(
                roundPublicKey: invalidCompressedPublicKey,
                blindNoncePoints: scenario.startRound.blindNoncePoints,
                serverTimeUnixSeconds: scenario.startRound.serverTimeUnixSeconds
            )
            _ = try scenario.workflow.buildPlayerCommit(round: &scenario.round)
            Issue.record("Expected invalid round public key to fail")
        } catch let error as OpalFusion.Execution.WorkflowFailure {
            #expect(
                error == .protocolValidationFailed(
                    "StartRound round public key must be a valid compressed public key"
                )
            )
        }

        do {
            var scenario = try ProductionWorkflowTestFixtures.makeScenario()
            var blindNoncePoints = scenario.startRound.blindNoncePoints
            blindNoncePoints[0] = invalidCompressedPublicKey
            scenario.round.startRound = .init(
                roundPublicKey: scenario.startRound.roundPublicKey,
                blindNoncePoints: blindNoncePoints,
                serverTimeUnixSeconds: scenario.startRound.serverTimeUnixSeconds
            )
            _ = try scenario.workflow.buildPlayerCommit(round: &scenario.round)
            Issue.record("Expected invalid blind nonce point to fail")
        } catch let error as OpalFusion.Execution.WorkflowFailure {
            #expect(
                error == .protocolValidationFailed(
                    "StartRound blind nonce point at index 0 must be a valid compressed public key"
                )
            )
        }
    }
}

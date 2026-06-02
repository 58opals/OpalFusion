// ProductionWorkflowValidator+ValidationGroup6.swift

@testable import OpalFusion
import Foundation
import OpalCrypto
import Testing

extension ProductionWorkflowValidator {
    @Test("Production workflow rejects shared input components with invalid public keys")
    func validateSharedInputComponentRejectsInvalidPublicKey() throws {
        var scenario = try ProductionWorkflowTestFixtures.makeScenario()
        let playerCommit = try scenario.buildPlayerCommit()

        let serializedComponent = try Self.serializedComponent(
            saltCommitment: Self.saltCommitment(0xB0),
            payload: .input(
                .init(
                    outpointTransactionHash: [UInt8](repeating: 0xCC, count: 32),
                    outpointIndex: 2,
                    publicKey: [UInt8](arrayLiteral: 0x02) + [UInt8](repeating: 0x00, count: 32),
                    amountSatoshis: 60_000
                )
            )
        )

        try scenario.useSharedRound(
            allCommitments: playerCommit.initialCommitments + [
                .init(
                    saltedComponentHash: [0xB1],
                    amountCommitment: [0xB2],
                    communicationPublicKey: [0xB3]
                )
            ],
            serializedComponents: scenario.makeLocalSerializedComponents()
                + [serializedComponent]
        )

        do {
            _ = try scenario.workflow.buildTransactionFinalizationProposal(round: &scenario.round)
            Issue.record("Expected invalid shared input public key to fail")
        } catch let error as OpalFusion.Execution.WorkflowFailure {
            #expect(
                error == .protocolValidationFailed(
                    "Shared input component at index 3 must provide a valid compressed public key"
                )
            )
        }
    }

    @Test("Production workflow rejects shared input components with short previous hashes")
    func validateSharedInputComponentRejectsShortPreviousHash() throws {
        var scenario = try ProductionWorkflowTestFixtures.makeScenario()
        let playerCommit = try scenario.buildPlayerCommit()

        guard let publicKey = scenario.reservation.inputs[0].publicKey else {
            Issue.record("Expected fixture public key")
            return
        }

        let serializedComponent = try Self.serializedComponent(
            saltCommitment: Self.saltCommitment(0xC0),
            payload: .input(
                .init(
                    outpointTransactionHash: [UInt8](repeating: 0xCC, count: 31),
                    outpointIndex: 2,
                    publicKey: publicKey,
                    amountSatoshis: 60_000
                )
            )
        )

        try scenario.useSharedRound(
            allCommitments: playerCommit.initialCommitments + [
                .init(
                    saltedComponentHash: [0xC1],
                    amountCommitment: [0xC2],
                    communicationPublicKey: [0xC3]
                )
            ],
            serializedComponents: scenario.makeLocalSerializedComponents()
                + [serializedComponent]
        )

        do {
            _ = try scenario.workflow.buildTransactionFinalizationProposal(round: &scenario.round)
            Issue.record("Expected short previous transaction hash to fail")
        } catch let error as OpalFusion.Execution.WorkflowFailure {
            #expect(
                error == .protocolValidationFailed(
                    "Shared input component at index 3 previous transaction hash must be 32 bytes"
                )
            )
        }
    }

    @Test("Production workflow rejects duplicate shared input outpoints")
    func validateSharedInputComponentRejectsDuplicateOutpoint() throws {
        var scenario = try ProductionWorkflowTestFixtures.makeScenario()
        let playerCommit = try scenario.buildPlayerCommit()

        guard let publicKey = scenario.reservation.inputs[0].publicKey else {
            Issue.record("Expected fixture public key")
            return
        }

        let serializedComponent = try Self.serializedComponent(
            saltCommitment: Self.saltCommitment(0xC8),
            payload: .input(
                .init(
                    outpointTransactionHash: scenario.reservation.inputs[0].outpointTransactionHashBytes,
                    outpointIndex: scenario.reservation.inputs[0].outpointIndex,
                    publicKey: publicKey,
                    amountSatoshis: scenario.reservation.inputs[0].amountSatoshis
                )
            )
        )

        try scenario.useSharedRound(
            allCommitments: playerCommit.initialCommitments + [
                .init(
                    saltedComponentHash: [0xC9],
                    amountCommitment: [0xCA],
                    communicationPublicKey: [0xCB]
                )
            ],
            serializedComponents: scenario.makeLocalSerializedComponents()
                + [serializedComponent]
        )

        do {
            _ = try scenario.workflow.buildTransactionFinalizationProposal(round: &scenario.round)
            Issue.record("Expected duplicate shared input outpoint to fail")
        } catch let error as OpalFusion.Execution.WorkflowFailure {
            #expect(
                error == .protocolValidationFailed(
                    "Coordinator returned duplicate input outpoints"
                )
            )
        }
    }
}

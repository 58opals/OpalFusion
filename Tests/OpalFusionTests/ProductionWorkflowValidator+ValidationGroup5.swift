// ProductionWorkflowValidator+ValidationGroup5.swift

@testable import OpalFusion
import Foundation
import OpalCrypto
import Testing

extension ProductionWorkflowValidator {
    @Test("Production workflow rejects shared output components above the BCH money supply")
    func validateSharedOutputComponentRejectsImpossibleAmount() throws {
        var scenario = try ProductionWorkflowTestFixtures.makeScenario()
        let playerCommit = try scenario.buildPlayerCommit()

        let serializedComponent = try Self.serializedComponent(
            saltCommitment: Self.saltCommitment(0xA0),
            payload: .output(
                .init(
                    lockingScript: [0x51],
                    amountSatoshis: OpalFusion.Execution.ProtocolPrimitives.maximumMoneySatoshis + 1
                )
            )
        )

        try scenario.useSharedRound(
            allCommitments: playerCommit.initialCommitments + [
                .init(
                    saltedComponentHash: [0xA1],
                    amountCommitment: [0xA2],
                    communicationPublicKey: [0xA3]
                )
            ],
            serializedComponents: scenario.makeLocalSerializedComponents()
                + [serializedComponent]
        )

        do {
            _ = try scenario.workflow.buildTransactionFinalizationProposal(round: &scenario.round)
            Issue.record("Expected impossible shared output amount to fail")
        } catch let error as OpalFusion.Execution.WorkflowFailure {
            #expect(
                error == .protocolValidationFailed(
                    "Shared output component at index 3 exceeds the maximum BCH money supply"
                )
            )
        }
    }

    @Test("Production workflow rejects shared output components below the minimum amount")
    func validateSharedOutputComponentRejectsDustAmount() throws {
        var scenario = try ProductionWorkflowTestFixtures.makeScenario()
        let playerCommit = try scenario.buildPlayerCommit()

        let serializedComponent = try Self.serializedComponent(
            saltCommitment: Self.saltCommitment(0xD0),
            payload: .output(
                .init(
                    lockingScript: [0x51],
                    amountSatoshis: 1
                )
            )
        )

        try scenario.useSharedRound(
            allCommitments: playerCommit.initialCommitments + [
                .init(
                    saltedComponentHash: [0xD1],
                    amountCommitment: [0xD2],
                    communicationPublicKey: [0xD3]
                )
            ],
            serializedComponents: scenario.makeLocalSerializedComponents()
                + [serializedComponent]
        )

        do {
            _ = try scenario.workflow.buildTransactionFinalizationProposal(round: &scenario.round)
            Issue.record("Expected dust shared output to fail")
        } catch let error as OpalFusion.Execution.WorkflowFailure {
            #expect(
                error == .protocolValidationFailed(
                    "Shared output component at index 3 is below the minimum allowed amount"
                )
            )
        }
    }

    @Test("Production workflow rejects shared component count mismatches")
    func validateSharedComponentCountMustMatchCommitments() throws {
        var scenario = try ProductionWorkflowTestFixtures.makeScenario()
        let playerCommit = try scenario.buildPlayerCommit()

        let extraComponent = try Self.serializedComponent(
            saltCommitment: Self.saltCommitment(0xE0),
            payload: .blank(.init())
        )

        try scenario.useSharedRound(
            allCommitments: playerCommit.initialCommitments,
            serializedComponents: scenario.makeLocalSerializedComponents()
                + [extraComponent]
        )

        do {
            _ = try scenario.workflow.buildTransactionFinalizationProposal(round: &scenario.round)
            Issue.record("Expected shared component count mismatch to fail")
        } catch let error as OpalFusion.Execution.WorkflowFailure {
            #expect(
                error == .protocolValidationFailed(
                    "Coordinator returned a different number of shared components than commitments"
                )
            )
        }
    }

    @Test("Production workflow rejects shared components with short salt commitments")
    func validateSharedComponentRejectsShortSaltCommitment() throws {
        var scenario = try ProductionWorkflowTestFixtures.makeScenario()
        let playerCommit = try scenario.buildPlayerCommit()

        let serializedComponent = try Self.serializedComponent(
            saltCommitment: [0xE1],
            payload: .blank(.init())
        )

        try scenario.useSharedRound(
            allCommitments: playerCommit.initialCommitments + [
                .init(
                    saltedComponentHash: [0xE2],
                    amountCommitment: [0xE3],
                    communicationPublicKey: [0xE4]
                )
            ],
            serializedComponents: scenario.makeLocalSerializedComponents()
                + [serializedComponent]
        )

        do {
            _ = try scenario.workflow.buildTransactionFinalizationProposal(round: &scenario.round)
            Issue.record("Expected short salt commitment to fail")
        } catch let error as OpalFusion.Execution.WorkflowFailure {
            #expect(
                error == .protocolValidationFailed(
                    "Shared component at index 3 salt commitment must be 32 bytes"
                )
            )
        }
    }

    @Test("Production workflow maps impossible transaction template totals")
    func validateTransactionFinalizationProposalRejectsImpossibleOutputTotal() throws {
        var scenario = try ProductionWorkflowTestFixtures.makeScenario()
        let playerCommit = try scenario.buildPlayerCommit()

        let serializedComponent = try Self.serializedComponent(
            saltCommitment: Self.saltCommitment(0xF0),
            payload: .output(
                .init(
                    lockingScript: [0x51],
                    amountSatoshis: OpalFusion.Execution.ProtocolPrimitives.maximumMoneySatoshis
                )
            )
        )

        try scenario.useSharedRound(
            allCommitments: playerCommit.initialCommitments + [
                .init(
                    saltedComponentHash: [0xF1],
                    amountCommitment: [0xF2],
                    communicationPublicKey: [0xF3]
                )
            ],
            serializedComponents: scenario.makeLocalSerializedComponents()
                + [serializedComponent]
        )

        do {
            _ = try scenario.workflow.buildTransactionFinalizationProposal(round: &scenario.round)
            Issue.record("Expected impossible transaction template total to fail")
        } catch let error as OpalFusion.Execution.WorkflowFailure {
            #expect(
                error == .protocolValidationFailed(
                    "Transaction output total exceeds the maximum BCH money supply"
                )
            )
        }
    }
}

// ProductionWorkflowValidator+ValidationGroup4.swift

@testable import OpalFusion
import Foundation
import OpalCrypto
import Testing

extension ProductionWorkflowValidator {
    @Test("Production workflow derives the unsigned template and extracts local signatures")
    func validateTransactionTemplateAndSignatureExtraction() async throws {
        var scenario = try ProductionWorkflowTestFixtures.makeScenario()
        let playerCommit = try scenario.buildPlayerCommit()
        _ = try await scenario.buildBlindSignatureResponses(for: playerCommit)

        let covertMessages = try scenario.workflow.buildCovertComponentMessages(round: &scenario.round)
        #expect(covertMessages.count == 3)

        try scenario.useSharedRound(
            allCommitments: playerCommit.initialCommitments,
            serializedComponents: try ProductionWorkflowTestFixtures
                .extractSerializedComponents(from: covertMessages)
        )

        let proposal = try scenario.workflow.buildTransactionFinalizationProposal(round: &scenario.round)
        #expect(proposal.participantCount == nil)
        let unsignedTransaction = try OpalFusion.Execution.BCHTransaction.parse(
            proposal.unsignedFusionTransactionBytes
        )

        #expect(unsignedTransaction.version == 1)
        #expect(unsignedTransaction.inputs.count == 1)
        #expect(unsignedTransaction.outputs.count == 2)
        #expect(unsignedTransaction.lockTime == 0)
        #expect(
            unsignedTransaction.outputs[0].lockingScript
                == OpalFusion.Execution.ProtocolPrimitives.makeSessionHashLockingScript(
                    sessionHash: proposal.sessionHash ?? [],
                    baseline: scenario.baseline
                )
        )
        #expect(
            unsignedTransaction.outputs[1].amountSatoshis
                == scenario.reservation.outputs[0].amountSatoshis
        )
        #expect(
            unsignedTransaction.outputs[1].lockingScript
                == scenario.reservation.outputs[0].lockingScriptBytes
        )

        let signingResult = try scenario.makeSignedFinalizedTransaction(proposal: proposal)
        scenario.round.finalizedTransaction = signingResult.transaction

        let signatureMessages = try scenario.workflow.buildCovertSignatureMessages(
            round: &scenario.round
        )
        #expect(signatureMessages.count == 1)

        guard case let .transactionSignature(signatureMessage) = signatureMessages[0] else {
            Issue.record("Expected a covert transaction signature message")
            return
        }
        #expect(signatureMessage.roundPublicKey == scenario.startRound.roundPublicKey)
        #expect(signatureMessage.inputIndex == 0)
        #expect(signatureMessage.transactionSignature == signingResult.signature)

        do {
            var mismatchedRound = scenario.round
            var mismatchedTransaction = unsignedTransaction
            mismatchedTransaction.outputs[1].amountSatoshis += 1
            mismatchedRound.finalizedTransaction = .init(
                signedFusionTransactionBytes: try mismatchedTransaction.serialize()
            )
            _ = try scenario.workflow.buildCovertSignatureMessages(round: &mismatchedRound)
            Issue.record("Expected mismatched finalized transaction to fail")
        } catch let error as OpalFusion.Execution.WorkflowFailure {
            #expect(
                error == .invalidTransactionTemplate(
                    "Finalized transaction outputs did not match the unsigned template"
                )
            )
        }

        do {
            var unsupportedRound = scenario.round
            let unsupportedSigningResult = try scenario.makeSignedFinalizedTransaction(
                proposal: proposal,
                unlockingScriptBuilder: { signature, publicKey in
                    [0x4C, 0x40] + signature + [0x21] + publicKey
                }
            )
            unsupportedRound.finalizedTransaction = unsupportedSigningResult.transaction
            _ = try scenario.workflow.buildCovertSignatureMessages(round: &unsupportedRound)
            Issue.record("Expected unsupported unlocking script to fail")
        } catch let error as OpalFusion.Execution.WorkflowFailure {
            #expect(
                error == .unsupportedExecution(
                    OpalFusion.Execution.ProtocolPrimitives.supportedUnlockingScriptSummary
                )
            )
        }
    }

    @Test("Production workflow preserves coordinator input order when extracting local signatures")
    func validateTransactionTemplatePreservesCoordinatorInputOrder() async throws {
        var scenario = try ProductionWorkflowTestFixtures.makeTwoInputScenario()
        let playerCommit = try scenario.buildPlayerCommit()
        _ = try await scenario.buildBlindSignatureResponses(for: playerCommit)
        _ = try scenario.workflow.buildCovertComponentMessages(round: &scenario.round)

        guard let material = scenario.round.executionMaterial.playerCommitMaterial else {
            Issue.record("Expected player-commit material to be cached in round context")
            return
        }
        let componentsByOriginalSlot = Dictionary(
            uniqueKeysWithValues: material.componentsByCommitmentOrder.map {
                ($0.originalSlot, $0)
            }
        )
        guard let firstReservationInputComponent = componentsByOriginalSlot[0],
              let secondReservationInputComponent = componentsByOriginalSlot[1],
              let outputComponent = componentsByOriginalSlot[2],
              let blankComponent = componentsByOriginalSlot[3] else {
            Issue.record("Expected two inputs, one output, and one blank component")
            return
        }

        try scenario.useSharedRound(
            allCommitments: playerCommit.initialCommitments,
            serializedComponents: [
                secondReservationInputComponent.serializedComponent,
                firstReservationInputComponent.serializedComponent,
                outputComponent.serializedComponent,
                blankComponent.serializedComponent,
            ]
        )

        let proposal = try scenario.workflow.buildTransactionFinalizationProposal(
            round: &scenario.round
        )
        let unsignedTransaction = try OpalFusion.Execution.BCHTransaction.parse(
            proposal.unsignedFusionTransactionBytes
        )

        #expect(unsignedTransaction.inputs.count == 2)
        #expect(
            unsignedTransaction.inputs[0].previousTransactionHashLittleEndian ==
                Array(scenario.reservation.inputs[1].outpointTransactionHashBytes.reversed())
        )
        #expect(
            unsignedTransaction.inputs[1].previousTransactionHashLittleEndian ==
                Array(scenario.reservation.inputs[0].outpointTransactionHashBytes.reversed())
        )

        let signingResult = try ProductionWorkflowTestFixtures.makeSignedFinalizedTransaction(
            proposal: proposal,
            participantInputs: scenario.reservation.inputs,
            participantInputPrivateKeys: scenario.participantInputPrivateKeys
        )
        scenario.round.finalizedTransaction = signingResult.transaction

        let signatureMessages = try scenario.workflow.buildCovertSignatureMessages(
            round: &scenario.round
        )
        var signaturePayloads: [OpalFusion.ProtocolModel.CovertTransactionSignature] = []
        for message in signatureMessages {
            guard case let .transactionSignature(payload) = message else {
                Issue.record("Expected a covert transaction signature message")
                return
            }
            signaturePayloads.append(payload)
        }

        #expect(signaturePayloads.map(\.inputIndex) == [UInt32(1), UInt32(0)])
        #expect(
            signaturePayloads.map(\.transactionSignature)
                == signingResult.signaturesByReservationInputIndex
        )
        #expect(
            signingResult.transactionInputIndicesByReservationInputIndex == [1, 0]
        )
    }
}

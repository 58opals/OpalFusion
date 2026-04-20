// ProductionWorkflowValidator.swift

@testable import OpalFusion
import Foundation
import OpalCrypto
import SwiftProtobuf
import Testing

struct ProductionWorkflowValidator {
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
    }

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
            proposal.unsignedTransactionBytes
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
                transactionBytes: try mismatchedTransaction.serialized()
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

    @Test("Production workflow generates decryptable proofs and blame outputs")
    func validateProofGenerationAndBlameMaterialization() throws {
        var scenario = try ProductionWorkflowTestFixtures.makeScenario()
        let playerCommit = try scenario.buildPlayerCommit()
        let extraInputComponent = try scenario.makeExternalInputComponent()

        try scenario.useSharedRound(
            allCommitments: playerCommit.initialCommitments + [extraInputComponent.initialCommitment],
            serializedComponents: scenario.localSerializedComponents() + [extraInputComponent.serializedComponent]
        )

        let myProofsList = try scenario.workflow.buildMyProofsList(round: &scenario.round)
        guard let playerCommitMaterial = scenario.round.executionMaterial.playerCommitMaterial else {
            Issue.record("Expected cached player-commit material before proof generation")
            return
        }
        guard let sharedRoundMaterial = scenario.round.executionMaterial.sharedRoundMaterial else {
            Issue.record("Expected cached shared-round material before proof generation")
            return
        }

        #expect(myProofsList.randomNumber == playerCommitMaterial.randomNumber)
        #expect(myProofsList.encryptedProofs.count == playerCommitMaterial.componentsByCommitmentOrder.count)

        let decryptedProof = try OpalCrypto.Communication.decrypt(
            Data(myProofsList.encryptedProofs[0]),
            privateKey: Data(extraInputComponent.communicationPrivateKey)
        )
        let parsedProof = try Fusion_Proof(serializedBytes: decryptedProof.message)
        #expect(sharedRoundMaterial.myComponentIndices.contains(Int(parsedProof.componentIdx)))

        let destinationComponent = playerCommitMaterial.componentsByCommitmentOrder[0]
        let invalidEncryptedProof = try Array(
            OpalCrypto.Communication.encrypt(
                message: Data([0x00]),
                recipientPublicKey: Data(destinationComponent.initialCommitment.communicationPublicKey)
            )
        )
        let validEncryptedProof = try ProductionWorkflowTestFixtures.encryptProof(
            componentIndex: sharedRoundMaterial.allComponentBytes.count - 1,
            salt: extraInputComponent.salt,
            pedersenNonce: extraInputComponent.pedersenNonce,
            recipientPublicKey: destinationComponent.initialCommitment.communicationPublicKey
        )

        scenario.round.fusionResult = .init(
            isSuccess: false,
            transactionSignatures: [],
            badComponentIndices: []
        )
        scenario.round.theirProofsList = .init(
            proofs: [
                .init(
                    encryptedProof: invalidEncryptedProof,
                    sourceCommitmentIndex: UInt32(sharedRoundMaterial.allCommitmentBytes.count - 1),
                    destinationKeyIndex: 0
                ),
                .init(
                    encryptedProof: validEncryptedProof,
                    sourceCommitmentIndex: UInt32(sharedRoundMaterial.allCommitmentBytes.count - 1),
                    destinationKeyIndex: 0
                )
            ]
        )

        let blames = try scenario.workflow.buildBlames(round: &scenario.round)
        #expect(blames.blames.count == 2)
        #expect(blames.blames[0].requiresBlockchainLookup == false)
        #expect(blames.blames[0].reason == "proof decode failed")
        if case let .sessionKey(sessionKey) = blames.blames[0].decrypter {
            #expect(sessionKey.count == 32)
        } else {
            Issue.record("Expected invalid proof blame to carry a session key")
        }
        #expect(blames.blames[1].requiresBlockchainLookup == true)
        #expect(blames.blames[1].reason == "input requires blockchain lookup")
        if case let .sessionKey(sessionKey) = blames.blames[1].decrypter {
            #expect(sessionKey.count == 32)
        } else {
            Issue.record("Expected input proof blame to carry a session key")
        }
    }
}

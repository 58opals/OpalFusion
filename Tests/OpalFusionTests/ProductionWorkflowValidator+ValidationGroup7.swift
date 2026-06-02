// ProductionWorkflowValidator+ValidationGroup7.swift

@testable import OpalFusion
import Foundation
import OpalCrypto
import Testing

extension ProductionWorkflowValidator {
    @Test("Production workflow generates decryptable proofs and blame outputs")
    func validateProofGenerationAndBlameMaterialization() throws {
        var scenario = try ProductionWorkflowTestFixtures.makeScenario()
        let playerCommit = try scenario.buildPlayerCommit()
        let extraInputComponent = try scenario.makeExternalInputComponent()

        try scenario.useSharedRound(
            allCommitments: playerCommit.initialCommitments + [extraInputComponent.initialCommitment],
            serializedComponents: scenario.makeLocalSerializedComponents() + [extraInputComponent.serializedComponent]
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
            OpalCrypto.Communication.Ciphertext(
                rawRepresentation: Data(myProofsList.encryptedProofs[0])
            ),
            privateKey: OpalCrypto.Secp256k1.PrivateKey(
                rawRepresentation: Data(extraInputComponent.communicationPrivateKey)
            )
        )
        let parsedProof = try OpalFusion.Wire.CashFusionProofCodec.decode(
            Array(decryptedProof.message)
        )
        #expect(sharedRoundMaterial.myComponentIndices.contains(Int(parsedProof.componentIndex)))

        let destinationComponent = playerCommitMaterial.componentsByCommitmentOrder[0]
        let invalidEncryptedProof = try Array(
            OpalCrypto.Communication.encrypt(
                message: Data([0x00]),
                recipientPublicKey: OpalCrypto.Secp256k1.PublicKey(
                    rawRepresentation: Data(
                        destinationComponent.initialCommitment.communicationPublicKey
                    )
                )
            ).rawRepresentation
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

        let decodedSubmission = try OpalFusion.Wire.PrimaryMessageDecoder().decodeClient(
            OpalFusion.Wire.PrimaryMessageEncoder().encode(
                OpalFusion.ProtocolModel.ClientMessage.blames(blames)
            )
        )
        guard case let .blames(decodedBlames) = decodedSubmission else {
            Issue.record("Expected decoded production blame submission")
            return
        }
        #expect(decodedBlames.blames[0].requiresBlockchainLookup == false)
        #expect(decodedBlames.blames[1].requiresBlockchainLookup == true)
    }

    @Test("Production workflow fails proof generation when a destination communication key is invalid")
    func validateProofGenerationRejectsInvalidDestinationCommunicationKey() throws {
        var scenario = try ProductionWorkflowTestFixtures.makeScenario()
        let playerCommit = try scenario.buildPlayerCommit()
        let externalComponent = try scenario.makeExternalInputComponent()
        let invalidCommunicationPublicKey = [UInt8](arrayLiteral: 0x02)
            + [UInt8](repeating: 0x00, count: 32)
        let invalidExternalCommitment = OpalFusion.Commitment.InitialCommitment(
            saltedComponentHash: externalComponent.initialCommitment.saltedComponentHash,
            amountCommitment: externalComponent.initialCommitment.amountCommitment,
            communicationPublicKey: invalidCommunicationPublicKey
        )
        try scenario.useSharedRound(
            allCommitments: playerCommit.initialCommitments + [invalidExternalCommitment],
            serializedComponents: scenario.makeLocalSerializedComponents()
                + [externalComponent.serializedComponent]
        )

        do {
            _ = try scenario.workflow.buildMyProofsList(round: &scenario.round)
            Issue.record("Expected invalid proof destination key to fail")
        } catch let error as OpalFusion.Execution.WorkflowFailure {
            guard case let .protocolValidationFailed(summary) = error else {
                Issue.record("Expected protocol validation failure")
                return
            }
            #expect(summary.hasPrefix("Proof encryption failed"))
        }
    }
}

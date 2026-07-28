// OpalFusion+Execution+ProductionWorkflow+ImplementationGroup2.swift

import Foundation
import OpalCrypto
import OpalDiagnostics

extension OpalFusion.Execution.ProductionWorkflow {
    func buildBlames(
        round: inout OpalFusion.Execution.RoundContext
    ) throws -> OpalFusion.ProtocolModel.Blames {
        let playerCommitMaterial = try ensurePlayerCommitMaterial(round: &round)
        let sharedMaterial = try ensureSharedRoundMaterial(round: &round)
        guard let theirProofsList = round.theirProofsList else {
            throw OpalFusion.Execution.WorkflowFailure.protocolValidationFailed(
                "TheirProofsList must be present before blame construction"
            )
        }

        var blames: [OpalFusion.Blame.BlameProof] = []
        let badComponentIndices = Set(round.fusionResult?.badComponentIndices ?? [])

        for (proofIndex, relayedProof) in theirProofsList.proofs.enumerated() {
            let destinationIndex = Int(relayedProof.destinationKeyIndex)
            guard playerCommitMaterial.componentsByCommitmentOrder.indices.contains(destinationIndex) else {
                throw OpalFusion.Execution.WorkflowFailure.protocolValidationFailed(
                    "Coordinator relayed a proof with an invalid destination key index"
                )
            }
            let sourceCommitmentIndex = Int(relayedProof.sourceCommitmentIndex)
            guard sharedMaterial.allCommitmentBytes.indices.contains(sourceCommitmentIndex) else {
                throw OpalFusion.Execution.WorkflowFailure.protocolValidationFailed(
                    "Coordinator relayed a proof with an invalid source commitment index"
                )
            }

            let localComponent = playerCommitMaterial.componentsByCommitmentOrder[destinationIndex]
            let sourceCommitment = try parseInitialCommitment(
                bytes: sharedMaterial.allCommitmentBytes[sourceCommitmentIndex]
            )

            let decrypted: OpalCrypto.Communication.DecryptionResult
            do {
                decrypted = try OpalCrypto.Communication.decrypt(
                    OpalCrypto.Communication.Ciphertext(
                        rawRepresentation: Data(relayedProof.encryptedProof),
                        maximumCiphertextByteCount: OpalFusion.Execution.ProtocolPrimitives
                            .maximumEncryptedProofCiphertextByteCount
                    ),
                    privateKey: OpalCrypto.Secp256k1.PrivateKey(
                        rawRepresentation: Data(localComponent.communicationPrivateKey)
                    ),
                    maximumCiphertextByteCount: OpalFusion.Execution.ProtocolPrimitives
                        .maximumEncryptedProofCiphertextByteCount
                )
            } catch {
                recordBlameProofValidationFailure(
                    roundIdentifier: round.identifier,
                    fields: [
                        OpalDiagnostics.Field.operation("proof_decrypt")
                    ] + OpalDiagnostics.Field.errorFields(for: error)
                )
                blames.append(
                    .init(
                        proofIndex: UInt32(proofIndex),
                        decrypter: .privateKey(secretBytes: localComponent.communicationPrivateKey),
                        reason: "undecryptable"
                    )
                )
                continue
            }

            let validatedProof: OpalFusion.Execution.ValidatedProof
            do {
                validatedProof = try validateRelayedProof(
                    Array(decrypted.message),
                    sourceCommitment: sourceCommitment,
                    sharedRoundMaterial: sharedMaterial,
                    badComponentIndices: badComponentIndices,
                    feeRateSatoshisPerKb: round.serverHello.componentFeeRateSatoshisPerKb
                )
            } catch let error as OpalFusion.Execution.RelayedProofValidationFailure {
                recordBlameProofValidationFailure(
                    roundIdentifier: round.identifier,
                    fields: OpalDiagnostics.Field.sanitizedSummaryFields(
                        errorCode: .relayedProofValidationFailed,
                        summary: error.reason
                    ) + [
                        OpalDiagnostics.Field.operation("proof_validation")
                    ]
                )
                blames.append(
                    .init(
                        proofIndex: UInt32(proofIndex),
                        decrypter: .sessionKey(secretBytes: Array(decrypted.symmetricKey.rawRepresentation)),
                        requiresBlockchainLookup: false,
                        reason: error.reason
                    )
                )
                continue
            }

            if case .input = validatedProof {
                blames.append(
                    .init(
                        proofIndex: UInt32(proofIndex),
                        decrypter: .sessionKey(secretBytes: Array(decrypted.symmetricKey.rawRepresentation)),
                        requiresBlockchainLookup: true,
                        reason: "input requires blockchain lookup"
                    )
                )
            }
        }

        return .init(blames: blames)
    }

    func ensureCovertSignatureMessages(
        round: inout OpalFusion.Execution.RoundContext
    ) throws -> [OpalFusion.ProtocolModel.CovertMessage] {
        guard let finalizedTransaction = round.finalizedTransaction else {
            throw OpalFusion.Execution.WorkflowFailure.protocolValidationFailed(
                "Finalized transaction was missing for signature submission"
            )
        }
        if let cachedMessages = round.executionMaterial.covertSignatureMessages,
           round.executionMaterial.covertSignatureSourceTransaction ==
            finalizedTransaction.signedFusionTransactionBytes {
            return cachedMessages
        }

        let sharedMaterial = try ensureSharedRoundMaterial(round: &round)
        guard let startRound = round.startRound else {
            throw OpalFusion.Execution.WorkflowFailure.protocolValidationFailed(
                "StartRound must be present before signature submission"
            )
        }

        let parsedFinalizedTransaction: OpalFusion.Execution.BCHTransaction
        do {
            parsedFinalizedTransaction = try .parse(finalizedTransaction.signedFusionTransactionBytes)
        } catch let error as OpalFusion.Execution.BCHTransactionError {
            throw mapTransactionError(error)
        }

        do {
            try validateFinalizedTransaction(
                parsedFinalizedTransaction,
                against: sharedMaterial.transactionTemplate,
                localInputReferences: sharedMaterial.localInputReferences
            )
        } catch let error as OpalFusion.Execution.BCHTransactionError {
            throw mapTransactionError(error)
        }

        let messages: [OpalFusion.ProtocolModel.CovertMessage]
        do {
            messages = try sharedMaterial.localInputReferences
                .sorted(by: { $0.originalSlot < $1.originalSlot })
                .map { inputReference in
                    let signature = try extractLocalSignature(
                        from: parsedFinalizedTransaction.inputs[inputReference.transactionInputIndex],
                        transaction: parsedFinalizedTransaction,
                        inputReference: inputReference
                    )
                    return OpalFusion.ProtocolModel.CovertMessage.transactionSignature(
                        .init(
                            roundPublicKey: startRound.roundPublicKey,
                            inputIndex: UInt32(inputReference.transactionInputIndex),
                            transactionSignature: signature
                        )
                    )
                }
        } catch let error as OpalFusion.Execution.BCHTransactionError {
            throw mapTransactionError(error)
        }

        round.executionMaterial.covertSignatureMessages = messages
        round.executionMaterial.covertSignatureSourceTransaction =
            finalizedTransaction.signedFusionTransactionBytes
        return messages
    }
}

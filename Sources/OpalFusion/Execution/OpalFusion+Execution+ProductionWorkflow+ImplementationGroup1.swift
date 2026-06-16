// OpalFusion+Execution+ProductionWorkflow+ImplementationGroup1.swift

import Foundation
import OpalCrypto
import OpalDiagnostics

extension OpalFusion.Execution.ProductionWorkflow {
    func buildPlayerCommit(
        round: inout OpalFusion.Execution.RoundContext
    ) throws -> OpalFusion.ProtocolModel.PlayerCommit {
        let material = try ensurePlayerCommitMaterial(round: &round)
        let randomCommitment = OpalFusion.Execution.ProtocolPrimitives.sha256(
            material.randomNumber
        )
        let blindRequests = material.blindSignatureRequests.map {
            OpalFusion.BlindSignature.Request(scalar: Array($0.scalar.rawRepresentation))
        }
        return .init(
            initialCommitments: material.componentsByCommitmentOrder.map(\.initialCommitment),
            excessFeeSatoshis: material.excessFeeSatoshis,
            pedersenTotalNonce: material.pedersenTotalNonce,
            randomNumberCommitment: randomCommitment,
            blindSignatureRequests: blindRequests
        )
    }

    func buildCovertComponentMessages(
        round: inout OpalFusion.Execution.RoundContext
    ) throws -> [OpalFusion.ProtocolModel.CovertMessage] {
        let material = try ensurePlayerCommitMaterial(round: &round)
        guard let startRound = round.startRound else {
            throw OpalFusion.Execution.WorkflowFailure.protocolValidationFailed(
                "StartRound must be present before covert component submission"
            )
        }
        guard let responses = round.blindSignatureResponses else {
            throw OpalFusion.Execution.WorkflowFailure.protocolValidationFailed(
                "Blind signature responses were missing for covert component submission"
            )
        }
        guard responses.responses.count == material.blindSignatureRequests.count else {
            throw OpalFusion.Execution.WorkflowFailure.protocolValidationFailed(
                "Coordinator returned the wrong number of blind signature responses"
            )
        }

        let finalizedBlindSignatures: [[UInt8]]
        do {
            finalizedBlindSignatures = try zip(
                material.blindSignatureRequests,
                responses.responses
            ).map { request, response in
                try Array(
                    request.finalize(
                        responseScalar: try OpalCrypto.Secp256k1.Scalar(
                            rawRepresentation: Data(response.scalar)
                        ),
                        verify: true
                    ).rawRepresentation
                )
            }
        } catch {
            throw OpalFusion.Execution.WorkflowFailure.protocolValidationFailed(
                "Blind signature finalization failed"
            )
        }

        round.executionMaterial.finalizedBlindSignatures = finalizedBlindSignatures

        return zip(
            material.componentsByCommitmentOrder,
            finalizedBlindSignatures
        )
        .sorted { lhs, rhs in
            lhs.0.originalSlot < rhs.0.originalSlot
        }
        .map { component, blindSignature in
            .component(
                .init(
                    roundPublicKey: startRound.roundPublicKey,
                    signature: blindSignature,
                    serializedComponent: component.serializedComponent
                )
            )
        }
    }

    func buildTransactionFinalizationProposal(
        round: inout OpalFusion.Execution.RoundContext
    ) throws -> OpalFusion.Host.TransactionFinalizationProposal {
        let sharedMaterial = try ensureSharedRoundMaterial(round: &round)
        let unsignedFusionTransactionBytes: [UInt8]
        do {
            unsignedFusionTransactionBytes = try sharedMaterial.transactionTemplate.serialize()
        } catch let error as OpalFusion.Execution.BCHTransactionError {
            throw mapTransactionError(error)
        }
        return .init(
            unsignedFusionTransactionBytes: unsignedFusionTransactionBytes,
            sessionHash: sharedMaterial.sessionHash,
            expectedInputCount: sharedMaterial.transactionTemplate.inputs.count,
            expectedOutputCount: sharedMaterial.transactionTemplate.outputs.count,
            participantCount: nil
        )
    }

    func buildCovertSignatureMessages(
        round: inout OpalFusion.Execution.RoundContext
    ) throws -> [OpalFusion.ProtocolModel.CovertMessage] {
        try ensureCovertSignatureMessages(round: &round)
    }

    func buildMyProofsList(
        round: inout OpalFusion.Execution.RoundContext
    ) throws -> OpalFusion.ProtocolModel.MyProofsList {
        let playerCommitMaterial = try ensurePlayerCommitMaterial(round: &round)
        let sharedMaterial = try ensureSharedRoundMaterial(round: &round)

        let othersCommitmentIndices = sharedMaterial.allCommitmentBytes.indices.filter {
            sharedMaterial.myCommitmentIndices.contains($0) == false
        }
        guard othersCommitmentIndices.isEmpty == false else {
            throw OpalFusion.Execution.WorkflowFailure.protocolValidationFailed(
                "Blame handling requires commitments from other participants"
            )
        }

        let encryptedProofs = try playerCommitMaterial.componentsByCommitmentOrder.enumerated().map {
            index, component in
            let destinationCommitmentIndex = othersCommitmentIndices[
                OpalFusion.Execution.ProtocolPrimitives.randPosition(
                    seed: playerCommitMaterial.randomNumber,
                    numberOfPositions: othersCommitmentIndices.count,
                    counter: index
                )
            ]
            let destinationCommitment = try parseInitialCommitment(
                bytes: sharedMaterial.allCommitmentBytes[destinationCommitmentIndex]
            )
            let proof = try serializeProof(
                componentIndex: UInt32(sharedMaterial.myComponentIndices[index]),
                salt: component.proofMaterial.salt,
                pedersenNonce: component.proofMaterial.pedersenNonce
            )
            do {
                return Array(
                    try OpalCrypto.Communication.encrypt(
                        message: Data(proof),
                        recipientPublicKey: OpalCrypto.Secp256k1.PublicKey(
                            rawRepresentation: Data(destinationCommitment.communicationPublicKey)
                        ),
                        paddedPlaintextLength: 80
                    ).rawRepresentation
                )
            } catch {
                throw OpalFusion.Execution.WorkflowFailure.protocolValidationFailed(
                    "Proof encryption failed"
                )
            }
        }

        return .init(
            encryptedProofs: encryptedProofs,
            randomNumber: playerCommitMaterial.randomNumber
        )
    }
}

// OpalFusion+Execution+ProductionWorkflow+ImplementationGroup4.swift

import Foundation
import OpalCrypto
import OpalDiagnostics

extension OpalFusion.Execution.ProductionWorkflow {
    func ensureSharedRoundMaterial(
        round: inout OpalFusion.Execution.RoundContext
    ) throws -> OpalFusion.Execution.SharedRoundMaterial {
        if let sharedRoundMaterial = round.executionMaterial.sharedRoundMaterial {
            return sharedRoundMaterial
        }

        let playerCommitMaterial = try ensurePlayerCommitMaterial(round: &round)
        guard let startRound = round.startRound,
              let allCommitments = round.allCommitments,
              let sharedComponents = round.sharedComponents,
              let reservation = round.participantReservation else {
            throw OpalFusion.Execution.WorkflowFailure.protocolValidationFailed(
                "Round data was incomplete for shared component validation"
            )
        }

        let allCommitmentBytes = try allCommitments.initialCommitments.map(serializeInitialCommitment)
        guard Self.hasDuplicateByteArrays(allCommitmentBytes) == false else {
            throw OpalFusion.Execution.WorkflowFailure.protocolValidationFailed(
                "Coordinator returned duplicate initial commitments"
            )
        }
        let myCommitmentIndices = try playerCommitMaterial.componentsByCommitmentOrder.map { component in
            guard let index = allCommitmentBytes.firstIndex(of: component.serializedInitialCommitment) else {
                throw OpalFusion.Execution.WorkflowFailure.protocolValidationFailed(
                    "Coordinator omitted one of the local commitments"
                )
            }
            return index
        }

        let allComponentBytes = sharedComponents.serializedComponents
        guard allComponentBytes.count == allCommitmentBytes.count else {
            throw OpalFusion.Execution.WorkflowFailure.protocolValidationFailed(
                "Coordinator returned a different number of shared components than commitments"
            )
        }

        guard Self.hasDuplicateByteArrays(allComponentBytes) == false else {
            throw OpalFusion.Execution.WorkflowFailure.protocolValidationFailed(
                "Coordinator returned duplicate shared components"
            )
        }
        let myComponentIndices = try playerCommitMaterial.componentsByCommitmentOrder.map { component in
            guard let index = allComponentBytes.firstIndex(of: component.serializedComponent) else {
                throw OpalFusion.Execution.WorkflowFailure.protocolValidationFailed(
                    "Coordinator omitted one of the local components"
                )
            }
            return index
        }

        let decodedComponents = try allComponentBytes.enumerated().map {
            try decodeComponent(bytes: $0.element, componentIndex: $0.offset)
        }
        let previousHash = OpalFusion.Execution.ProtocolPrimitives.calculateInitialHash(
            fusionBegin: round.fusionBegin,
            baseline: baseline
        )
        let sessionHash = OpalFusion.Execution.ProtocolPrimitives.calculateRoundHash(
            previousHash: previousHash,
            startRound: startRound,
            allCommitmentBytes: allCommitmentBytes,
            allComponentBytes: allComponentBytes
        )
        if let sharedSessionHash = sharedComponents.sessionHash, sharedSessionHash != sessionHash {
            throw OpalFusion.Execution.WorkflowFailure.protocolValidationFailed(
                "Coordinator returned a mismatched session hash"
            )
        }

        let (transactionTemplate, transactionInputComponentIndices) = try makeTransactionTemplate(
            decodedComponents: decodedComponents,
            sessionHash: sessionHash
        )
        let localInputReferences = try makeLocalInputReferences(
            reservation: reservation,
            playerCommitMaterial: playerCommitMaterial,
            myComponentIndices: myComponentIndices,
            transactionInputComponentIndices: transactionInputComponentIndices
        )
        let material = OpalFusion.Execution.SharedRoundMaterial(
            allCommitmentBytes: allCommitmentBytes,
            allComponentBytes: allComponentBytes,
            sessionHash: sessionHash,
            decodedComponents: decodedComponents,
            myCommitmentIndices: myCommitmentIndices,
            myComponentIndices: myComponentIndices,
            transactionTemplate: transactionTemplate,
            transactionInputComponentIndices: transactionInputComponentIndices,
            localInputReferences: localInputReferences
        )
        round.executionMaterial.sharedRoundMaterial = material
        round.executionMaterial.covertSignatureMessages = nil
        round.executionMaterial.covertSignatureSourceTransaction = nil
        return material
    }

    func buildComponentMaterial(
        originalSlot: Int,
        payload: OpalFusion.Commitment.ComponentPayload,
        contributionSatoshis: Int64
    ) throws -> OpalFusion.Execution.LocalComponentMaterial {
        let salt = try OpalFusion.Execution.ProtocolPrimitives.randomBytes(count: 32)
        let serializedComponent = try serializeComponent(
            payload: payload,
            saltCommitment: OpalFusion.Execution.ProtocolPrimitives.sha256(salt)
        )
        let pedersenCommitment: OpalCrypto.Pedersen.Commitment
        do {
            pedersenCommitment = try pedersenSetup.commit(amount: contributionSatoshis)
        } catch {
            throw OpalFusion.Execution.WorkflowFailure.protocolValidationFailed(
                "Pedersen commitment construction failed"
            )
        }
        let communicationPrivateKey: OpalCrypto.Secp256k1.PrivateKey
        let communicationPublicKey: OpalCrypto.Secp256k1.PublicKey
        do {
            communicationPrivateKey = try OpalCrypto.Secp256k1.PrivateKey.generate()
            communicationPublicKey = try OpalCrypto.Secp256k1
                .derivePublicKey(from: communicationPrivateKey)
        } catch {
            throw OpalFusion.Execution.WorkflowFailure.unsupportedExecution(
                "Communication key generation failed"
            )
        }

        let initialCommitment = OpalFusion.Commitment.InitialCommitment(
            saltedComponentHash: OpalFusion.Execution.ProtocolPrimitives.sha256(
                salt + serializedComponent
            ),
            amountCommitment: Array(pedersenCommitment.point.uncompressedRepresentation),
            communicationPublicKey: Array(communicationPublicKey.rawRepresentation)
        )
        return .init(
            originalSlot: originalSlot,
            payload: payload,
            serializedComponent: serializedComponent,
            serializedInitialCommitment: try serializeInitialCommitment(initialCommitment),
            initialCommitment: initialCommitment,
            proofMaterial: .init(
                salt: salt,
                pedersenNonce: Array(pedersenCommitment.nonce.rawRepresentation)
            ),
            communicationPrivateKey: Array(communicationPrivateKey.rawRepresentation),
            contributionSatoshis: contributionSatoshis
        )
    }
}

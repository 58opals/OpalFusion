// OpalFusion+Execution+ProductionWorkflow+ImplementationGroup7.swift

import Foundation
import OpalCrypto
import OpalDiagnostics

extension OpalFusion.Execution.ProductionWorkflow {
    func validateRelayedProof(
        _ proofBytes: [UInt8],
        sourceCommitment: OpalFusion.Commitment.InitialCommitment,
        sharedRoundMaterial: OpalFusion.Execution.SharedRoundMaterial,
        badComponentIndices: Set<UInt32>,
        feeRateSatoshisPerKb: UInt64
    ) throws -> OpalFusion.Execution.ValidatedProof {
        let parsedProof = try parseProof(bytes: proofBytes)
        let componentIndex = Int(parsedProof.componentIndex)
        guard sharedRoundMaterial.decodedComponents.indices.contains(componentIndex) else {
            throw OpalFusion.Execution.RelayedProofValidationFailure(
                reason: "component index out of range"
            )
        }
        guard badComponentIndices.contains(parsedProof.componentIndex) == false else {
            throw OpalFusion.Execution.RelayedProofValidationFailure(
                reason: "component in bad list"
            )
        }

        let component = sharedRoundMaterial.decodedComponents[componentIndex]
        guard parsedProof.salt.count == 32 else {
            throw OpalFusion.Execution.RelayedProofValidationFailure(
                reason: "salt wrong length"
            )
        }
        guard OpalFusion.Execution.ProtocolPrimitives.sha256(parsedProof.salt) ==
            component.saltCommitment else {
            throw OpalFusion.Execution.RelayedProofValidationFailure(
                reason: "salt commitment mismatch"
            )
        }
        guard OpalFusion.Execution.ProtocolPrimitives.sha256(
            parsedProof.salt + component.serializedComponent
        ) == sourceCommitment.saltedComponentHash else {
            throw OpalFusion.Execution.RelayedProofValidationFailure(
                reason: "salted component hash mismatch"
            )
        }

        let contribution = try contributionForComponent(
            component.payload,
            feeRateSatoshisPerKb: feeRateSatoshisPerKb
        )
        let expectedCommitment: OpalCrypto.Pedersen.Commitment
        do {
            expectedCommitment = try pedersenSetup.commit(
                amount: contribution,
                nonce: OpalCrypto.Pedersen.Nonce(
                    rawRepresentation: Data(parsedProof.pedersenNonce)
                )
            )
        } catch {
            throw OpalFusion.Execution.RelayedProofValidationFailure(
                reason: "pedersen commitment verification error"
            )
        }
        guard Array(expectedCommitment.point.uncompressedRepresentation) ==
            sourceCommitment.amountCommitment else {
            throw OpalFusion.Execution.RelayedProofValidationFailure(
                reason: "pedersen commitment mismatch"
            )
        }

        switch component.payload {
        case let .input(inputComponent):
            return .input(inputComponent)
        case .output, .blank:
            return .nonInput
        }
    }

    func contributionForComponent(
        _ payload: OpalFusion.Commitment.ComponentPayload,
        feeRateSatoshisPerKb: UInt64
    ) throws -> Int64 {
        switch payload {
        case let .input(inputComponent):
            let fee = try checkedProofComponentFee(
                sizeBytes: OpalFusion.Execution.ProtocolPrimitives.inputSize(
                    for: inputComponent.publicKey
                ),
                feeRateSatoshisPerKb: feeRateSatoshisPerKb
            )
            return Int64(inputComponent.amountSatoshis) - Int64(fee)
        case let .output(outputComponent):
            let fee = try checkedProofComponentFee(
                sizeBytes: OpalFusion.Execution.ProtocolPrimitives.outputSize(
                    for: outputComponent.lockingScript
                ),
                feeRateSatoshisPerKb: feeRateSatoshisPerKb
            )
            let amount = Int64(outputComponent.amountSatoshis)
            let signedFee = Int64(fee)
            guard signedFee <= Int64.max - amount else {
                throw OpalFusion.Execution.RelayedProofValidationFailure(
                    reason: "component fee rate too large"
                )
            }
            return -(amount + signedFee)
        case .blank:
            return 0
        }
    }

    func checkedComponentFee(
        sizeBytes: Int,
        feeRateSatoshisPerKb: UInt64
    ) throws -> UInt64 {
        let fee = OpalFusion.Execution.ProtocolPrimitives.componentFee(
            sizeBytes: sizeBytes,
            feeRateSatoshisPerKb: feeRateSatoshisPerKb
        )
        guard fee <= UInt64(Int64.max) else {
            throw OpalFusion.Execution.WorkflowFailure.protocolValidationFailed(
                "Coordinator component fee rate was too large"
            )
        }
        return fee
    }

    func checkedProofComponentFee(
        sizeBytes: Int,
        feeRateSatoshisPerKb: UInt64
    ) throws -> UInt64 {
        let fee = OpalFusion.Execution.ProtocolPrimitives.componentFee(
            sizeBytes: sizeBytes,
            feeRateSatoshisPerKb: feeRateSatoshisPerKb
        )
        guard fee <= UInt64(Int64.max) else {
            throw OpalFusion.Execution.RelayedProofValidationFailure(
                reason: "component fee rate too large"
            )
        }
        return fee
    }
}

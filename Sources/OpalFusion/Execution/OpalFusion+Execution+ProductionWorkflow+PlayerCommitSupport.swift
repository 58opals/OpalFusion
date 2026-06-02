// OpalFusion+Execution+ProductionWorkflow+PlayerCommitSupport.swift

import Foundation
import OpalCrypto

extension OpalFusion.Execution.ProductionWorkflow {
    func appendBlankComponentMaterials(
        numberOfComponents: Int,
        components: inout [OpalFusion.Execution.LocalComponentMaterial]
    ) throws {
        for slot in components.count..<numberOfComponents {
            components.append(
                try buildComponentMaterial(
                    originalSlot: slot,
                    payload: .blank(.init()),
                    contributionSatoshis: 0
                )
            )
        }
    }

    func sortedCommitmentComponents(
        from components: [OpalFusion.Execution.LocalComponentMaterial]
    ) throws -> [OpalFusion.Execution.LocalComponentMaterial] {
        let serializedComponents = components.map(\.serializedComponent)
        guard Self.hasDuplicateByteArrays(serializedComponents) == false else {
            throw OpalFusion.Execution.WorkflowFailure.invalidParticipantReservation(
                "Participant reservation produced duplicate components"
            )
        }

        return components.sorted {
            Data($0.serializedInitialCommitment).lexicographicallyPrecedes(
                Data($1.serializedInitialCommitment)
            )
        }
    }

    func validateExcessFee(
        for sortedComponents: [OpalFusion.Execution.LocalComponentMaterial],
        serverHello: OpalFusion.ProtocolModel.ServerHello
    ) throws -> UInt64 {
        let excessFee = sortedComponents.reduce(Int64(0)) { partial, component in
            partial + component.contributionSatoshis
        }
        guard excessFee >= 0 else {
            throw OpalFusion.Execution.WorkflowFailure.invalidParticipantReservation(
                "Participant reservation does not satisfy the coordinator fee requirements"
            )
        }
        let excessFeeSatoshis = UInt64(excessFee)
        guard excessFeeSatoshis >= serverHello.minimumExcessFeeSatoshis,
              excessFeeSatoshis <= serverHello.maximumExcessFeeSatoshis else {
            throw OpalFusion.Execution.WorkflowFailure.invalidParticipantReservation(
                "Participant reservation produced an excess fee outside the coordinator range"
            )
        }
        return excessFeeSatoshis
    }

    func makeBlindSignatureRequests(
        startRound: OpalFusion.ProtocolModel.StartRound,
        sortedComponents: [OpalFusion.Execution.LocalComponentMaterial]
    ) throws -> [OpalCrypto.BlindSignature.Request] {
        let roundPublicKey: OpalCrypto.Secp256k1.PublicKey
        do {
            roundPublicKey = try OpalCrypto.Secp256k1.PublicKey(
                rawRepresentation: Data(startRound.roundPublicKey)
            )
        } catch {
            throw OpalFusion.Execution.WorkflowFailure.protocolValidationFailed(
                "StartRound round public key must be a valid compressed public key"
            )
        }

        let blindNoncePublicKeys: [OpalCrypto.Secp256k1.PublicKey] = try startRound
            .blindNoncePoints
            .enumerated()
            .map { index, blindNoncePoint in
                do {
                    return try OpalCrypto.Secp256k1.PublicKey(
                        rawRepresentation: Data(blindNoncePoint)
                    )
                } catch {
                    throw OpalFusion.Execution.WorkflowFailure.protocolValidationFailed(
                        "StartRound blind nonce point at index \(index) must be a valid compressed public key"
                    )
                }
            }

        do {
            return try zip(
                blindNoncePublicKeys,
                sortedComponents
            ).map { blindNoncePoint, component in
                try OpalCrypto.BlindSignature.Request(
                    signerPublicKey: roundPublicKey,
                    noncePoint: blindNoncePoint,
                    messageDigest: OpalCrypto.Signature.Digest(
                        rawRepresentation: Data(
                            OpalFusion.Execution.ProtocolPrimitives.sha256(
                                component.serializedComponent
                            )
                        )
                    )
                )
            }
        } catch {
            throw OpalFusion.Execution.WorkflowFailure.protocolValidationFailed(
                "Blind signature request construction failed"
            )
        }
    }
}

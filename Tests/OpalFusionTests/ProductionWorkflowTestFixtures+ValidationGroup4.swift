// ProductionWorkflowTestFixtures+ValidationGroup4.swift

@testable import OpalFusion
import Foundation
import OpalCrypto

extension ProductionWorkflowTestFixtures {
    static func makeSignedFinalizedTransaction(
        proposal: OpalFusion.Host.TransactionFinalizationProposal,
        participantInputs: [OpalFusion.Host.ParticipantInput],
        participantInputPrivateKeys: [[UInt8]]
    ) throws -> (
        transaction: OpalFusion.Host.FinalizedTransaction,
        signaturesByReservationInputIndex: [[UInt8]],
        transactionInputIndicesByReservationInputIndex: [Int]
    ) {
        guard participantInputs.count == participantInputPrivateKeys.count else {
            throw ProductionWorkflowTestError.participantPrivateKeyCountMismatch
        }

        var transaction = try OpalFusion.Execution.BCHTransaction.parse(
            proposal.unsignedTransactionBytes
        )
        var signatures: [[UInt8]] = []
        var transactionInputIndices: [Int] = []
        signatures.reserveCapacity(participantInputs.count)
        transactionInputIndices.reserveCapacity(participantInputs.count)

        for (participantInput, participantInputPrivateKey) in zip(
            participantInputs,
            participantInputPrivateKeys
        ) {
            guard let participantInputPublicKey = participantInput.publicKey else {
                throw ProductionWorkflowTestError.missingParticipantInputPublicKey
            }

            let previousTransactionHashLittleEndian = Array(
                participantInput.outpointTransactionHashBytes.reversed()
            )
            guard let inputIndex = transaction.inputs.firstIndex(where: { input in
                input.previousTransactionHashLittleEndian == previousTransactionHashLittleEndian &&
                    input.previousOutputIndex == participantInput.outpointIndex
            }) else {
                throw ProductionWorkflowTestError.signingInputNotFound
            }

            let sighash = try transaction.signatureHash(
                forInputAt: inputIndex,
                lockingScript: participantInput.lockingScriptBytes,
                amountSatoshis: participantInput.amountSatoshis
            )
            let signature = try Array(
                OpalCrypto.Signature.Schnorr.sign(
                    digest: OpalCrypto.Signature.Digest(rawRepresentation: Data(sighash)),
                    privateKey: OpalCrypto.Secp256k1.PrivateKey(
                        rawRepresentation: Data(participantInputPrivateKey)
                    ),
                    noncePolicy: .bip340Deterministic
                ).rawRepresentation
            )

            transaction = try transaction.settingUnlockingScript(
                standardP2PKHUnlockingScript(
                    signature: signature,
                    publicKey: participantInputPublicKey
                ),
                at: inputIndex
            )
            signatures.append(signature)
            transactionInputIndices.append(inputIndex)
        }

        return (
            .init(transactionBytes: try transaction.serialize()),
            signatures,
            transactionInputIndices
        )
    }

    static func standardP2PKHUnlockingScript(
        signature: [UInt8],
        publicKey: [UInt8]
    ) -> [UInt8] {
        [0x41] + signature + [0x41] + [0x21] + publicKey
    }

    static func p2pkhLockingScript(publicKey: [UInt8]) -> [UInt8] {
        [0x76, 0xA9, 0x14]
            + OpalFusion.Execution.ProtocolPrimitives.hash160(publicKey)
            + [0x88, 0xAC]
    }
}

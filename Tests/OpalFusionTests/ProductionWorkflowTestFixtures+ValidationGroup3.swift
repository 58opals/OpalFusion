// ProductionWorkflowTestFixtures+ValidationGroup3.swift

@testable import OpalFusion
import Foundation
import OpalCrypto

extension ProductionWorkflowTestFixtures {
    static func makeExternalInputComponent(
        workflow: OpalFusion.Execution.ProductionWorkflow,
        feeRateSatoshisPerKb: UInt64
    ) throws -> ExternalInputComponentFixture {
        let inputPrivateKey = [UInt8](repeating: 0x44, count: 32)
        let inputPublicKey = try Array(
            OpalCrypto.Secp256k1.derivePublicKey(
                from: OpalCrypto.Secp256k1.PrivateKey(
                    rawRepresentation: Data(inputPrivateKey)
                )
            ).rawRepresentation
        )
        let communicationPrivateKey = [UInt8](repeating: 0x55, count: 32)
        let communicationPublicKey = try Array(
            OpalCrypto.Secp256k1.derivePublicKey(
                from: OpalCrypto.Secp256k1.PrivateKey(
                    rawRepresentation: Data(communicationPrivateKey)
                )
            ).rawRepresentation
        )
        let salt = [UInt8](repeating: 0x66, count: 32)
        let pedersenNonce = [UInt8](repeating: 0x77, count: 32)
        let amountSatoshis: UInt64 = 60_000

        let inputComponent = OpalFusion.Commitment.InputComponent(
            outpointTransactionHash: [UInt8](repeating: 0xCC, count: 32),
            outpointIndex: 2,
            publicKey: inputPublicKey,
            amountSatoshis: amountSatoshis
        )
        let serializedComponent = try OpalFusion.Wire.CashFusionComponentCodec.encode(
            payload: .input(inputComponent),
            saltCommitment: OpalFusion.Execution.ProtocolPrimitives.sha256(salt)
        )

        let contribution = Int64(amountSatoshis)
            - Int64(
                OpalFusion.Execution.ProtocolPrimitives.componentFee(
                    sizeBytes: OpalFusion.Execution.ProtocolPrimitives
                        .inputSize(for: inputPublicKey),
                    feeRateSatoshisPerKb: feeRateSatoshisPerKb
                )
            )
        let pedersenCommitment = try workflow.pedersenSetup.commit(
            amount: contribution,
            nonce: OpalCrypto.Pedersen.Nonce(rawRepresentation: Data(pedersenNonce))
        )
        let initialCommitment = OpalFusion.Commitment.InitialCommitment(
            saltedComponentHash: OpalFusion.Execution.ProtocolPrimitives.sha256(
                salt + serializedComponent
            ),
            amountCommitment: Array(pedersenCommitment.point.uncompressedRepresentation),
            communicationPublicKey: communicationPublicKey
        )

        return .init(
            serializedComponent: serializedComponent,
            initialCommitment: initialCommitment,
            communicationPrivateKey: communicationPrivateKey,
            salt: salt,
            pedersenNonce: pedersenNonce
        )
    }

    static func encryptProof(
        componentIndex: Int,
        salt: [UInt8],
        pedersenNonce: [UInt8],
        recipientPublicKey: [UInt8]
    ) throws -> [UInt8] {
        let proof = OpalFusion.Blame.Proof(
            componentIndex: UInt32(componentIndex),
            salt: salt,
            pedersenNonce: pedersenNonce
        )
        return try Array(
            OpalCrypto.Communication.encrypt(
                message: Data(
                    try OpalFusion.Wire.CashFusionProofCodec.encode(proof)
                ),
                recipientPublicKey: OpalCrypto.Secp256k1.PublicKey(
                    rawRepresentation: Data(recipientPublicKey)
                ),
                paddedPlaintextLength: OpalFusion.Execution.ProtocolPrimitives
                    .encryptedProofPaddedPlaintextByteCount,
                maximumCiphertextByteCount: OpalFusion.Execution.ProtocolPrimitives
                    .maximumEncryptedProofCiphertextByteCount
            ).rawRepresentation
        )
    }

    static func makeSignedFinalizedTransaction(
        proposal: OpalFusion.Host.TransactionFinalizationProposal,
        participantInput: OpalFusion.Host.ParticipantInput,
        participantInputPrivateKey: [UInt8],
        unlockingScriptBuilder: (([UInt8], [UInt8]) -> [UInt8])? = nil
    ) throws -> SigningTransactionFixture {
        guard let participantInputPublicKey = participantInput.publicKey else {
            throw ProductionWorkflowTestError.missingParticipantInputPublicKey
        }

        var transaction = try OpalFusion.Execution.BCHTransaction.parse(
            proposal.unsignedFusionTransactionBytes
        )
        let sighash = try transaction.signatureHash(
            forInputAt: 0,
            lockingScript: participantInput.lockingScriptBytes,
            amountSatoshis: participantInput.amountSatoshis
        )
        let signature = try Array(
            OpalCrypto.Signature.Schnorr.sign(
                digest: OpalCrypto.Signature.Digest(rawRepresentation: Data(sighash)),
                privateKey: OpalCrypto.Secp256k1.PrivateKey(
                    rawRepresentation: Data(participantInputPrivateKey)
                ),
                noncePolicy: .bchDeterministic
            ).rawRepresentation
        )

        let unlockingScript = unlockingScriptBuilder?(
            signature,
            participantInputPublicKey
        ) ?? standardP2PKHUnlockingScript(
            signature: signature,
            publicKey: participantInputPublicKey
        )

        transaction = try transaction.settingUnlockingScript(unlockingScript, at: 0)
        return .init(
            transaction: .init(signedFusionTransactionBytes: try transaction.serialize()),
            signature: signature
        )
    }
}

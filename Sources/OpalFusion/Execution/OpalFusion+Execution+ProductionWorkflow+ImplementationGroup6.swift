// OpalFusion+Execution+ProductionWorkflow+ImplementationGroup6.swift

import Foundation
import OpalCrypto
import OpalDiagnostics

extension OpalFusion.Execution.ProductionWorkflow {
    func extractLocalSignature(
        from input: OpalFusion.Execution.BCHTransaction.Input,
        transaction: OpalFusion.Execution.BCHTransaction,
        inputReference: OpalFusion.Execution.LocalInputReference
    ) throws -> [UInt8] {
        guard let publicKey = inputReference.participantInput.publicKey else {
            throw OpalFusion.Execution.WorkflowFailure.missingParticipantInputPublicKey(
                index: inputReference.reservationInputIndex
            )
        }
        let (signature, pushedPublicKey) = try parseP2PKHUnlockingScript(input.unlockingScript)
        guard pushedPublicKey == publicKey else {
            throw OpalFusion.Execution.BCHTransactionError.templateMismatch(
                "Finalized transaction public key did not match the reserved participant input"
            )
        }

        let sighash = try transaction.signatureHash(
            forInputAt: inputReference.transactionInputIndex,
            lockingScript: inputReference.participantInput.lockingScriptBytes,
            amountSatoshis: inputReference.participantInput.amountSatoshis
        )
        let isValid: Bool
        do {
            isValid = try OpalCrypto.Signature.Schnorr(
                rawRepresentation: Data(signature)
            ).verify(
                digest: OpalCrypto.Signature.Digest(rawRepresentation: Data(sighash)),
                publicKey: OpalCrypto.Secp256k1.PublicKey(
                    rawRepresentation: Data(publicKey)
                )
            )
        } catch {
            throw OpalFusion.Execution.BCHTransactionError.templateMismatch(
                "Finalized transaction signature verification failed"
            )
        }
        guard isValid else {
            throw OpalFusion.Execution.BCHTransactionError.templateMismatch(
                "Finalized transaction included an invalid signature"
            )
        }
        return signature
    }

    func parseP2PKHUnlockingScript(
        _ unlockingScript: [UInt8]
    ) throws -> (signature: [UInt8], publicKey: [UInt8]) {
        guard unlockingScript.isEmpty == false else {
            throw OpalFusion.Execution.BCHTransactionError.templateMismatch(
                "Finalized transaction was missing a required local unlocking script"
            )
        }
        var cursor = 0
        let signaturePush = try parsePushData(from: unlockingScript, cursor: &cursor)
        let publicKeyPush = try parsePushData(from: unlockingScript, cursor: &cursor)
        guard cursor == unlockingScript.count else {
            throw OpalFusion.Execution.BCHTransactionError.unsupportedInput(
                OpalFusion.Execution.ProtocolPrimitives.supportedUnlockingScriptSummary
            )
        }
        guard signaturePush.count == 65, signaturePush.last == 0x41 else {
            throw OpalFusion.Execution.BCHTransactionError.unsupportedInput(
                OpalFusion.Execution.ProtocolPrimitives.supportedUnlockingScriptSummary
            )
        }
        guard OpalFusion.Execution.ProtocolPrimitives.isCompressedSecp256k1PublicKey(
            publicKeyPush
        ) else {
            throw OpalFusion.Execution.BCHTransactionError.unsupportedInput(
                OpalFusion.Execution.ProtocolPrimitives.supportedUnlockingScriptSummary
            )
        }
        return (Array(signaturePush.dropLast()), publicKeyPush)
    }

    func parsePushData(
        from script: [UInt8],
        cursor: inout Int
    ) throws -> [UInt8] {
        guard cursor < script.count else {
            throw OpalFusion.Execution.BCHTransactionError.unsupportedInput(
                OpalFusion.Execution.ProtocolPrimitives.supportedUnlockingScriptSummary
            )
        }
        let opcode = script[cursor]
        cursor += 1
        guard opcode > 0x00, opcode < 0x4C else {
            throw OpalFusion.Execution.BCHTransactionError.unsupportedInput(
                OpalFusion.Execution.ProtocolPrimitives.supportedUnlockingScriptSummary
            )
        }
        let pushLength = Int(opcode)
        guard cursor + pushLength <= script.count else {
            throw OpalFusion.Execution.BCHTransactionError.unsupportedInput(
                OpalFusion.Execution.ProtocolPrimitives.supportedUnlockingScriptSummary
            )
        }
        defer { cursor += pushLength }
        return Array(script[cursor..<(cursor + pushLength)])
    }
}

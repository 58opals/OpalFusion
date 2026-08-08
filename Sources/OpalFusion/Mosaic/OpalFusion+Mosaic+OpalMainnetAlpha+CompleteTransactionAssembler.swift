// OpalFusion+Mosaic+OpalMainnetAlpha+CompleteTransactionAssembler.swift

import Foundation
import OpalCrypto

extension OpalFusion.Mosaic.OpalMainnetAlpha {
    enum CompleteTransactionAssembler {
        static func assemble(
            transcript: OpalFusion.Mosaic.OpalV0.UnsignedTransactionTranscript,
            signatureSet: BCHSignatureSet,
            spentInputs: [OpalFusion.Host.ParticipantInput]
        ) throws -> OpalFusion.Host.MosaicCompleteTransaction {
            guard transcript.profile == .opalMainnetAlpha,
                  signatureSet.roundIdentifier
                    == transcript.manifest.roundIdentifier,
                  signatureSet.transcriptRoot
                    == transcript.transcriptRoot.validatedBytes else {
                throw ContractError.transcriptMismatch
            }
            guard spentInputs.count == transcript.transaction.inputs.count,
                  signatureSet.entries.count == transcript.transaction.inputs.count else {
                throw ContractError.transactionMismatch
            }
            let committedInputs = transcript.componentSet.components.compactMap {
                component -> OpalFusion.Mosaic.OpalV0.InputComponent? in
                guard case let .input(input) = component.payload else {
                    return nil
                }
                return input
            }.sorted { lhs, rhs in
                if lhs.previousTransactionHash != rhs.previousTransactionHash {
                    return lhs.previousTransactionHash.lexicographicallyPrecedes(
                        rhs.previousTransactionHash
                    )
                }
                return lhs.outputIndex < rhs.outputIndex
            }
            guard committedInputs.count == transcript.transaction.inputs.count else {
                throw ContractError.transactionMismatch
            }

            var completeTransaction = transcript.transaction
            for index in completeTransaction.inputs.indices {
                let transactionInput = completeTransaction.inputs[index]
                let committedInput = committedInputs[index]
                let spentInput = spentInputs[index]
                let entry = signatureSet.entries[index]
                guard entry.inputIndex == UInt32(index),
                      transactionInput.previousTransactionHashLittleEndian
                        == Array(committedInput.previousTransactionHash.reversed()),
                      transactionInput.previousOutputIndex
                        == committedInput.outputIndex,
                      transactionInput.previousTransactionHashLittleEndian
                        == Array(spentInput.outpointTransactionHashBytes.reversed()),
                      transactionInput.previousOutputIndex == spentInput.outpointIndex,
                      transactionInput.unlockingScript.isEmpty,
                      spentInput.amountSatoshis
                        == committedInput.amountSatoshis else {
                    throw ContractError.invalidSpentInput(index: index)
                }
                if let expectedPublicKey = spentInput.publicKey,
                   expectedPublicKey != entry.publicKey {
                    throw ContractError.invalidSpentInput(index: index)
                }
                try validateP2PKHLockingScript(
                    spentInput.lockingScriptBytes,
                    publicKey: entry.publicKey,
                    inputIndex: index
                )
                let signatureHash = try transcript.transaction.signatureHash(
                    forInputAt: index,
                    lockingScript: spentInput.lockingScriptBytes,
                    amountSatoshis: spentInput.amountSatoshis,
                    sighashType: 0x41
                )
                let isValid = try OpalCrypto.Signature.Schnorr(
                    rawRepresentation: Data(entry.signature)
                ).verify(
                    digest: OpalCrypto.Signature.Digest(
                        rawRepresentation: Data(signatureHash)
                    ),
                    publicKey: OpalCrypto.Secp256k1.PublicKey(
                        rawRepresentation: Data(entry.publicKey)
                    )
                )
                guard isValid else {
                    throw ContractError.bchSignatureVerificationFailed(index: index)
                }
                let unlockingScript = [UInt8(0x41)]
                    + entry.signature
                    + [UInt8(0x41), UInt8(0x21)]
                    + entry.publicKey
                guard unlockingScript.count
                    == OpalFusion.Mosaic.OpalMainnetAlpha
                        .standardP2PKHUnlockingScriptByteCount else {
                    preconditionFailure("The frozen P2PKH Schnorr script is 100 bytes.")
                }
                completeTransaction = try completeTransaction
                    .settingUnlockingScript(unlockingScript, at: index)
            }
            return try .init(transactionBytes: completeTransaction.serialize())
        }

        private static func validateP2PKHLockingScript(
            _ lockingScript: [UInt8],
            publicKey: [UInt8],
            inputIndex: Int
        ) throws {
            guard lockingScript.count == 25,
                  lockingScript[0 ... 2] == [0x76, 0xa9, 0x14],
                  lockingScript[23 ... 24] == [0x88, 0xac],
                  Array(lockingScript[3 ... 22])
                    == OpalFusion.Execution.ProtocolPrimitives.hash160(publicKey) else {
                throw ContractError.invalidP2PKHLockingScript(index: inputIndex)
            }
        }
    }
}

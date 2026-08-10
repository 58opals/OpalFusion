// OpalFusion+Mosaic+OpalMainnetAlpha+BCHSignatureValidator.swift

import Foundation
import OpalCrypto

extension OpalFusion.Mosaic.OpalMainnetAlpha {
    /// Verifies one input-indexed BCH signature against the exact transcript and previous output.
    enum BCHSignatureValidator {
        static func validatedUnlockingScript(
            entry: BCHSignatureEntry,
            at inputIndex: Int,
            committedInput: OpalFusion.Mosaic.OpalV0.InputComponent,
            spentInput: OpalFusion.Host.ParticipantInput,
            transaction: OpalFusion.Execution.BCHTransaction
        ) throws -> [UInt8] {
            guard transaction.inputs.indices.contains(inputIndex) else {
                throw ContractError.invalidSpentInput(index: inputIndex)
            }
            let transactionInput = transaction.inputs[inputIndex]
            guard entry.inputIndex == UInt32(inputIndex),
                  transactionInput.previousTransactionHashLittleEndian
                    == Array(committedInput.previousTransactionHash.reversed()),
                  transactionInput.previousOutputIndex == committedInput.outputIndex,
                  transactionInput.previousTransactionHashLittleEndian
                    == Array(spentInput.outpointTransactionHashBytes.reversed()),
                  transactionInput.previousOutputIndex == spentInput.outpointIndex,
                  transactionInput.unlockingScript.isEmpty,
                  spentInput.amountSatoshis == committedInput.amountSatoshis else {
                throw ContractError.invalidSpentInput(index: inputIndex)
            }
            if let expectedPublicKey = spentInput.publicKey,
               expectedPublicKey != entry.publicKey {
                throw ContractError.invalidSpentInput(index: inputIndex)
            }
            guard OpalFusion.Execution.ProtocolPrimitives
                .isCompressedSecp256k1PublicKey(entry.publicKey),
                OpalFusion.Execution.ProtocolPrimitives
                .isStandardP2PKHLockingScript(
                    spentInput.lockingScriptBytes,
                    publicKey: entry.publicKey
                ) else {
                throw ContractError.invalidP2PKHLockingScript(index: inputIndex)
            }

            let signatureHash = try transaction.signatureHash(
                forInputAt: inputIndex,
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
                throw ContractError.bchSignatureVerificationFailed(index: inputIndex)
            }

            let unlockingScript = [UInt8(0x41)]
                + entry.signature
                + [UInt8(0x41), UInt8(0x21)]
                + entry.publicKey
            guard unlockingScript.count == standardP2PKHUnlockingScriptByteCount else {
                preconditionFailure("The frozen P2PKH Schnorr script is 100 bytes.")
            }
            return unlockingScript
        }
    }

    /// Previous-output-backed semantic validation for one anonymous signature submission.
    struct BCHSignatureAdmissionValidator: AnonymousBCHSignatureAdmissionValidating {
        enum Failure: Error, Sendable, Equatable {
            case transcriptMismatch
            case inputComponentMissing
            case signatureRejected
        }

        let previousOutputs: PreviousOutputResolver.Validation

        func validateBCHSignatureAdmission(
            submission: BCHSignatureSubmission,
            acceptedInputComponent: OpalFusion.Mosaic.OpalV0.Component,
            transcript: OpalFusion.Mosaic.OpalV0.UnsignedTransactionTranscript
        ) throws {
            guard previousOutputs.transcriptRoot == transcript.transcriptRoot else {
                throw Failure.transcriptMismatch
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
            guard case let .input(acceptedInput) = acceptedInputComponent.payload,
                  let inputIndex = committedInputs.firstIndex(of: acceptedInput),
                  previousOutputs.spentInputs.indices.contains(inputIndex),
                  submission.entry.inputIndex == UInt32(inputIndex) else {
                throw Failure.inputComponentMissing
            }
            do {
                _ = try BCHSignatureValidator.validatedUnlockingScript(
                    entry: submission.entry,
                    at: inputIndex,
                    committedInput: committedInputs[inputIndex],
                    spentInput: previousOutputs.spentInputs[inputIndex],
                    transaction: transcript.transaction
                )
            } catch {
                throw Failure.signatureRejected
            }
        }
    }
}

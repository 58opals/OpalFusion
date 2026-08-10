// OpalFusion+Mosaic+OpalMainnetAlpha+LocalBCHSignatureBuilder.swift

extension OpalFusion.Mosaic.OpalMainnetAlpha {
    /// One host-produced local signature paired with its retained purpose-one authorization.
    struct LocalBCHSignaturePublication: Sendable, Equatable {
        let slot: Int
        let recipientEventIdentity: [UInt8]
        let submission: BCHSignatureSubmission
    }

    /// Extracts only the exact local signatures produced by the wallet host.
    enum LocalBCHSignatureBuilder {
        enum Failure: Error, Sendable, Equatable {
            case contextBindingMismatch
            case finalizedTransactionInvalid
            case finalizedTransactionBodyMismatch
            case nonLocalInputSigned(index: Int)
            case localInputUnsigned(index: Int)
            case localInputSlotMissing(index: Int)
            case authorizationTokenMissing(slot: Int)
            case unlockingScriptInvalid(index: Int)
            case signatureInvalid(index: Int)
            case submissionInvalid(index: Int)
        }

        private struct Outpoint: Hashable {
            let transactionHash: [UInt8]
            let outputIndex: UInt32
        }

        static func build(
            finalizedTransaction: OpalFusion.Host.FinalizedTransaction,
            signingRequest: OpalFusion.Host.MosaicTransactionSigningRequest,
            transcript: OpalFusion.Mosaic.OpalV0.UnsignedTransactionTranscript,
            material: LocalContributionMaterial,
            authorizationValidation: AuthorizationResponseSetMaterialValidation
        ) throws(Failure) -> [LocalBCHSignaturePublication] {
            guard transcript.profile == .opalMainnetAlpha,
                  signingRequest.reservationReference
                    == material.reservationLease.reference,
                  signingRequest.roundIdentifier
                    == material.manifest.core.roundIdentifier,
                  signingRequest.transcriptBinding == transcript.transcriptBinding,
                  signingRequest.unsignedTransactionBytes
                    == transcript.unsignedTransactionBytes,
                  authorizationValidation.attemptIdentifier
                    == material.attemptIdentifier,
                  authorizationValidation.generationIdentifier
                    == material.generationIdentifier,
                  authorizationValidation.materialIdentifier
                    == material.materialIdentifier,
                  authorizationValidation.responseSet.contributor
                    == material.contributor else {
                throw .contextBindingMismatch
            }

            let finalized: OpalFusion.Execution.BCHTransaction
            do {
                finalized = try .parse(
                    finalizedTransaction.signedFusionTransactionBytes
                )
            } catch {
                throw .finalizedTransactionInvalid
            }
            guard finalized.version == transcript.transaction.version,
                  finalized.lockTime == transcript.transaction.lockTime,
                  finalized.outputs == transcript.transaction.outputs,
                  finalized.inputs.count == transcript.transaction.inputs.count else {
                throw .finalizedTransactionBodyMismatch
            }
            let localIndices = Set(signingRequest.localInputIndices)
            for index in finalized.inputs.indices {
                let finalizedInput = finalized.inputs[index]
                let unsignedInput = transcript.transaction.inputs[index]
                guard finalizedInput.previousTransactionHashLittleEndian
                        == unsignedInput.previousTransactionHashLittleEndian,
                      finalizedInput.previousOutputIndex
                        == unsignedInput.previousOutputIndex,
                      finalizedInput.sequence == unsignedInput.sequence else {
                    throw .finalizedTransactionBodyMismatch
                }
                if localIndices.contains(index) {
                    guard !finalizedInput.unlockingScript.isEmpty else {
                        throw .localInputUnsigned(index: index)
                    }
                } else if !finalizedInput.unlockingScript.isEmpty {
                    throw .nonLocalInputSigned(index: index)
                }
            }

            let slotByOutpoint: [Outpoint: ComponentSlotMaterial] = Dictionary(
                uniqueKeysWithValues: material.slots.compactMap { slot in
                    guard case let .input(input) = slot.component.payload else {
                        return nil
                    }
                    return (
                        Outpoint(
                            transactionHash: input.previousTransactionHash,
                            outputIndex: input.outputIndex
                        ),
                        slot
                    )
                }
            )
            let tokens = authorizationValidation.bchSignatureAuthorizationTokens
            var publications: [LocalBCHSignaturePublication] = []
            publications.reserveCapacity(localIndices.count)
            for inputIndex in signingRequest.localInputIndices.sorted() {
                guard signingRequest.spentInputs.indices.contains(inputIndex) else {
                    throw .localInputSlotMissing(index: inputIndex)
                }
                let spentInput = signingRequest.spentInputs[inputIndex]
                let outpoint = Outpoint(
                    transactionHash: spentInput.outpointTransactionHashBytes,
                    outputIndex: spentInput.outpointIndex
                )
                guard let slot = slotByOutpoint[outpoint] else {
                    throw .localInputSlotMissing(index: inputIndex)
                }
                guard tokens.indices.contains(slot.slot) else {
                    throw .authorizationTokenMissing(slot: slot.slot)
                }
                let unlockingScript = finalized.inputs[inputIndex].unlockingScript
                guard unlockingScript.count == standardP2PKHUnlockingScriptByteCount,
                      unlockingScript[0] == 0x41,
                      unlockingScript[65] == 0x41,
                      unlockingScript[66] == 0x21 else {
                    throw .unlockingScriptInvalid(index: inputIndex)
                }
                let entry: BCHSignatureEntry
                do {
                    entry = try .init(
                        inputIndex: UInt32(inputIndex),
                        signature: Array(unlockingScript[1 ..< 65]),
                        publicKey: Array(unlockingScript[67 ..< 100])
                    )
                } catch {
                    throw .unlockingScriptInvalid(index: inputIndex)
                }
                guard case let .input(committedInput) = slot.component.payload else {
                    throw .localInputSlotMissing(index: inputIndex)
                }
                do {
                    let expectedScript = try BCHSignatureValidator
                        .validatedUnlockingScript(
                        entry: entry,
                        at: inputIndex,
                        committedInput: committedInput,
                        spentInput: spentInput,
                        transaction: transcript.transaction
                    )
                    guard expectedScript == unlockingScript else {
                        throw Failure.signatureInvalid(index: inputIndex)
                    }
                } catch let failure as Failure {
                    throw failure
                } catch {
                    throw .signatureInvalid(index: inputIndex)
                }
                let submission: BCHSignatureSubmission
                do {
                    submission = try .init(
                        transcriptRoot: transcript.transcriptRoot.validatedBytes,
                        authorizationToken: tokens[slot.slot],
                        entry: entry
                    )
                } catch {
                    throw .submissionInvalid(index: inputIndex)
                }
                publications.append(
                    .init(
                        slot: slot.slot,
                        recipientEventIdentity: slot.recipientEventIdentity,
                        submission: submission
                    )
                )
            }
            return publications
        }
    }
}

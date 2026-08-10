// OpalFusion+Mosaic+OpalMainnetAlpha+CompleteTransactionAssembler.swift

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
                let committedInput = committedInputs[index]
                let spentInput = spentInputs[index]
                let entry = signatureSet.entries[index]
                let unlockingScript = try BCHSignatureValidator
                    .validatedUnlockingScript(
                    entry: entry,
                    at: index,
                    committedInput: committedInput,
                    spentInput: spentInput,
                    transaction: transcript.transaction
                )
                completeTransaction = try completeTransaction
                    .settingUnlockingScript(unlockingScript, at: index)
            }
            return try .init(transactionBytes: completeTransaction.serialize())
        }
    }
}

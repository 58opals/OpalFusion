// OpalFusion+Mosaic+OpalMainnetAlpha+CompleteTransactionPayload.swift

extension OpalFusion.Mosaic.OpalMainnetAlpha {
    struct CompleteTransactionPayload: Sendable, Equatable {
        let roundIdentifier: [UInt8]
        let transcriptRoot: [UInt8]
        let completeTransaction: OpalFusion.Host.MosaicCompleteTransaction
        let transaction: OpalFusion.Execution.BCHTransaction
        let canonicalBytes: [UInt8]
        let digest: [UInt8]

        init(
            roundIdentifier: [UInt8],
            transcriptRoot: [UInt8],
            completeTransaction: OpalFusion.Host.MosaicCompleteTransaction
        ) throws {
            try RoleSeedValidator.validateFixed(
                roundIdentifier,
                field: .roundIdentifier
            )
            try RoleSeedValidator.validateFixed(
                transcriptRoot,
                field: .transcriptRoot
            )
            guard UInt32(exactly: completeTransaction.transactionBytes.count) != nil else {
                throw ContractError.invalidAggregateByteCount(
                    actual: completeTransaction.transactionBytes.count
                )
            }
            let transaction: OpalFusion.Execution.BCHTransaction
            do {
                transaction = try .parse(completeTransaction.transactionBytes)
            } catch {
                throw ContractError.invalidCompleteTransaction
            }
            let canonicalTransactionBytes: [UInt8]
            do {
                canonicalTransactionBytes = try transaction.serialize()
            } catch {
                throw ContractError.invalidCompleteTransaction
            }
            guard transaction.version == 2,
                  transaction.lockTime == 0,
                  (1 ... OpalFusion.Mosaic.OpalMainnetAlpha
                    .maximumTransactionInputCount).contains(
                        transaction.inputs.count
                    ),
                  transaction.inputs.allSatisfy({ input in
                      input.sequence == UInt32.max
                          && input.unlockingScript.count
                            == OpalFusion.Mosaic.OpalMainnetAlpha
                                .standardP2PKHUnlockingScriptByteCount
                          && input.unlockingScript[0] == 0x41
                          && input.unlockingScript[65] == 0x41
                          && input.unlockingScript[66] == 0x21
                  }),
                  (1 ... OpalFusion.Mosaic.OpalMainnetAlpha
                    .maximumTransactionOutputCount).contains(
                        transaction.outputs.count
                    ),
                  transaction.inputs.count + transaction.outputs.count
                    <= OpalFusion.Mosaic.OpalMainnetAlpha
                        .maximumTransactionComponentCount,
                  transaction.outputs.allSatisfy({ output in
                      output.lockingScript.count == 25
                          && output.lockingScript[0 ... 2]
                            == [0x76, 0xa9, 0x14]
                          && output.lockingScript[23 ... 24] == [0x88, 0xac]
                  }),
                  canonicalTransactionBytes
                    == completeTransaction.transactionBytes else {
                throw ContractError.invalidCompleteTransaction
            }
            let canonicalBytes = try CanonicalWireCodec
                .encodeCompleteTransactionPayload(
                    roundIdentifier: roundIdentifier,
                    transcriptRoot: transcriptRoot,
                    transactionBytes: completeTransaction.transactionBytes
                )
            self.roundIdentifier = Array(roundIdentifier)
            self.transcriptRoot = Array(transcriptRoot)
            self.completeTransaction = completeTransaction
            self.transaction = transaction
            self.canonicalBytes = canonicalBytes
            self.digest = RoleSeedValidator.hash(
                domainSuffix: "complete-transaction",
                fields: [canonicalBytes]
            )
        }

        func matches(
            transcript: OpalFusion.Mosaic.OpalV0.UnsignedTransactionTranscript
        ) -> Bool {
            guard transcript.profile == .opalMainnetAlpha,
                  roundIdentifier == transcript.manifest.roundIdentifier,
                  transcriptRoot == transcript.transcriptRoot.validatedBytes else {
                return false
            }
            let unsignedTransaction = OpalFusion.Execution.BCHTransaction(
                version: transaction.version,
                inputs: transaction.inputs.map { input in
                    .init(
                        previousTransactionHashLittleEndian:
                            input.previousTransactionHashLittleEndian,
                        previousOutputIndex: input.previousOutputIndex,
                        unlockingScript: [],
                        sequence: input.sequence
                    )
                },
                outputs: transaction.outputs,
                lockTime: transaction.lockTime
            )
            return unsignedTransaction == transcript.transaction
        }
    }
}

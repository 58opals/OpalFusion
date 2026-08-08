// OpalFusion+Mosaic+OpalV0+UnsignedTransactionTranscript.swift

extension OpalFusion.Mosaic.OpalV0 {
    /// A deterministic Opal-v0 unsigned transaction and its recomputable transcript binding.
    ///
    /// Construction covers only the frozen aggregate transaction rules. Previous-output fetching,
    /// reservation ownership, and wallet policy remain host responsibilities.
    struct UnsignedTransactionTranscript: Sendable, Equatable {
        enum ValidationError: Error, Sendable, Equatable {
            case contributorRosterMismatch
            case invalidComponentCount(expected: Int, actual: Int)
            case missingInput
            case missingOutput
            case inputAmountExceedsMaximum(actual: UInt64)
            case outputAmountExceedsMaximum(actual: UInt64)
            case outputAmountExceedsInput(
                inputSatoshis: UInt64,
                outputSatoshis: UInt64
            )
            case feeMismatch(expected: UInt64, actual: UInt64)
        }

        let contributors: [OpalFusion.Mosaic.Attempt.ControlIdentity]
        let manifest: OpalFusion.Mosaic.Attempt.ManifestBinding
        let commitmentSet: CommitmentSet
        let componentSet: ComponentSet
        let transaction: OpalFusion.Execution.BCHTransaction
        let unsignedTransactionBytes: [UInt8]
        let estimatedFinalSignedByteCount: Int
        let feeSatoshis: UInt64
        let transcriptBinding: OpalFusion.Host.MosaicTranscriptBinding
        let transcriptRoot: OpalFusion.Mosaic.Attempt.TranscriptRoot

        init(
            roster: OpalFusion.Mosaic.Attempt.Roster,
            manifest: OpalFusion.Mosaic.Attempt.ManifestBinding,
            commitmentSet: OpalFusion.Mosaic.Attempt.CommitmentSetValidation,
            componentSet: ComponentSet
        ) throws(ValidationError) {
            let contributorCount = roster.contributors.count
            guard commitmentSet.contributors == roster.contributors else {
                throw .contributorRosterMismatch
            }

            let expectedComponentCount = contributorCount
                * OpalFusion.Mosaic.OpalV0.componentAuthorizationCountPerContributor
            guard componentSet.components.count == expectedComponentCount else {
                throw .invalidComponentCount(
                    expected: expectedComponentCount,
                    actual: componentSet.components.count
                )
            }

            let inputComponents: [InputComponent] = componentSet.components.compactMap {
                component in
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
            guard !inputComponents.isEmpty else {
                throw .missingInput
            }

            let outputComponents: [OutputComponent] = componentSet.components.compactMap {
                component in
                guard case let .output(output) = component.payload else {
                    return nil
                }
                return output
            }.sorted { lhs, rhs in
                if lhs.amountSatoshis != rhs.amountSatoshis {
                    return lhs.amountSatoshis < rhs.amountSatoshis
                }
                return lhs.lockingScript.lexicographicallyPrecedes(rhs.lockingScript)
            }
            guard !outputComponents.isEmpty else {
                throw .missingOutput
            }

            let inputSatoshis = Self.sumAmounts(
                inputComponents.map(\.amountSatoshis)
            )
            let outputSatoshis = Self.sumAmounts(
                outputComponents.map(\.amountSatoshis)
            )
            let maximumMoneySatoshis = OpalFusion.Mosaic.OpalV0
                .maximumMoneySatoshis
            guard inputSatoshis <= maximumMoneySatoshis else {
                throw .inputAmountExceedsMaximum(actual: inputSatoshis)
            }
            guard outputSatoshis <= maximumMoneySatoshis else {
                throw .outputAmountExceedsMaximum(actual: outputSatoshis)
            }
            guard inputSatoshis >= outputSatoshis else {
                throw .outputAmountExceedsInput(
                    inputSatoshis: inputSatoshis,
                    outputSatoshis: outputSatoshis
                )
            }

            let inputs = inputComponents.map { input in
                OpalFusion.Execution.BCHTransaction.Input(
                    previousTransactionHashLittleEndian: Array(
                        input.previousTransactionHash.reversed()
                    ),
                    previousOutputIndex: input.outputIndex,
                    unlockingScript: [],
                    sequence: UInt32.max
                )
            }
            let outputs = outputComponents.map { output in
                OpalFusion.Execution.BCHTransaction.Output(
                    amountSatoshis: output.amountSatoshis,
                    lockingScript: output.lockingScript
                )
            }
            let transaction = OpalFusion.Execution.BCHTransaction(
                version: 2,
                inputs: inputs,
                outputs: outputs,
                lockTime: 0
            )

            let unsignedTransactionBytes: [UInt8]
            let estimatedFinalSignedByteCount: Int
            do {
                unsignedTransactionBytes = try transaction.serialize()
                let estimatedSignedTransaction = OpalFusion.Execution.BCHTransaction(
                    version: transaction.version,
                    inputs: transaction.inputs.map { input in
                        OpalFusion.Execution.BCHTransaction.Input(
                            previousTransactionHashLittleEndian:
                                input.previousTransactionHashLittleEndian,
                            previousOutputIndex: input.previousOutputIndex,
                            unlockingScript: Array(repeating: 0, count: 100),
                            sequence: input.sequence
                        )
                    },
                    outputs: transaction.outputs,
                    lockTime: transaction.lockTime
                )
                estimatedFinalSignedByteCount = try estimatedSignedTransaction
                    .serialize().count
            } catch {
                preconditionFailure(
                    "Validated Opal-v0 transaction members must always serialize."
                )
            }

            let actualFee = inputSatoshis - outputSatoshis
            let expectedFee = UInt64(estimatedFinalSignedByteCount)
            guard actualFee == expectedFee else {
                throw .feeMismatch(expected: expectedFee, actual: actualFee)
            }

            let transcriptBinding: OpalFusion.Host.MosaicTranscriptBinding
            let transcriptRoot: OpalFusion.Mosaic.Attempt.TranscriptRoot
            do {
                let root = try OpalFusion.Host.MosaicTranscriptBinding.transcriptRoot(
                    profile: .opalV0,
                    manifestDigest: manifest.manifestDigest,
                    commitmentSetDigest: commitmentSet.digest,
                    componentSetDigest: componentSet.digest,
                    unsignedTransactionBytes: unsignedTransactionBytes
                )
                transcriptBinding = try .init(
                    profile: .opalV0,
                    manifestDigest: manifest.manifestDigest,
                    commitmentSetDigest: commitmentSet.digest,
                    componentSetDigest: componentSet.digest,
                    unsignedTransactionBytes: unsignedTransactionBytes,
                    acknowledgedTranscriptRoot: root
                )
                transcriptRoot = try .init(validating: root)
            } catch {
                preconditionFailure(
                    "Validated Opal-v0 values must always form a transcript binding."
                )
            }

            self.contributors = roster.contributors
            self.manifest = manifest
            self.commitmentSet = commitmentSet.commitmentSet
            self.componentSet = componentSet
            self.transaction = transaction
            self.unsignedTransactionBytes = unsignedTransactionBytes
            self.estimatedFinalSignedByteCount = estimatedFinalSignedByteCount
            self.feeSatoshis = actualFee
            self.transcriptBinding = transcriptBinding
            self.transcriptRoot = transcriptRoot
        }

        private static func sumAmounts(
            _ amounts: [UInt64]
        ) -> UInt64 {
            var total: UInt64 = 0
            for amount in amounts {
                let (sum, overflow) = total.addingReportingOverflow(amount)
                guard !overflow else {
                    preconditionFailure(
                        "The bounded Opal-v0 component set cannot overflow UInt64."
                    )
                }
                total = sum
            }
            return total
        }
    }
}

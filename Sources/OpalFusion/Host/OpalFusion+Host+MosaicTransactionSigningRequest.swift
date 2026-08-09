// OpalFusion+Host+MosaicTransactionSigningRequest.swift

public extension OpalFusion.Host {
    /// The transcript-bound transaction material a Mosaic host must validate before signing.
    struct MosaicTransactionSigningRequest: Sendable, Equatable {
        public let reservationReference: MosaicReservationReference
        public let roundIdentifier: [UInt8]
        public let transcriptBinding: MosaicTranscriptBinding
        public let unsignedTransactionBytes: [UInt8]
        public let spentInputs: [ParticipantInput]
        public let localInputIndices: [Int]
        public let expectedLocalOutputs: [ParticipantOutput]
        public let feeRateSatoshisPerByte: UInt64
        public let minimumExcessFeeSatoshis: UInt64
        public let maximumExcessFeeSatoshis: UInt64
        public let requiredExcessFeeSatoshis: UInt64
        public let transactionProfileIdentifier: String

        public init(
            reservationReference: MosaicReservationReference,
            roundIdentifier: [UInt8],
            transcriptBinding: MosaicTranscriptBinding,
            unsignedTransactionBytes: [UInt8],
            spentInputs: [ParticipantInput],
            localInputIndices: [Int],
            expectedLocalOutputs: [ParticipantOutput],
            feeRateSatoshisPerByte: UInt64,
            minimumExcessFeeSatoshis: UInt64,
            maximumExcessFeeSatoshis: UInt64,
            requiredExcessFeeSatoshis: UInt64,
            transactionProfileIdentifier: String
        ) throws {
            guard roundIdentifier.count == 32 else {
                throw MosaicHostContractError.invalidRoundIdentifierLength(
                    actual: roundIdentifier.count
                )
            }
            guard !unsignedTransactionBytes.isEmpty else {
                throw MosaicHostContractError.emptyUnsignedTransaction
            }
            guard transcriptBinding.matches(
                unsignedTransactionBytes: unsignedTransactionBytes
            ) else {
                throw MosaicHostContractError.unsignedTransactionTranscriptMismatch
            }
            guard !spentInputs.isEmpty else {
                throw MosaicHostContractError.emptySpentInputs
            }
            guard !localInputIndices.isEmpty else {
                throw MosaicHostContractError.emptyLocalInputIndices
            }
            guard !expectedLocalOutputs.isEmpty else {
                throw MosaicHostContractError.emptyExpectedLocalOutputs
            }
            guard minimumExcessFeeSatoshis <= maximumExcessFeeSatoshis else {
                throw MosaicHostContractError.invalidExcessFeeRange(
                    minimum: minimumExcessFeeSatoshis,
                    maximum: maximumExcessFeeSatoshis
                )
            }
            guard (minimumExcessFeeSatoshis ... maximumExcessFeeSatoshis)
                .contains(requiredExcessFeeSatoshis) else {
                throw MosaicHostContractError.requiredExcessFeeOutsideRange(
                    required: requiredExcessFeeSatoshis,
                    minimum: minimumExcessFeeSatoshis,
                    maximum: maximumExcessFeeSatoshis
                )
            }
            guard !transactionProfileIdentifier.isEmpty else {
                throw MosaicHostContractError.emptyTransactionProfileIdentifier
            }
            guard transactionProfileIdentifier.unicodeScalars.allSatisfy({
                (0x20 ... 0x7e).contains($0.value)
            }) else {
                throw MosaicHostContractError.nonASCIITransactionProfileIdentifier
            }
            let expectedTransactionProfileIdentifier =
                transcriptBinding.profile.transactionProfileIdentifier
            guard transactionProfileIdentifier == expectedTransactionProfileIdentifier else {
                throw MosaicHostContractError.transactionProfileIdentifierMismatch(
                    expected: expectedTransactionProfileIdentifier,
                    actual: transactionProfileIdentifier
                )
            }

            for (index, spentInput) in spentInputs.enumerated() {
                guard spentInput.outpointTransactionHashBytes.count == 32 else {
                    throw MosaicHostContractError.invalidSpentInputHashLength(
                        index: index,
                        actual: spentInput.outpointTransactionHashBytes.count
                    )
                }
                guard spentInput.amountSatoshis > 0 else {
                    throw MosaicHostContractError.zeroSpentInputAmount(index: index)
                }
                guard !spentInput.lockingScriptBytes.isEmpty else {
                    throw MosaicHostContractError.emptySpentInputLockingScript(index: index)
                }
            }

            for (index, expectedOutput) in expectedLocalOutputs.enumerated() {
                guard expectedOutput.amountSatoshis > 0 else {
                    throw MosaicHostContractError.zeroExpectedLocalOutputAmount(index: index)
                }
                guard !expectedOutput.lockingScriptBytes.isEmpty else {
                    throw MosaicHostContractError.emptyExpectedLocalOutputLockingScript(index: index)
                }
            }

            var uniqueIndices = Set<Int>()
            for index in localInputIndices {
                guard uniqueIndices.insert(index).inserted else {
                    throw MosaicHostContractError.duplicateLocalInputIndex(index)
                }
                guard spentInputs.indices.contains(index) else {
                    throw MosaicHostContractError.localInputIndexOutOfBounds(
                        index: index,
                        inputCount: spentInputs.count
                    )
                }
            }

            self.reservationReference = reservationReference
            self.roundIdentifier = Array(roundIdentifier)
            self.transcriptBinding = transcriptBinding
            self.unsignedTransactionBytes = Array(unsignedTransactionBytes)
            self.spentInputs = spentInputs
            self.localInputIndices = localInputIndices
            self.expectedLocalOutputs = expectedLocalOutputs
            self.feeRateSatoshisPerByte = feeRateSatoshisPerByte
            self.minimumExcessFeeSatoshis = minimumExcessFeeSatoshis
            self.maximumExcessFeeSatoshis = maximumExcessFeeSatoshis
            self.requiredExcessFeeSatoshis = requiredExcessFeeSatoshis
            self.transactionProfileIdentifier = transactionProfileIdentifier
        }

        /// Preserves source compatibility for profiles whose fee range selects one exact value.
        /// Callers using a non-singleton range must migrate to the initializer that supplies
        /// `requiredExcessFeeSatoshis` explicitly.
        @available(
            *,
            deprecated,
            message: "Pass requiredExcessFeeSatoshis explicitly."
        )
        public init(
            reservationReference: MosaicReservationReference,
            roundIdentifier: [UInt8],
            transcriptBinding: MosaicTranscriptBinding,
            unsignedTransactionBytes: [UInt8],
            spentInputs: [ParticipantInput],
            localInputIndices: [Int],
            expectedLocalOutputs: [ParticipantOutput],
            feeRateSatoshisPerByte: UInt64,
            minimumExcessFeeSatoshis: UInt64,
            maximumExcessFeeSatoshis: UInt64,
            transactionProfileIdentifier: String
        ) throws {
            guard minimumExcessFeeSatoshis == maximumExcessFeeSatoshis else {
                throw MosaicHostContractError.requiredExcessFeeUnavailable(
                    minimum: minimumExcessFeeSatoshis,
                    maximum: maximumExcessFeeSatoshis
                )
            }
            try self.init(
                reservationReference: reservationReference,
                roundIdentifier: roundIdentifier,
                transcriptBinding: transcriptBinding,
                unsignedTransactionBytes: unsignedTransactionBytes,
                spentInputs: spentInputs,
                localInputIndices: localInputIndices,
                expectedLocalOutputs: expectedLocalOutputs,
                feeRateSatoshisPerByte: feeRateSatoshisPerByte,
                minimumExcessFeeSatoshis: minimumExcessFeeSatoshis,
                maximumExcessFeeSatoshis: maximumExcessFeeSatoshis,
                requiredExcessFeeSatoshis: minimumExcessFeeSatoshis,
                transactionProfileIdentifier: transactionProfileIdentifier
            )
        }

        public var transcriptRoot: [UInt8] {
            transcriptBinding.transcriptRoot
        }
    }
}

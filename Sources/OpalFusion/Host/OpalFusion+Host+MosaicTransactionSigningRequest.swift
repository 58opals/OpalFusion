// OpalFusion+Host+MosaicTransactionSigningRequest.swift

public extension OpalFusion.Host {
    /// The transcript-bound transaction material a Mosaic host must validate before signing.
    struct MosaicTransactionSigningRequest: Sendable, Equatable {
        public let reservationReference: MosaicReservationReference
        public let roundIdentifier: [UInt8]
        public let transcriptRoot: [UInt8]
        public let unsignedTransactionBytes: [UInt8]
        public let spentInputs: [ParticipantInput]
        public let localInputIndices: [Int]
        public let expectedLocalOutputs: [ParticipantOutput]
        public let feeRateSatoshisPerByte: UInt64
        public let minimumExcessFeeSatoshis: UInt64
        public let maximumExcessFeeSatoshis: UInt64
        public let transactionProfileIdentifier: String

        public init(
            reservationReference: MosaicReservationReference,
            roundIdentifier: [UInt8],
            transcriptRoot: [UInt8],
            unsignedTransactionBytes: [UInt8],
            spentInputs: [ParticipantInput],
            localInputIndices: [Int],
            expectedLocalOutputs: [ParticipantOutput],
            feeRateSatoshisPerByte: UInt64,
            minimumExcessFeeSatoshis: UInt64,
            maximumExcessFeeSatoshis: UInt64,
            transactionProfileIdentifier: String
        ) throws {
            guard roundIdentifier.count == 32 else {
                throw MosaicHostContractError.invalidRoundIdentifierLength(
                    actual: roundIdentifier.count
                )
            }
            guard transcriptRoot.count == 32 else {
                throw MosaicHostContractError.invalidTranscriptRootLength(
                    actual: transcriptRoot.count
                )
            }
            guard !unsignedTransactionBytes.isEmpty else {
                throw MosaicHostContractError.emptyUnsignedTransaction
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
            guard !transactionProfileIdentifier.isEmpty else {
                throw MosaicHostContractError.emptyTransactionProfileIdentifier
            }
            guard transactionProfileIdentifier.unicodeScalars.allSatisfy({
                (0x20 ... 0x7e).contains($0.value)
            }) else {
                throw MosaicHostContractError.nonASCIITransactionProfileIdentifier
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
            self.transcriptRoot = Array(transcriptRoot)
            self.unsignedTransactionBytes = Array(unsignedTransactionBytes)
            self.spentInputs = spentInputs
            self.localInputIndices = localInputIndices
            self.expectedLocalOutputs = expectedLocalOutputs
            self.feeRateSatoshisPerByte = feeRateSatoshisPerByte
            self.minimumExcessFeeSatoshis = minimumExcessFeeSatoshis
            self.maximumExcessFeeSatoshis = maximumExcessFeeSatoshis
            self.transactionProfileIdentifier = transactionProfileIdentifier
        }
    }
}

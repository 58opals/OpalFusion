// OpalFusion+Host+MosaicHostContractError.swift

public extension OpalFusion.Host {
    /// Structural failures in the Mosaic wallet-host contract.
    enum MosaicHostContractError: Error, Sendable, Equatable {
        case emptyAttemptIdentifier
        case invalidNetworkGenesisHashLength(actual: Int)
        case invalidRoundIdentifierLength(actual: Int)
        case invalidTranscriptRootLength(actual: Int)
        case invalidManifestDigestLength(actual: Int)
        case invalidCommitmentSetDigestLength(actual: Int)
        case invalidComponentSetDigestLength(actual: Int)
        case transcriptRootMismatch
        case unsignedTransactionTranscriptMismatch
        case invalidComponentCount(actual: Int)
        case invalidExcessFeeRange(minimum: UInt64, maximum: UInt64)
        case emptyTransactionProfileIdentifier
        case nonASCIITransactionProfileIdentifier
        case emptyReservationInputs
        case emptyReservationOutputs
        case emptyUnsignedTransaction
        case unsignedTransactionTooLarge(actual: Int)
        case emptyCompleteTransaction
        case emptySpentInputs
        case emptyLocalInputIndices
        case emptyExpectedLocalOutputs
        case invalidSpentInputHashLength(index: Int, actual: Int)
        case zeroSpentInputAmount(index: Int)
        case emptySpentInputLockingScript(index: Int)
        case zeroExpectedLocalOutputAmount(index: Int)
        case emptyExpectedLocalOutputLockingScript(index: Int)
        case duplicateLocalInputIndex(Int)
        case localInputIndexOutOfBounds(index: Int, inputCount: Int)
    }
}

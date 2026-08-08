// OpalFusion+Mosaic+OpalV0+WireContractError.swift

extension OpalFusion.Mosaic.OpalV0 {
    enum WireContractError: Error, Sendable, Equatable {
        case unsupportedProfile(OpalFusion.Mosaic.Profile)
        case invalidSaltedComponentDigestLength(actual: Int)
        case invalidAmountCommitment
        case invalidCommunicationPublicKey
        case invalidGroupedCommitmentCount(actual: Int)
        case duplicateGroupedCommitment
        case duplicateSaltedComponentDigest
        case duplicateAmountCommitment
        case duplicateCommunicationPublicKey
        case nonzeroExcessFee(actual: UInt64)
        case invalidPedersenTotalNonce
        case invalidAuthorizationSlot(actual: Int)
        case invalidSaltCommitmentLength(actual: Int)
        case unknownComponentKind(UInt8)
        case invalidInputTransactionHashLength(actual: Int)
        case invalidComponentAmount(actual: UInt64)
        case invalidP2PKHLockingScript
        case invalidRoundIdentifierLength(actual: Int)
        case authorizationTokenRoundMismatch
        case invalidTranscriptRootLength(actual: Int)
        case invalidCommitmentSetCount(actual: Int)
        case duplicateCommitmentSetMember
        case invalidComponentSetCount(actual: Int)
        case duplicateComponentSetMember
        case duplicateSaltCommitment
        case duplicateInputOutpoint
    }
}

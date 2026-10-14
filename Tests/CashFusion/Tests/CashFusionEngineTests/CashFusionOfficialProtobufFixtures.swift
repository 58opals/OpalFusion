// CashFusionOfficialProtobufFixtures.swift

// These official wire bytes are manually derived from Electron Cash 4.4.3 fusion.proto field numbers and protobuf wire rules.
enum CashFusionOfficialProtobufFixtures {
    static let clientHelloEmptyVersionBytes: [UInt8] = [
        0x0A, 0x00
    ]

    static let serverHelloRequiredZeroBytes: [UInt8] = [
        0x10, 0x00,
        0x20, 0x00,
        0x28, 0x00,
        0x30, 0x00
    ]

    static let serverHelloPackedTiersBytes: [UInt8] = [
        0x0A, 0x03, 0x01, 0xAC, 0x02,
        0x10, 0x00,
        0x20, 0x00,
        0x28, 0x00,
        0x30, 0x00
    ]

    static let serverHelloUnpackedTiersBytes: [UInt8] = [
        0x08, 0x01,
        0x08, 0xAC, 0x02,
        0x10, 0x00,
        0x20, 0x00,
        0x28, 0x00,
        0x30, 0x00
    ]

    static let poolTagRequiredZeroBytes: [UInt8] = [
        0x0A, 0x00,
        0x10, 0x00
    ]

    static let joinPoolsEmptyBytes: [UInt8] = []

    static let fusionBeginRequiredZeroBytes: [UInt8] = [
        0x08, 0x00,
        0x12, 0x00,
        0x18, 0x00,
        0x29, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00
    ]

    static let startRoundRequiredZeroBytes: [UInt8] = [
        0x0A, 0x00,
        0x29, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00
    ]

    static let playerCommitRequiredZeroBytes: [UInt8] = [
        0x10, 0x00,
        0x1A, 0x00,
        0x22, 0x00
    ]

    static let fusionResultRequiredFalseBytes: [UInt8] = [
        0x08, 0x00
    ]

    static let fusionResultPackedBadComponentsBytes: [UInt8] = [
        0x08, 0x00,
        0x1A, 0x03, 0x01, 0xAC, 0x02
    ]

    static let fusionResultUnpackedBadComponentsBytes: [UInt8] = [
        0x08, 0x00,
        0x18, 0x01,
        0x18, 0xAC, 0x02
    ]

    static let blindSigResponsesEmptyBytes: [UInt8] = []

    static let allCommitmentsEmptyBytes: [UInt8] = []

    static let shareCovertComponentsEmptyBytes: [UInt8] = []

    static let myProofsListRequiredEmptyRandomNumberBytes: [UInt8] = [
        0x12, 0x00
    ]

    static let theirProofsListEmptyBytes: [UInt8] = []

    static let relayedProofRequiredZeroBytes: [UInt8] = [
        0x0A, 0x00,
        0x10, 0x00,
        0x18, 0x00
    ]

    static let tierStatusDuplicateMapKeyBytes: [UInt8] = [
        0x0A, 0x06,
        0x08, 0x01,
        0x12, 0x02, 0x08, 0x01,
        0x0A, 0x06,
        0x08, 0x01,
        0x12, 0x02, 0x10, 0x02
    ]

    static let tierStatusLastWinsMapKeyBytes: [UInt8] = [
        0x0A, 0x06,
        0x08, 0x01,
        0x12, 0x02, 0x10, 0x02
    ]

    static let blameProofSessionKeyBytes: [UInt8] = [
        0x08, 0x00,
        0x12, 0x01, 0xAA
    ]

    static let blameProofPrivateKeyWithReasonBytes: [UInt8] = [
        0x08, 0x01,
        0x1A, 0x01, 0xBB,
        0x20, 0x01,
        0x2A, 0x02, 0x6F, 0x6B
    ]

    static let covertComponentWithoutRoundKeyBytes: [UInt8] = [
        0x12, 0x01, 0x30,
        0x1A, 0x01, 0x31
    ]

    static let covertTransactionSignatureWithoutRoundKeyBytes: [UInt8] = [
        0x10, 0x00,
        0x1A, 0x01, 0x61
    ]

    static let errorMessageBytes: [UInt8] = [
        0x0A, 0x02, 0x6F, 0x6B
    ]

    static let emptyErrorBytes: [UInt8] = []

    static let clientBlamesEnvelopeWithoutDecrypterBytes: [UInt8] = [
        0x32, 0x04,
        0x0A, 0x02, 0x08, 0x01
    ]

    static let conflictingClientEnvelopeBytes: [UInt8] = [
        0x0A, 0x03,
        0x0A, 0x01, 0x01,
        0x12, 0x00
    ]

    static let serverFusionBeginEnvelopeWithInvalidDomainBytes: [UInt8] = [
        0x1A, 0x03,
        0x12, 0x01, 0xFF
    ]

    static let serverFailureEnvelopeWithInvalidMessageBytes: [UInt8] = [
        0x7A, 0x03,
        0x0A, 0x01, 0xFF
    ]

    static let malformedServerEnvelopeLengthBytes: [UInt8] = [
        0x1A, 0x02, 0x08
    ]

    static let serverHelloEnvelopeWithUnknownPrefixBytes: [UInt8] = [
        0x98, 0x06, 0x01,
        0x0A, 0x08,
        0x10, 0x00,
        0x20, 0x00,
        0x28, 0x00,
        0x30, 0x00
    ]

    static let conflictingCovertEnvelopeBytes: [UInt8] = [
        0x0A, 0x06,
        0x12, 0x01, 0x30,
        0x1A, 0x01, 0x31,
        0x1A, 0x00
    ]

    static let conflictingCovertResponseEnvelopeBytes: [UInt8] = [
        0x0A, 0x00,
        0x7A, 0x00
    ]

    static let covertFailureEnvelopeWithInvalidMessageBytes: [UInt8] = [
        0x7A, 0x03,
        0x0A, 0x01, 0xFF
    ]

    static let malformedCovertResponseLengthBytes: [UInt8] = [
        0x7A, 0x02, 0x0A
    ]

    static let covertMessageEnvelopeWithUnknownPrefixBytes: [UInt8] = [
        0x98, 0x06, 0x01,
        0x0A, 0x06,
        0x12, 0x01, 0x30,
        0x1A, 0x01, 0x31
    ]
}

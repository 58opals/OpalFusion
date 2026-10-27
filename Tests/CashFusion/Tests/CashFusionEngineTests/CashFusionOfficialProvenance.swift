// CashFusionOfficialProvenance.swift

/// Current independent qualification of the unchanged manual fixtures.
/// See docs/reference-fixture-provenance.md; no upstream Python is executed.
enum CashFusionOfficialProvenance {
    static let sourceCommit = "124a6d9be80190b987fbb4854d9931e9073b17f2"
    static let schemaSHA256 = "22b8a137176c28ecd12bb6fde8c44662b555a470e79a5203105e363abf9307da"
    static let framingSHA256 = "662d803626da26b304d88f139e35508f6ef0416f4c264ea77c767ec387307ef8"
    static let protocolSHA256 = "1848765adcbd8cb5b235693aeaf824a0aa28df6f3d66570efac01e740b9728fb"
    static let licenseSHA256 = "3e6dae555eb92787fc82d1d48355677f454c7f65aeb38d3f9e72bf9a3daf034b"
    static let fixtureSHA256 = "deaed7aa5129170e3269c262d4fc34c2f9906d9bc34ccce9a35fd566fcb3ffd5"

    static let fixtures: [(name: String, bytes: [UInt8])] = [
        ("allCommitmentsEmptyBytes", CashFusionOfficialProtobufFixtures.allCommitmentsEmptyBytes),
        ("blameProofPrivateKeyWithReasonBytes", CashFusionOfficialProtobufFixtures.blameProofPrivateKeyWithReasonBytes),
        ("blameProofSessionKeyBytes", CashFusionOfficialProtobufFixtures.blameProofSessionKeyBytes),
        ("blindSigResponsesEmptyBytes", CashFusionOfficialProtobufFixtures.blindSigResponsesEmptyBytes),
        ("clientBlamesEnvelopeWithoutDecrypterBytes", CashFusionOfficialProtobufFixtures.clientBlamesEnvelopeWithoutDecrypterBytes),
        ("clientHelloEmptyVersionBytes", CashFusionOfficialProtobufFixtures.clientHelloEmptyVersionBytes),
        ("conflictingClientEnvelopeBytes", CashFusionOfficialProtobufFixtures.conflictingClientEnvelopeBytes),
        ("conflictingCovertEnvelopeBytes", CashFusionOfficialProtobufFixtures.conflictingCovertEnvelopeBytes),
        ("conflictingCovertResponseEnvelopeBytes", CashFusionOfficialProtobufFixtures.conflictingCovertResponseEnvelopeBytes),
        ("covertComponentWithoutRoundKeyBytes", CashFusionOfficialProtobufFixtures.covertComponentWithoutRoundKeyBytes),
        ("covertFailureEnvelopeWithInvalidMessageBytes", CashFusionOfficialProtobufFixtures.covertFailureEnvelopeWithInvalidMessageBytes),
        ("covertMessageEnvelopeWithUnknownPrefixBytes", CashFusionOfficialProtobufFixtures.covertMessageEnvelopeWithUnknownPrefixBytes),
        ("covertTransactionSignatureWithoutRoundKeyBytes", CashFusionOfficialProtobufFixtures.covertTransactionSignatureWithoutRoundKeyBytes),
        ("emptyErrorBytes", CashFusionOfficialProtobufFixtures.emptyErrorBytes),
        ("errorMessageBytes", CashFusionOfficialProtobufFixtures.errorMessageBytes),
        ("fusionBeginRequiredZeroBytes", CashFusionOfficialProtobufFixtures.fusionBeginRequiredZeroBytes),
        ("fusionResultPackedBadComponentsBytes", CashFusionOfficialProtobufFixtures.fusionResultPackedBadComponentsBytes),
        ("fusionResultRequiredFalseBytes", CashFusionOfficialProtobufFixtures.fusionResultRequiredFalseBytes),
        ("fusionResultUnpackedBadComponentsBytes", CashFusionOfficialProtobufFixtures.fusionResultUnpackedBadComponentsBytes),
        ("joinPoolsEmptyBytes", CashFusionOfficialProtobufFixtures.joinPoolsEmptyBytes),
        ("malformedCovertResponseLengthBytes", CashFusionOfficialProtobufFixtures.malformedCovertResponseLengthBytes),
        ("malformedServerEnvelopeLengthBytes", CashFusionOfficialProtobufFixtures.malformedServerEnvelopeLengthBytes),
        ("myProofsListRequiredEmptyRandomNumberBytes", CashFusionOfficialProtobufFixtures.myProofsListRequiredEmptyRandomNumberBytes),
        ("playerCommitRequiredZeroBytes", CashFusionOfficialProtobufFixtures.playerCommitRequiredZeroBytes),
        ("poolTagRequiredZeroBytes", CashFusionOfficialProtobufFixtures.poolTagRequiredZeroBytes),
        ("relayedProofRequiredZeroBytes", CashFusionOfficialProtobufFixtures.relayedProofRequiredZeroBytes),
        ("serverFailureEnvelopeWithInvalidMessageBytes", CashFusionOfficialProtobufFixtures.serverFailureEnvelopeWithInvalidMessageBytes),
        ("serverFusionBeginEnvelopeWithInvalidDomainBytes", CashFusionOfficialProtobufFixtures.serverFusionBeginEnvelopeWithInvalidDomainBytes),
        ("serverHelloEnvelopeWithUnknownPrefixBytes", CashFusionOfficialProtobufFixtures.serverHelloEnvelopeWithUnknownPrefixBytes),
        ("serverHelloPackedTiersBytes", CashFusionOfficialProtobufFixtures.serverHelloPackedTiersBytes),
        ("serverHelloRequiredZeroBytes", CashFusionOfficialProtobufFixtures.serverHelloRequiredZeroBytes),
        ("serverHelloUnpackedTiersBytes", CashFusionOfficialProtobufFixtures.serverHelloUnpackedTiersBytes),
        ("shareCovertComponentsEmptyBytes", CashFusionOfficialProtobufFixtures.shareCovertComponentsEmptyBytes),
        ("startRoundRequiredZeroBytes", CashFusionOfficialProtobufFixtures.startRoundRequiredZeroBytes),
        ("theirProofsListEmptyBytes", CashFusionOfficialProtobufFixtures.theirProofsListEmptyBytes),
        ("tierStatusDuplicateMapKeyBytes", CashFusionOfficialProtobufFixtures.tierStatusDuplicateMapKeyBytes),
        ("tierStatusLastWinsMapKeyBytes", CashFusionOfficialProtobufFixtures.tierStatusLastWinsMapKeyBytes),
    ]
}

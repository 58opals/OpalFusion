// OpalFusion+Mosaic+OpalMainnetAlpha.swift

extension OpalFusion.Mosaic {
    /// Internal constants frozen by `Mosaic/0-opal-mainnet-alpha.3`.
    enum OpalMainnetAlpha {
        static let mainnetGenesisHash: [UInt8] = [
            0x00, 0x00, 0x00, 0x00, 0x00, 0x19, 0xd6, 0x68,
            0x9c, 0x08, 0x5a, 0xe1, 0x65, 0x83, 0x1e, 0x93,
            0x4f, 0xf7, 0x63, 0xae, 0x46, 0xa2, 0xa6, 0xc1,
            0x72, 0xb3, 0xf1, 0xb6, 0x0a, 0x8c, 0xe2, 0x6f
        ]

        static let componentCountPerContributor = 23
        static let feeRateSatoshisPerByte: UInt64 = 1
        static let minimumExcessFeeSatoshis: UInt64 = 1
        static let maximumExcessFeeSatoshis: UInt64 = 2
        static let fixedTransactionOverheadByteCount = 10
        static let opaquePoolIdentifierByteCount = 32
        static let bchSchnorrSignatureByteCount = 64
        static let compressedPublicKeyByteCount = 33
        static let standardP2PKHUnlockingScriptByteCount = 100

        static let blindSigningVerificationKeyByteCount = 342
        static let maximumTransactionComponentCount = 8
            * OpalFusion.Mosaic.OpalV0.componentAuthorizationCountPerContributor
        static let maximumTransactionInputCount =
            maximumTransactionComponentCount - 1
        static let maximumTransactionOutputCount =
            maximumTransactionComponentCount - 1

        static let playerCommitCanonicalByteCount = 32 + 32
            + 4
            + componentCountPerContributor
                * OpalFusion.Mosaic.OpalV0.componentCommitmentByteCount
            + 8 + 32
            + 4
            + componentCountPerContributor
                * (1 + OpalFusion.Mosaic.OpalV0.authorizationMaterialByteCount)

        static let authorizationResponseSetCanonicalByteCount = 32 + 32 + 32
            + 4
            + componentCountPerContributor
                * (1 + OpalFusion.Mosaic.OpalV0.authorizationMaterialByteCount)

        static func preSignAcknowledgementSetCanonicalByteCount(
            contributorCount: Int
        ) -> Int {
            32 + 32 + 4 + contributorCount * (32 + bchSchnorrSignatureByteCount)
        }

        static func completeManifestCanonicalByteCount(
            candidateCount: Int
        ) -> Int {
            let contributorCount = candidateCount - 1
            let profile = OpalFusion.Mosaic.Profile.opalMainnetAlpha
            return 4 + profile.rawValue.utf8.count
                + 32 + 32 + 32 + 32
                + 4 + candidateCount * (32 + 1)
                + 32
                + 4 + contributorCount * 32
                + opaquePoolIdentifierByteCount
                + 1 + 8 + 8 + 8
                + 4 + blindSigningVerificationKeyByteCount
                + 32
                + 4 + profile.transportProfile.rawValue.utf8.count
                + 32
                + 6 * 8
                + 4 + profile.transactionProfileIdentifier.utf8.count
                + 4 + candidateCount * (32 + 64)
        }

        static let minimumCompleteTransactionPayloadByteCount = 32 + 32 + 4
            + 4 + 1 + 141 + 1 + 34 + 4
        static let maximumCompleteTransactionPayloadByteCount = 32 + 32 + 4
            + 4 + 1 + maximumTransactionInputCount * 141
            + 1 + 34 + 4
        static let maximumControlEnvelopeByteCount = 4_092
        static let maximumAnonymousEnvelopeByteCount = 4_092
        static let controlEnvelopeFixedOverheadByteCount = 280
        static let maximumControlPayloadByteCount =
            maximumControlEnvelopeByteCount - controlEnvelopeFixedOverheadByteCount
        static let anonymousEnvelopeFixedOverheadByteCount = 219
        static let maximumAnonymousPayloadByteCount =
            maximumAnonymousEnvelopeByteCount
                - anonymousEnvelopeFixedOverheadByteCount
        static let aggregateFragmentFramingByteCount = 13
        static let maximumAggregateFragmentBodyByteCount =
            maximumControlPayloadByteCount - aggregateFragmentFramingByteCount
    }
}

// CashFusionPrimaryMessageCodecValidator.swift

@testable import OpalFusion
import Testing

struct CashFusionPrimaryMessageCodecValidator {
    @Test("CashFusion primary codec matches pinned client message bytes")
    func validateClientMessagePinnedByteParity() throws {
        #expect(
            PrimaryRuntimeTestFixtures.clientMessages.count
                == CashFusionPinnedProtobufFixtures.primaryClientMessageBytes.count
        )

        for (message, pinnedBytes) in zip(
            PrimaryRuntimeTestFixtures.clientMessages,
            CashFusionPinnedProtobufFixtures.primaryClientMessageBytes
        ) {
            let nativeBytes = try OpalFusion.Wire.CashFusionPrimaryMessageCodec.encode(message)

            #expect(nativeBytes == pinnedBytes)
            #expect(
                try OpalFusion.Wire.CashFusionPrimaryMessageCodec.decodeClient(
                    pinnedBytes
                ) == message
            )
        }
    }

    @Test("CashFusion primary codec matches pinned server message bytes")
    func validateServerMessagePinnedByteParity() throws {
        #expect(
            PrimaryRuntimeTestFixtures.serverMessages.count
                == CashFusionPinnedProtobufFixtures.primaryServerMessageBytes.count
        )

        for (message, pinnedBytes) in zip(
            PrimaryRuntimeTestFixtures.serverMessages,
            CashFusionPinnedProtobufFixtures.primaryServerMessageBytes
        ) {
            let nativeBytes = try OpalFusion.Wire.CashFusionPrimaryMessageCodec.encode(message)

            #expect(nativeBytes == pinnedBytes)
            #expect(
                try OpalFusion.Wire.CashFusionPrimaryMessageCodec.decodeServer(
                    pinnedBytes
                ) == message
            )
        }
    }

    @Test("CashFusion primary codec handles optional, map, and packed edge cases")
    func validateFocusedFieldParity() throws {
        let clientMessages: [OpalFusion.ProtocolModel.ClientMessage] = [
            .clientHello(
                .init(
                    versionBytes: [0x01],
                    genesisHash: nil
                )
            ),
            .joinPools(
                .init(
                    tiers: [1, 300],
                    tags: [
                        .init(
                            identifier: [0xA0],
                            limit: 0,
                            noIp: nil
                        )
                    ]
                )
            ),
            .blames(
                .init(
                    blames: [
                        .init(
                            proofIndex: 7,
                            decrypter: .privateKey(secretBytes: [0xB0]),
                            requiresBlockchainLookup: true,
                            reason: nil
                        )
                    ]
                )
            )
        ]
        let serverMessages: [OpalFusion.ProtocolModel.ServerMessage] = [
            .serverHello(
                .init(
                    tiers: [1, 300],
                    numberOfComponents: 0,
                    componentFeeRateSatoshisPerKb: 0,
                    minimumExcessFeeSatoshis: 0,
                    maximumExcessFeeSatoshis: 0,
                    donationAddress: nil
                )
            ),
            .tierStatusUpdate(
                .init(
                    statusesByTier: [
                        1: .init(),
                        300: .init(
                            playerCount: 1,
                            minimumPlayerCount: 2,
                            maximumPlayerCount: 3,
                            timeRemainingSeconds: 4
                        )
                    ]
                )
            ),
            .fusionResult(
                .init(
                    isSuccess: false,
                    transactionSignatures: [],
                    badComponentIndices: [1, 300]
                )
            )
        ]

        #expect(
            clientMessages.count
                == CashFusionPinnedProtobufFixtures.primaryFocusedClientMessageBytes.count
        )
        #expect(
            serverMessages.count
                == CashFusionPinnedProtobufFixtures.primaryFocusedServerMessageBytes.count
        )

        for (message, pinnedBytes) in zip(
            clientMessages,
            CashFusionPinnedProtobufFixtures.primaryFocusedClientMessageBytes
        ) {
            let nativeBytes = try OpalFusion.Wire.CashFusionPrimaryMessageCodec.encode(message)
            #expect(nativeBytes == pinnedBytes)
            #expect(
                try OpalFusion.Wire.CashFusionPrimaryMessageCodec.decodeClient(
                    pinnedBytes
                ) == message
            )
        }

        for (message, pinnedBytes) in zip(
            serverMessages,
            CashFusionPinnedProtobufFixtures.primaryFocusedServerMessageBytes
        ) {
            let nativeBytes = try OpalFusion.Wire.CashFusionPrimaryMessageCodec.encode(message)
            #expect(nativeBytes == pinnedBytes)
            #expect(
                try OpalFusion.Wire.CashFusionPrimaryMessageCodec.decodeServer(
                    pinnedBytes
                ) == message
            )
        }
    }

}

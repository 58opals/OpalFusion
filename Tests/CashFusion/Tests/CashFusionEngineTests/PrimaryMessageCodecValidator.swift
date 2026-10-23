// PrimaryMessageCodecValidator.swift

@testable import CashFusionEngine
@testable import OpalFusionCore
import Testing

struct PrimaryMessageCodecValidator {
    @Test("Primary protobuf bridge round-trips all modeled client messages")
    func validateClientMessageRoundTrips() throws {
        let encoder = OpalFusion.Wire.PrimaryMessageEncoder()
        let decoder = OpalFusion.Wire.PrimaryMessageDecoder()

        for message in PrimaryRuntimeTestFixtures.clientMessages {
            let bytes = try encoder.encode(message)
            let decoded = try decoder.decodeClient(bytes)
            #expect(decoded == message)
        }
    }

    @Test("Primary protobuf bridge round-trips all modeled server messages")
    func validateServerMessageRoundTrips() throws {
        let encoder = OpalFusion.Wire.PrimaryMessageEncoder()
        let decoder = OpalFusion.Wire.PrimaryMessageDecoder()

        for message in PrimaryRuntimeTestFixtures.serverMessages {
            let bytes = try encoder.encode(message)
            let decoded = try decoder.decodeServer(bytes)
            #expect(decoded == message)
        }
    }

    @Test("Primary protobuf bridge preserves official blame variants and lookup hints")
    func validateBlameProofVariantPreservation() throws {
        let encoder = OpalFusion.Wire.PrimaryMessageEncoder()
        let decoder = OpalFusion.Wire.PrimaryMessageDecoder()
        let message = OpalFusion.ProtocolModel.ClientMessage.blames(
            .init(
                blames: [
                    .init(
                        proofIndex: 0,
                        decrypter: .sessionKey(secretBytes: [0x83]),
                        requiresBlockchainLookup: false,
                        reason: "session proof"
                    ),
                    .init(
                        proofIndex: 1,
                        decrypter: .privateKey(secretBytes: [0x84]),
                        requiresBlockchainLookup: true,
                        reason: "private proof"
                    )
                ]
            )
        )

        let decoded = try decoder.decodeClient(encoder.encode(message))

        #expect(decoded == message)
        guard case let .blames(blames) = decoded else {
            Issue.record("Expected decoded client message to carry Blames")
            return
        }
        try #require(blames.blames.count == 2)
        #expect(blames.blames[0].requiresBlockchainLookup == false)
        #expect(blames.blames[1].requiresBlockchainLookup == true)
    }

    @Test("Primary protobuf bridge matches pinned oneof cases for interoperability messages")
    func validatePinnedCompatibilityCases() throws {
        let encoder = OpalFusion.Wire.PrimaryMessageEncoder()
        let decoder = OpalFusion.Wire.PrimaryMessageDecoder()

        let clientHello = OpalFusion.ProtocolModel.ClientMessage.clientHello(
            PrimaryRuntimeTestFixtures.clientHello
        )
        #expect(try encoder.encode(clientHello) == CashFusionPinnedProtobufFixtures.primaryClientMessageBytes[0])
        #expect(
            try decoder.decodeClient(
                CashFusionPinnedProtobufFixtures.primaryClientMessageBytes[0]
            ) == clientHello
        )

        let serverHello = OpalFusion.ProtocolModel.ServerMessage.serverHello(
            PrimaryRuntimeTestFixtures.serverHello
        )
        #expect(
            try encoder.encode(serverHello)
                == CashFusionPinnedProtobufFixtures.primaryServerMessageBytes[0]
        )
        #expect(
            try decoder.decodeServer(
                CashFusionPinnedProtobufFixtures.primaryServerMessageBytes[0]
            ) == serverHello
        )

        let fusionBegin = OpalFusion.ProtocolModel.ServerMessage.fusionBegin(
            PrimaryRuntimeTestFixtures.fusionBegin
        )
        #expect(
            try encoder.encode(fusionBegin)
                == CashFusionPinnedProtobufFixtures.primaryServerMessageBytes[2]
        )
        #expect(
            try decoder.decodeServer(
                CashFusionPinnedProtobufFixtures.primaryServerMessageBytes[2]
            ) == fusionBegin
        )

        let startRound = OpalFusion.ProtocolModel.ServerMessage.startRound(
            PrimaryRuntimeTestFixtures.startRound
        )
        #expect(
            try encoder.encode(startRound)
                == CashFusionPinnedProtobufFixtures.primaryServerMessageBytes[3]
        )
        #expect(
            try decoder.decodeServer(
                CashFusionPinnedProtobufFixtures.primaryServerMessageBytes[3]
            ) == startRound
        )

        let allCommitments = OpalFusion.ProtocolModel.ServerMessage.allCommitments(
            PrimaryRuntimeTestFixtures.allCommitments
        )
        #expect(
            try encoder.encode(allCommitments)
                == CashFusionPinnedProtobufFixtures.primaryServerMessageBytes[5]
        )
        #expect(
            try decoder.decodeServer(
                CashFusionPinnedProtobufFixtures.primaryServerMessageBytes[5]
            ) == allCommitments
        )

        let fusionResult = OpalFusion.ProtocolModel.ServerMessage.fusionResult(
            PrimaryRuntimeTestFixtures.successResult
        )
        #expect(
            try encoder.encode(fusionResult)
                == CashFusionPinnedProtobufFixtures.primaryServerMessageBytes[7]
        )
        #expect(
            try decoder.decodeServer(
                CashFusionPinnedProtobufFixtures.primaryServerMessageBytes[7]
            ) == fusionResult
        )

        let theirProofsList = OpalFusion.ProtocolModel.ServerMessage.theirProofsList(
            PrimaryRuntimeTestFixtures.theirProofsList
        )
        #expect(
            try encoder.encode(theirProofsList)
                == CashFusionPinnedProtobufFixtures.primaryServerMessageBytes[8]
        )
        #expect(
            try decoder.decodeServer(
                CashFusionPinnedProtobufFixtures.primaryServerMessageBytes[8]
            ) == theirProofsList
        )

        let restartRound = OpalFusion.ProtocolModel.ServerMessage.restartRound(.init())
        #expect(
            try encoder.encode(restartRound)
                == CashFusionPinnedProtobufFixtures.primaryServerMessageBytes[9]
        )
        #expect(
            try decoder.decodeServer(
                CashFusionPinnedProtobufFixtures.primaryServerMessageBytes[9]
            ) == restartRound
        )

        let serverFailure = OpalFusion.ProtocolModel.ServerMessage.serverFailure(
            PrimaryRuntimeTestFixtures.serverFailure
        )
        #expect(
            try encoder.encode(serverFailure)
                == CashFusionPinnedProtobufFixtures.primaryServerMessageBytes[10]
        )
        #expect(
            try decoder.decodeServer(
                CashFusionPinnedProtobufFixtures.primaryServerMessageBytes[10]
            ) == serverFailure
        )
    }
}

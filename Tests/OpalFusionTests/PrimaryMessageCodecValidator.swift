// PrimaryMessageCodecValidator.swift

@testable import OpalFusion
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

    @Test("Primary protobuf bridge preserves representative optional and repeated fields")
    func validateRepresentativeFieldPreservation() throws {
        let encoder = OpalFusion.Wire.PrimaryMessageEncoder()
        let decoder = OpalFusion.Wire.PrimaryMessageDecoder()

        let joinPools = try decoder.decodeClient(
            encoder.encode(.joinPools(PrimaryRuntimeTestFixtures.joinPools))
        )
        let tierStatusUpdate = try decoder.decodeServer(
            encoder.encode(.tierStatusUpdate(PrimaryRuntimeTestFixtures.tierStatusUpdate))
        )
        let startRound = try decoder.decodeServer(
            encoder.encode(.startRound(PrimaryRuntimeTestFixtures.startRound))
        )
        let shareCovertComponents = try decoder.decodeServer(
            encoder.encode(.shareCovertComponents(PrimaryRuntimeTestFixtures.sharedComponents))
        )
        let blames = try decoder.decodeClient(
            encoder.encode(.blames(PrimaryRuntimeTestFixtures.blames))
        )

        #expect(joinPools == .joinPools(PrimaryRuntimeTestFixtures.joinPools))
        #expect(tierStatusUpdate == .tierStatusUpdate(PrimaryRuntimeTestFixtures.tierStatusUpdate))
        #expect(startRound == .startRound(PrimaryRuntimeTestFixtures.startRound))
        #expect(
            shareCovertComponents
                == .shareCovertComponents(PrimaryRuntimeTestFixtures.sharedComponents)
        )
        #expect(blames == .blames(PrimaryRuntimeTestFixtures.blames))
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

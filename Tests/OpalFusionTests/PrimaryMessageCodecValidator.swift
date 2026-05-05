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
    func validateGeneratedCompatibilityCases() throws {
        let encoder = OpalFusion.Wire.PrimaryMessageEncoder()

        let clientHelloEnvelope = try Fusion_ClientMessage(
            serializedBytes: encoder.encode(.clientHello(PrimaryRuntimeTestFixtures.clientHello))
        )
        guard case let .clienthello(clientHello)? = clientHelloEnvelope.msg else {
            Issue.record("Expected clienthello envelope case")
            return
        }
        #expect([UInt8](clientHello.version) == PrimaryRuntimeTestFixtures.clientHello.versionBytes)
        #expect(clientHello.hasGenesisHash)
        #expect(
            [UInt8](clientHello.genesisHash)
                == (PrimaryRuntimeTestFixtures.clientHello.genesisHash ?? [])
        )

        let serverHelloEnvelope = try Fusion_ServerMessage(
            serializedBytes: encoder.encode(.serverHello(PrimaryRuntimeTestFixtures.serverHello))
        )
        guard case let .serverhello(serverHello)? = serverHelloEnvelope.msg else {
            Issue.record("Expected serverhello envelope case")
            return
        }
        #expect(serverHello.tiers == PrimaryRuntimeTestFixtures.serverHello.tiers)
        #expect(serverHello.hasDonationAddress)
        #expect(
            serverHello.donationAddress
                == (PrimaryRuntimeTestFixtures.serverHello.donationAddress ?? "")
        )

        let fusionBeginEnvelope = try Fusion_ServerMessage(
            serializedBytes: encoder.encode(.fusionBegin(PrimaryRuntimeTestFixtures.fusionBegin))
        )
        guard case let .fusionbegin(fusionBegin)? = fusionBeginEnvelope.msg else {
            Issue.record("Expected fusionbegin envelope case")
            return
        }
        #expect(fusionBegin.tier == PrimaryRuntimeTestFixtures.fusionBegin.tier)
        #expect(
            String(decoding: fusionBegin.covertDomain, as: UTF8.self)
                == PrimaryRuntimeTestFixtures.fusionBegin.covertDomain
        )
        #expect(fusionBegin.covertPort == PrimaryRuntimeTestFixtures.fusionBegin.covertPort)

        let startRoundEnvelope = try Fusion_ServerMessage(
            serializedBytes: encoder.encode(.startRound(PrimaryRuntimeTestFixtures.startRound))
        )
        guard case let .startround(startRound)? = startRoundEnvelope.msg else {
            Issue.record("Expected startround envelope case")
            return
        }
        #expect([UInt8](startRound.roundPubkey) == PrimaryRuntimeTestFixtures.startRound.roundPublicKey)
        #expect(
            startRound.blindNoncePoints.map { [UInt8]($0) }
                == PrimaryRuntimeTestFixtures.startRound.blindNoncePoints
        )

        let commitmentsEnvelope = try Fusion_ServerMessage(
            serializedBytes: encoder.encode(.allCommitments(PrimaryRuntimeTestFixtures.allCommitments))
        )
        guard case let .allcommitments(allCommitments)? = commitmentsEnvelope.msg else {
            Issue.record("Expected allcommitments envelope case")
            return
        }
        #expect(allCommitments.initialCommitments.count == 1)
        let nestedCommitment = try Fusion_InitialCommitment(
            serializedBytes: allCommitments.initialCommitments[0]
        )
        #expect(
            [UInt8](nestedCommitment.communicationKey)
                == PrimaryRuntimeTestFixtures.initialCommitment.communicationPublicKey
        )

        let fusionResultEnvelope = try Fusion_ServerMessage(
            serializedBytes: encoder.encode(.fusionResult(PrimaryRuntimeTestFixtures.successResult))
        )
        guard case let .fusionresult(fusionResult)? = fusionResultEnvelope.msg else {
            Issue.record("Expected fusionresult envelope case")
            return
        }
        #expect(fusionResult.ok)
        #expect(
            fusionResult.txsignatures.map { [UInt8]($0) }
                == PrimaryRuntimeTestFixtures.successResult.transactionSignatures
        )

        let proofsEnvelope = try Fusion_ServerMessage(
            serializedBytes: encoder.encode(.theirProofsList(PrimaryRuntimeTestFixtures.theirProofsList))
        )
        guard case let .theirproofslist(theirProofsList)? = proofsEnvelope.msg else {
            Issue.record("Expected theirproofslist envelope case")
            return
        }
        #expect(theirProofsList.proofs.count == 1)
        #expect(
            [UInt8](theirProofsList.proofs[0].encryptedProof)
                == PrimaryRuntimeTestFixtures.theirProofsList.proofs[0].encryptedProof
        )

        let restartEnvelope = try Fusion_ServerMessage(
            serializedBytes: encoder.encode(.restartRound(.init()))
        )
        guard case .restartround? = restartEnvelope.msg else {
            Issue.record("Expected restartround envelope case")
            return
        }

        let errorEnvelope = try Fusion_ServerMessage(
            serializedBytes: encoder.encode(.serverFailure(PrimaryRuntimeTestFixtures.serverFailure))
        )
        guard case let .error(error)? = errorEnvelope.msg else {
            Issue.record("Expected error envelope case")
            return
        }
        #expect(error.message == (PrimaryRuntimeTestFixtures.serverFailure.message ?? ""))
    }

}

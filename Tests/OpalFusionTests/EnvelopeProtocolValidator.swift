// EnvelopeProtocolValidator.swift

import OpalFusion
import Testing

struct EnvelopeProtocolValidator {
    @Test("Envelope protocol models preserve typed payloads across every wrapper family")
    func validateEnvelopeProtocolModels() {
        let clientHello = OpalFusion.ProtocolModel.ClientHello(
            versionBytes: [0x61],
            genesisHash: [0xAA]
        )
        let joinPools = OpalFusion.ProtocolModel.JoinPools(
            tiers: [100_000],
            tags: []
        )
        let playerCommit = OpalFusion.ProtocolModel.PlayerCommit(
            initialCommitments: [],
            excessFeeSatoshis: 1,
            pedersenTotalNonce: [0x01],
            randomNumberCommitment: [0x02],
            blindSignatureRequests: []
        )
        let myProofsList = OpalFusion.ProtocolModel.MyProofsList(
            encryptedProofs: [[0x03]],
            randomNumber: [0x04]
        )
        let blames = OpalFusion.ProtocolModel.Blames(
            blames: []
        )
        let serverHello = OpalFusion.ProtocolModel.ServerHello(
            tiers: [100_000],
            numberOfComponents: 37,
            componentFeeRateSatoshisPerKb: 1_000,
            minimumExcessFeeSatoshis: 100,
            maximumExcessFeeSatoshis: 500
        )
        let tierStatusUpdate = OpalFusion.ProtocolModel.TierStatusUpdate(
            statusesByTier: [:]
        )
        let fusionBegin = OpalFusion.ProtocolModel.FusionBegin(
            tier: 100_000,
            covertDomain: "covert.example.org",
            covertPort: 7447,
            serverTimeUnixSeconds: 1_700_000_000
        )
        let startRound = OpalFusion.ProtocolModel.StartRound(
            roundPublicKey: [0x05],
            blindNoncePoints: [[0x06]],
            serverTimeUnixSeconds: 1_700_000_001
        )
        let blindSignatureResponses = OpalFusion.ProtocolModel.BlindSignatureResponses(
            responses: []
        )
        let allCommitments = OpalFusion.ProtocolModel.AllCommitments(
            initialCommitments: []
        )
        let shareCovertComponents = OpalFusion.ProtocolModel.ShareCovertComponents(
            serializedComponents: [[0x07]]
        )
        let fusionResult = OpalFusion.ProtocolModel.FusionResult(
            isSuccess: true,
            transactionSignatures: [[0x08]],
            badComponentIndices: []
        )
        let theirProofsList = OpalFusion.ProtocolModel.TheirProofsList(
            proofs: []
        )
        let restartRound = OpalFusion.ProtocolModel.RestartRound()
        let serverFailure = OpalFusion.ProtocolModel.ServerFailure(
            message: "bad request"
        )
        let covertComponent = OpalFusion.ProtocolModel.CovertComponent(
            signature: [0x09],
            serializedComponent: [0x0A]
        )
        let covertTransactionSignature = OpalFusion.ProtocolModel.CovertTransactionSignature(
            inputIndex: 2,
            transactionSignature: [0x0B]
        )
        let ping = OpalFusion.ProtocolModel.Ping()
        let acknowledgement = OpalFusion.ProtocolModel.Acknowledgement()

        #expect(OpalFusion.ProtocolModel.ClientMessage.clientHello(clientHello) == .clientHello(clientHello))
        #expect(OpalFusion.ProtocolModel.ClientMessage.joinPools(joinPools) == .joinPools(joinPools))
        #expect(OpalFusion.ProtocolModel.ClientMessage.playerCommit(playerCommit) == .playerCommit(playerCommit))
        #expect(OpalFusion.ProtocolModel.ClientMessage.myProofsList(myProofsList) == .myProofsList(myProofsList))
        #expect(OpalFusion.ProtocolModel.ClientMessage.blames(blames) == .blames(blames))

        #expect(OpalFusion.ProtocolModel.ServerMessage.serverHello(serverHello) == .serverHello(serverHello))
        #expect(OpalFusion.ProtocolModel.ServerMessage.tierStatusUpdate(tierStatusUpdate) == .tierStatusUpdate(tierStatusUpdate))
        #expect(OpalFusion.ProtocolModel.ServerMessage.fusionBegin(fusionBegin) == .fusionBegin(fusionBegin))
        #expect(OpalFusion.ProtocolModel.ServerMessage.startRound(startRound) == .startRound(startRound))
        #expect(OpalFusion.ProtocolModel.ServerMessage.blindSignatureResponses(blindSignatureResponses) == .blindSignatureResponses(blindSignatureResponses))
        #expect(OpalFusion.ProtocolModel.ServerMessage.allCommitments(allCommitments) == .allCommitments(allCommitments))
        #expect(OpalFusion.ProtocolModel.ServerMessage.shareCovertComponents(shareCovertComponents) == .shareCovertComponents(shareCovertComponents))
        #expect(OpalFusion.ProtocolModel.ServerMessage.fusionResult(fusionResult) == .fusionResult(fusionResult))
        #expect(OpalFusion.ProtocolModel.ServerMessage.theirProofsList(theirProofsList) == .theirProofsList(theirProofsList))
        #expect(OpalFusion.ProtocolModel.ServerMessage.restartRound(restartRound) == .restartRound(restartRound))
        #expect(OpalFusion.ProtocolModel.ServerMessage.serverFailure(serverFailure) == .serverFailure(serverFailure))

        #expect(OpalFusion.ProtocolModel.CovertMessage.component(covertComponent) == .component(covertComponent))
        #expect(OpalFusion.ProtocolModel.CovertMessage.transactionSignature(covertTransactionSignature) == .transactionSignature(covertTransactionSignature))
        #expect(OpalFusion.ProtocolModel.CovertMessage.ping(ping) == .ping(ping))

        #expect(OpalFusion.ProtocolModel.CovertResponse.acknowledgement(acknowledgement) == .acknowledgement(acknowledgement))
        #expect(OpalFusion.ProtocolModel.CovertResponse.serverFailure(serverFailure) == .serverFailure(serverFailure))
    }
}

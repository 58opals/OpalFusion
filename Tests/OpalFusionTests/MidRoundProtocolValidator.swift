// MidRoundProtocolValidator.swift

import OpalFusion
import Testing

struct MidRoundProtocolValidator {
    @Test("Mid-round protocol models preserve typed commitments and fusion result outcomes")
    func validateMidRoundProtocolModels() {
        let initialCommitment = OpalFusion.Commitment.InitialCommitment(
            saltedComponentHash: [0x10],
            amountCommitment: [0x20],
            communicationPublicKey: [0x30]
        )
        let request = OpalFusion.BlindSignature.Request(
            scalar: [0x40]
        )
        let response = OpalFusion.BlindSignature.Response(
            scalar: [0x50]
        )
        let playerCommit = OpalFusion.ProtocolModel.PlayerCommit(
            initialCommitments: [initialCommitment],
            excessFeeSatoshis: 250,
            pedersenTotalNonce: [0x60],
            randomNumberCommitment: [0x70],
            blindSignatureRequests: [request]
        )
        let blindSignatureResponses = OpalFusion.ProtocolModel.BlindSignatureResponses(
            responses: [response]
        )
        let allCommitments = OpalFusion.ProtocolModel.AllCommitments(
            initialCommitments: [initialCommitment]
        )
        let successResult = OpalFusion.ProtocolModel.FusionResult(
            isSuccess: true,
            transactionSignatures: [[0xAA, 0xBB]],
            badComponentIndices: []
        )
        let failureResult = OpalFusion.ProtocolModel.FusionResult(
            isSuccess: false,
            transactionSignatures: [],
            badComponentIndices: [2, 5]
        )

        #expect(playerCommit.initialCommitments == [initialCommitment])
        #expect(playerCommit.excessFeeSatoshis == 250)
        #expect(playerCommit.pedersenTotalNonce == [0x60])
        #expect(playerCommit.randomNumberCommitment == [0x70])
        #expect(playerCommit.blindSignatureRequests == [request])
        #expect(blindSignatureResponses.responses == [response])
        #expect(allCommitments.initialCommitments == [initialCommitment])
        #expect(successResult.isSuccess == true)
        #expect(successResult.transactionSignatures == [[0xAA, 0xBB]])
        #expect(successResult.badComponentIndices.isEmpty)
        #expect(failureResult.isSuccess == false)
        #expect(failureResult.badComponentIndices == [2, 5])
    }
}

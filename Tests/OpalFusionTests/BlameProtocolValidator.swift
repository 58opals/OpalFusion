// BlameProtocolValidator.swift

import OpalFusion
import Testing

struct BlameProtocolValidator {
    @Test("Blame protocol models preserve encrypted proof lists and typed blame payloads")
    func validateBlameProtocolModels() {
        let relayedProof = OpalFusion.Blame.RelayedProof(
            encryptedProof: [0x10, 0x11],
            sourceCommitmentIndex: 1,
            destinationKeyIndex: 4
        )
        let blameProof = OpalFusion.Blame.BlameProof(
            proofIndex: 0,
            decrypter: .privateKey([0x20, 0x21]),
            reason: "bad component"
        )
        let myProofsList = OpalFusion.ProtocolModel.MyProofsList(
            encryptedProofs: [
                [0x30, 0x31],
                [0x32, 0x33]
            ],
            randomNumber: [0x40, 0x41]
        )
        let theirProofsList = OpalFusion.ProtocolModel.TheirProofsList(
            proofs: [relayedProof]
        )
        let emptyBlames = OpalFusion.ProtocolModel.Blames(
            blames: []
        )
        let populatedBlames = OpalFusion.ProtocolModel.Blames(
            blames: [blameProof]
        )

        #expect(myProofsList.encryptedProofs == [[0x30, 0x31], [0x32, 0x33]])
        #expect(myProofsList.randomNumber == [0x40, 0x41])
        #expect(theirProofsList.proofs == [relayedProof])
        #expect(emptyBlames.blames.isEmpty)
        #expect(populatedBlames.blames == [blameProof])
    }
}

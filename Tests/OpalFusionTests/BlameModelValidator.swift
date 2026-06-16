// BlameModelValidator.swift

import OpalFusion
import Testing

struct BlameModelValidator {
    @Test("Blame models preserve proof bytes, indexes, and decrypter cases")
    func validateBlameModels() {
        let proof = OpalFusion.Blame.Proof(
            componentIndex: 3,
            salt: [0x10, 0x11],
            pedersenNonce: [0x20, 0x21]
        )
        let encryptedProof = OpalFusion.Blame.EncryptedProof(
            ciphertext: [0x30, 0x31]
        )
        let relayedProof = OpalFusion.Blame.RelayedProof(
            encryptedProof: [0x40, 0x41],
            sourceCommitmentIndex: 7,
            destinationKeyIndex: 2
        )
        let sessionKeyDecrypter = OpalFusion.Blame.Decrypter.sessionKey(secretBytes: [0x50, 0x51])
        let privateKeyDecrypter = OpalFusion.Blame.Decrypter.privateKey(secretBytes: [0x60, 0x61])
        let blameProof = OpalFusion.Blame.BlameProof(
            proofIndex: 5,
            decrypter: sessionKeyDecrypter,
            requiresBlockchainLookup: true,
            reason: "missing utxo"
        )

        #expect(Self.requireSendable(proof) == proof)
        #expect(proof.componentIndex == 3)
        #expect(proof.salt == [0x10, 0x11])
        #expect(proof.pedersenNonce == [0x20, 0x21])
        #expect(encryptedProof.ciphertext == [0x30, 0x31])
        #expect(relayedProof.encryptedProof == [0x40, 0x41])
        #expect(relayedProof.sourceCommitmentIndex == 7)
        #expect(relayedProof.destinationKeyIndex == 2)
        #expect(sessionKeyDecrypter == .sessionKey(secretBytes: [0x50, 0x51]))
        #expect(privateKeyDecrypter == .privateKey(secretBytes: [0x60, 0x61]))
        #expect(blameProof.proofIndex == 5)
        #expect(blameProof.decrypter == sessionKeyDecrypter)
        #expect(blameProof.requiresBlockchainLookup == true)
        #expect(blameProof.reason == "missing utxo")
    }

    static func requireSendable<Value: Sendable>(_ value: Value) -> Value {
        value
    }
}

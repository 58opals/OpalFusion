// SigningTransactionAssembler.swift

@testable import OpalFusion
import Foundation
import OpalCrypto

actor SigningTransactionAssembler: OpalFusion.Host.TransactionAssembler {
    private let participantInput: OpalFusion.Host.ParticipantInput
    private let participantInputPrivateKey: [UInt8]
    private let unlockingScriptBuilder: (([UInt8], [UInt8]) -> [UInt8])?
    private let delay: Duration
    private var requestedRoundIdentifiers: [OpalFusion.Round.Identifier] = []
    private var proposals: [OpalFusion.Host.TransactionFinalizationProposal] = []
    private var proposalRecords: [TimedTransactionProposalRecord] = []
    private var signatures: [[UInt8]] = []

    init(
        participantInput: OpalFusion.Host.ParticipantInput,
        participantInputPrivateKey: [UInt8],
        unlockingScriptBuilder: (([UInt8], [UInt8]) -> [UInt8])? = nil,
        delay: Duration = .zero
    ) {
        self.participantInput = participantInput
        self.participantInputPrivateKey = participantInputPrivateKey
        self.unlockingScriptBuilder = unlockingScriptBuilder
        self.delay = delay
        self.requestedRoundIdentifiers = []
        self.proposals = []
        self.signatures = []
    }

    func finalizeTransaction(
        for roundIdentifier: OpalFusion.Round.Identifier,
        proposal: OpalFusion.Host.TransactionFinalizationProposal
    ) async throws -> OpalFusion.Host.FinalizedTransaction {
        requestedRoundIdentifiers.append(roundIdentifier)
        proposals.append(proposal)
        proposalRecords.append(
            .init(
                roundIdentifier: roundIdentifier,
                proposal: proposal,
                recordedAt: Date()
            )
        )

        if delay > .zero {
            try await Task.sleep(for: delay)
        }

        let signingResult = try finalizedTransaction(for: proposal)
        signatures.append(signingResult.signature)
        return signingResult.transaction
    }

    func requestedRounds() -> [OpalFusion.Round.Identifier] {
        requestedRoundIdentifiers
    }

    func recordedProposals() -> [OpalFusion.Host.TransactionFinalizationProposal] {
        proposals
    }

    func timedProposalRecords() -> [TimedTransactionProposalRecord] {
        proposalRecords
    }

    func recordedSignatures() -> [[UInt8]] {
        signatures
    }

    private func finalizedTransaction(
        for proposal: OpalFusion.Host.TransactionFinalizationProposal
    ) throws -> (transaction: OpalFusion.Host.FinalizedTransaction, signature: [UInt8]) {
        guard let participantInputPublicKey = participantInput.publicKey else {
            throw LiveRuntimeTestSupportError.inboundStreamClosed
        }

        var transaction = try OpalFusion.Execution.BCHTransaction.parse(
            proposal.unsignedTransactionBytes
        )
        let previousTransactionHashLittleEndian = Array(
            participantInput.outpointTransactionHashBytes.reversed()
        )
        guard let inputIndex = transaction.inputs.firstIndex(where: { input in
            input.previousTransactionHashLittleEndian == previousTransactionHashLittleEndian &&
                input.previousOutputIndex == participantInput.outpointIndex
        }) else {
            throw LiveRuntimeTestSupportError.signingInputNotFound
        }
        let sighash = try transaction.signatureHash(
            forInputAt: inputIndex,
            lockingScript: participantInput.lockingScriptBytes,
            amountSatoshis: participantInput.amountSatoshis
        )
        let signature = try Array(
            OpalCrypto.Signature.Schnorr.sign(
                digest: OpalCrypto.Signature.Digest(rawRepresentation: Data(sighash)),
                privateKey: OpalCrypto.Secp256k1.PrivateKey(
                    rawRepresentation: Data(participantInputPrivateKey)
                ),
                noncePolicy: .bip340Deterministic
            ).rawRepresentation
        )

        let unlockingScript = unlockingScriptBuilder?(
            signature,
            participantInputPublicKey
        ) ?? ([0x41] + signature + [0x41] + [0x21] + participantInputPublicKey)

        transaction = try transaction.settingUnlockingScript(unlockingScript, at: inputIndex)
        return (
            .init(transactionBytes: try transaction.serialized()),
            signature
        )
    }
}

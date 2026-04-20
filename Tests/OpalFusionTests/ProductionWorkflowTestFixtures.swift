// ProductionWorkflowTestFixtures.swift

@testable import OpalFusion
import Foundation
import OpalCrypto
import SwiftProtobuf

enum ProductionWorkflowTestFixtures {
    static let baseline = OpalFusion.Transport.BaselineConfiguration.electronCash443

    static func makeScenario() throws -> ProductionWorkflowScenario {
        let workflow = OpalFusion.Execution.ProductionWorkflow(baseline: baseline)
        let blindCoordinator = try BlindSigningCoordinator(numberOfComponents: 3)
        let inputPrivateKey = [UInt8](repeating: 0x11, count: 32)
        let inputPublicKey = try Array(
            OpalCrypto.Signature.derivePublicKey(fromPrivateKey: Data(inputPrivateKey))
        )
        let outputPrivateKey = [UInt8](repeating: 0x22, count: 32)
        let outputPublicKey = try Array(
            OpalCrypto.Signature.derivePublicKey(fromPrivateKey: Data(outputPrivateKey))
        )

        let reservation = OpalFusion.Host.ParticipantReservation(
            inputs: [
                .init(
                    outpointTransactionHashBytes: [UInt8](repeating: 0xAA, count: 32),
                    outpointIndex: 1,
                    amountSatoshis: 100_000,
                    lockingScriptBytes: p2pkhLockingScript(publicKey: inputPublicKey),
                    publicKey: inputPublicKey
                )
            ],
            outputs: [
                .init(
                    lockingScriptBytes: p2pkhLockingScript(publicKey: outputPublicKey),
                    amountSatoshis: 99_600
                )
            ]
        )

        let serverHello = OpalFusion.ProtocolModel.ServerHello(
            tiers: [10_000],
            numberOfComponents: 3,
            componentFeeRateSatoshisPerKb: 1_000,
            minimumExcessFeeSatoshis: 200,
            maximumExcessFeeSatoshis: 500,
            donationAddress: "bitcoincash:qexample"
        )
        let fusionBegin = OpalFusion.ProtocolModel.FusionBegin(
            tier: 10_000,
            covertDomain: "covert.example.org",
            covertPort: 7_447,
            covertSsl: true,
            serverTimeUnixSeconds: 1_000
        )

        let deadlines = OpalFusion.Execution.Deadlines
            .fromFusionBegin(fusionBegin, timing: baseline.roundTiming)
            .withStartRound(blindCoordinator.startRound, timing: baseline.roundTiming)
        var round = OpalFusion.Execution.RoundContext(
            fusionBegin: fusionBegin,
            serverHello: serverHello,
            deadlines: deadlines
        )
        round.startRound = blindCoordinator.startRound
        round.identifier = .init(rawValue: blindCoordinator.roundPublicKey.map {
            String(format: "%02x", $0)
        }.joined())
        round.participantReservation = reservation

        return .init(
            baseline: baseline,
            workflow: workflow,
            serverHello: serverHello,
            fusionBegin: fusionBegin,
            reservation: reservation,
            participantInputPrivateKey: inputPrivateKey,
            blindCoordinator: blindCoordinator,
            round: round
        )
    }

    static func extractSerializedComponents(
        from covertMessages: [OpalFusion.ProtocolModel.CovertMessage]
    ) throws -> [[UInt8]] {
        try covertMessages.map { message in
            guard case let .component(componentMessage) = message else {
                throw ProductionWorkflowTestError.expectedComponentMessage
            }
            return componentMessage.serializedComponent
        }
    }

    static func makeExternalInputComponent(
        workflow: OpalFusion.Execution.ProductionWorkflow,
        feeRateSatoshisPerKb: UInt64
    ) throws -> ExternalInputComponentFixture {
        let inputPrivateKey = [UInt8](repeating: 0x44, count: 32)
        let inputPublicKey = try Array(
            OpalCrypto.Signature.derivePublicKey(fromPrivateKey: Data(inputPrivateKey))
        )
        let communicationPrivateKey = [UInt8](repeating: 0x55, count: 32)
        let communicationPublicKey = try Array(
            OpalCrypto.Secp256k1.deriveCompressedPublicKey(
                from: Data(communicationPrivateKey)
            )
        )
        let salt = [UInt8](repeating: 0x66, count: 32)
        let pedersenNonce = [UInt8](repeating: 0x77, count: 32)
        let amountSatoshis: UInt64 = 60_000

        var component = Fusion_Component()
        component.saltCommitment = Data(
            OpalFusion.Execution.ProtocolPrimitives.sha256(salt)
        )
        var input = Fusion_InputComponent()
        input.prevTxid = Data([UInt8](repeating: 0xCC, count: 32).reversed())
        input.prevIndex = 2
        input.pubkey = Data(inputPublicKey)
        input.amount = amountSatoshis
        component.component = .input(input)
        let serializedComponent = try Array(component.serializedData())

        let contribution = Int64(amountSatoshis)
            - Int64(
                OpalFusion.Execution.ProtocolPrimitives.componentFee(
                    sizeBytes: OpalFusion.Execution.ProtocolPrimitives
                        .inputSize(for: inputPublicKey),
                    feeRateSatoshisPerKb: feeRateSatoshisPerKb
                )
            )
        let pedersenCommitment = try workflow.pedersenSetup.commit(
            amount: contribution,
            nonce: Data(pedersenNonce)
        )
        let initialCommitment = OpalFusion.Commitment.InitialCommitment(
            saltedComponentHash: OpalFusion.Execution.ProtocolPrimitives.sha256(
                salt + serializedComponent
            ),
            amountCommitment: Array(pedersenCommitment.uncompressedPoint),
            communicationPublicKey: communicationPublicKey
        )

        return .init(
            serializedComponent: serializedComponent,
            initialCommitment: initialCommitment,
            communicationPrivateKey: communicationPrivateKey,
            salt: salt,
            pedersenNonce: pedersenNonce
        )
    }

    static func encryptProof(
        componentIndex: Int,
        salt: [UInt8],
        pedersenNonce: [UInt8],
        recipientPublicKey: [UInt8]
    ) throws -> [UInt8] {
        var proof = Fusion_Proof()
        proof.componentIdx = UInt32(componentIndex)
        proof.salt = Data(salt)
        proof.pedersenNonce = Data(pedersenNonce)
        return try Array(
            OpalCrypto.Communication.encrypt(
                message: proof.serializedData(),
                recipientPublicKey: Data(recipientPublicKey),
                paddedPlaintextLength: 80
            )
        )
    }

    static func makeSignedFinalizedTransaction(
        proposal: OpalFusion.Host.TransactionFinalizationProposal,
        participantInput: OpalFusion.Host.ParticipantInput,
        participantInputPrivateKey: [UInt8],
        unlockingScriptBuilder: (([UInt8], [UInt8]) -> [UInt8])? = nil
    ) throws -> SigningTransactionFixture {
        guard let participantInputPublicKey = participantInput.publicKey else {
            throw ProductionWorkflowTestError.missingParticipantInputPublicKey
        }

        var transaction = try OpalFusion.Execution.BCHTransaction.parse(
            proposal.unsignedTransactionBytes
        )
        let sighash = try transaction.signatureHash(
            forInputAt: 0,
            lockingScript: participantInput.lockingScriptBytes,
            amountSatoshis: participantInput.amountSatoshis
        )
        let signature = try Array(
            OpalCrypto.Signature.signSchnorr(
                digest: Data(sighash),
                privateKey: Data(participantInputPrivateKey),
                noncePolicy: .bip340Deterministic
            )
        )

        let unlockingScript = unlockingScriptBuilder?(
            signature,
            participantInputPublicKey
        ) ?? standardP2PKHUnlockingScript(
            signature: signature,
            publicKey: participantInputPublicKey
        )

        transaction = transaction.settingUnlockingScript(unlockingScript, at: 0)
        return .init(
            transaction: .init(transactionBytes: try transaction.serialized()),
            signature: signature
        )
    }

    static func standardP2PKHUnlockingScript(
        signature: [UInt8],
        publicKey: [UInt8]
    ) -> [UInt8] {
        [0x41] + signature + [0x41] + [0x21] + publicKey
    }

    static func p2pkhLockingScript(publicKey: [UInt8]) -> [UInt8] {
        [0x76, 0xA9, 0x14]
            + OpalFusion.Execution.ProtocolPrimitives.hash160(publicKey)
            + [0x88, 0xAC]
    }
}

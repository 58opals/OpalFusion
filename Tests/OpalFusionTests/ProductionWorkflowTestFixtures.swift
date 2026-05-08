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
            OpalCrypto.Secp256k1.derivePublicKey(
                from: OpalCrypto.Secp256k1.PrivateKey(
                    rawRepresentation: Data(inputPrivateKey)
                )
            ).rawRepresentation
        )
        let outputPrivateKey = [UInt8](repeating: 0x22, count: 32)
        let outputPublicKey = try Array(
            OpalCrypto.Secp256k1.derivePublicKey(
                from: OpalCrypto.Secp256k1.PrivateKey(
                    rawRepresentation: Data(outputPrivateKey)
                )
            ).rawRepresentation
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
            participantInputPrivateKeys: [inputPrivateKey],
            blindCoordinator: blindCoordinator,
            round: round
        )
    }

    static func makeTwoInputScenario() throws -> ProductionWorkflowScenario {
        let workflow = OpalFusion.Execution.ProductionWorkflow(baseline: baseline)
        let blindCoordinator = try BlindSigningCoordinator(numberOfComponents: 4)
        let inputPrivateKeys = [
            [UInt8](repeating: 0x11, count: 32),
            [UInt8](repeating: 0x33, count: 32),
        ]
        let inputPublicKeys = try inputPrivateKeys.map { privateKey in
            try Array(
                OpalCrypto.Secp256k1.derivePublicKey(
                    from: OpalCrypto.Secp256k1.PrivateKey(
                        rawRepresentation: Data(privateKey)
                    )
                ).rawRepresentation
            )
        }
        let outputPrivateKey = [UInt8](repeating: 0x22, count: 32)
        let outputPublicKey = try Array(
            OpalCrypto.Secp256k1.derivePublicKey(
                from: OpalCrypto.Secp256k1.PrivateKey(
                    rawRepresentation: Data(outputPrivateKey)
                )
            ).rawRepresentation
        )
        let outputScript = p2pkhLockingScript(publicKey: outputPublicKey)
        let feeRateSatoshisPerKb: UInt64 = 1_000
        let inputAmounts: [UInt64] = [100_000, 60_000]
        let inputFees = inputPublicKeys.map { publicKey in
            OpalFusion.Execution.ProtocolPrimitives.componentFee(
                sizeBytes: OpalFusion.Execution.ProtocolPrimitives.inputSize(for: publicKey),
                feeRateSatoshisPerKb: feeRateSatoshisPerKb
            )
        }
        let outputFee = OpalFusion.Execution.ProtocolPrimitives.componentFee(
            sizeBytes: OpalFusion.Execution.ProtocolPrimitives.outputSize(for: outputScript),
            feeRateSatoshisPerKb: feeRateSatoshisPerKb
        )
        let outputAmount = inputAmounts.reduce(0, +)
            - inputFees.reduce(0, +)
            - outputFee
            - 250

        let reservation = OpalFusion.Host.ParticipantReservation(
            inputs: [
                .init(
                    outpointTransactionHashBytes: [UInt8](repeating: 0xAA, count: 32),
                    outpointIndex: 1,
                    amountSatoshis: inputAmounts[0],
                    lockingScriptBytes: p2pkhLockingScript(publicKey: inputPublicKeys[0]),
                    publicKey: inputPublicKeys[0]
                ),
                .init(
                    outpointTransactionHashBytes: [UInt8](repeating: 0xBB, count: 32),
                    outpointIndex: 2,
                    amountSatoshis: inputAmounts[1],
                    lockingScriptBytes: p2pkhLockingScript(publicKey: inputPublicKeys[1]),
                    publicKey: inputPublicKeys[1]
                ),
            ],
            outputs: [
                .init(
                    lockingScriptBytes: outputScript,
                    amountSatoshis: outputAmount
                )
            ]
        )

        let serverHello = OpalFusion.ProtocolModel.ServerHello(
            tiers: [10_000],
            numberOfComponents: 4,
            componentFeeRateSatoshisPerKb: feeRateSatoshisPerKb,
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
            participantInputPrivateKeys: inputPrivateKeys,
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
            OpalCrypto.Secp256k1.derivePublicKey(
                from: OpalCrypto.Secp256k1.PrivateKey(
                    rawRepresentation: Data(inputPrivateKey)
                )
            ).rawRepresentation
        )
        let communicationPrivateKey = [UInt8](repeating: 0x55, count: 32)
        let communicationPublicKey = try Array(
            OpalCrypto.Secp256k1.derivePublicKey(
                from: OpalCrypto.Secp256k1.PrivateKey(
                    rawRepresentation: Data(communicationPrivateKey)
                )
            ).rawRepresentation
        )
        let salt = [UInt8](repeating: 0x66, count: 32)
        let pedersenNonce = [UInt8](repeating: 0x77, count: 32)
        let amountSatoshis: UInt64 = 60_000

        var component = FusionComponent()
        component.saltCommitment = Data(
            OpalFusion.Execution.ProtocolPrimitives.sha256(salt)
        )
        var input = FusionInputComponent()
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
            nonce: OpalCrypto.Pedersen.Nonce(rawRepresentation: Data(pedersenNonce))
        )
        let initialCommitment = OpalFusion.Commitment.InitialCommitment(
            saltedComponentHash: OpalFusion.Execution.ProtocolPrimitives.sha256(
                salt + serializedComponent
            ),
            amountCommitment: Array(pedersenCommitment.point.uncompressedRepresentation),
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
        var proof = FusionProof()
        proof.componentIdx = UInt32(componentIndex)
        proof.salt = Data(salt)
        proof.pedersenNonce = Data(pedersenNonce)
        return try Array(
            OpalCrypto.Communication.encrypt(
                message: proof.serializedData(),
                recipientPublicKey: OpalCrypto.Secp256k1.PublicKey(
                    rawRepresentation: Data(recipientPublicKey)
                ),
                paddedPlaintextLength: 80
            ).rawRepresentation
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

    static func makeSignedFinalizedTransaction(
        proposal: OpalFusion.Host.TransactionFinalizationProposal,
        participantInputs: [OpalFusion.Host.ParticipantInput],
        participantInputPrivateKeys: [[UInt8]]
    ) throws -> (
        transaction: OpalFusion.Host.FinalizedTransaction,
        signaturesByReservationInputIndex: [[UInt8]],
        transactionInputIndicesByReservationInputIndex: [Int]
    ) {
        guard participantInputs.count == participantInputPrivateKeys.count else {
            throw ProductionWorkflowTestError.participantPrivateKeyCountMismatch
        }

        var transaction = try OpalFusion.Execution.BCHTransaction.parse(
            proposal.unsignedTransactionBytes
        )
        var signatures: [[UInt8]] = []
        var transactionInputIndices: [Int] = []
        signatures.reserveCapacity(participantInputs.count)
        transactionInputIndices.reserveCapacity(participantInputs.count)

        for (participantInput, participantInputPrivateKey) in zip(
            participantInputs,
            participantInputPrivateKeys
        ) {
            guard let participantInputPublicKey = participantInput.publicKey else {
                throw ProductionWorkflowTestError.missingParticipantInputPublicKey
            }

            let previousTransactionHashLittleEndian = Array(
                participantInput.outpointTransactionHashBytes.reversed()
            )
            guard let inputIndex = transaction.inputs.firstIndex(where: { input in
                input.previousTransactionHashLittleEndian == previousTransactionHashLittleEndian &&
                    input.previousOutputIndex == participantInput.outpointIndex
            }) else {
                throw ProductionWorkflowTestError.signingInputNotFound
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

            transaction = transaction.settingUnlockingScript(
                standardP2PKHUnlockingScript(
                    signature: signature,
                    publicKey: participantInputPublicKey
                ),
                at: inputIndex
            )
            signatures.append(signature)
            transactionInputIndices.append(inputIndex)
        }

        return (
            .init(transactionBytes: try transaction.serialized()),
            signatures,
            transactionInputIndices
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

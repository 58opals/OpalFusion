// ProductionWorkflowValidator.swift

@testable import OpalFusion
import Foundation
import OpalCrypto
import SwiftProtobuf
import Testing

struct ProductionWorkflowValidator {
    @Test("Production workflow builds a real PlayerCommit from participant reservation")
    func validatePlayerCommitMaterialization() throws {
        var scenario = try ProductionWorkflowTestFixtures.makeScenario()

        let playerCommit = try scenario.buildPlayerCommit()

        guard let material = scenario.round.executionMaterial.playerCommitMaterial else {
            Issue.record("Expected player-commit material to be cached in round context")
            return
        }

        #expect(playerCommit.initialCommitments.count == 3)
        #expect(playerCommit.blindSignatureRequests.count == 3)
        #expect(material.componentsByCommitmentOrder.count == 3)
        #expect(
            material.componentsByCommitmentOrder.contains { component in
                if case .blank = component.payload {
                    return true
                }
                return false
            }
        )
        #expect(
            playerCommit.randomNumberCommitment
                == OpalFusion.Execution.ProtocolPrimitives.sha256(material.randomNumber)
        )
        let expectedPedersenTotalNonce = try OpalFusion.Execution.ProtocolPrimitives
            .sumNoncesModOrder(
                material.componentsByCommitmentOrder.map(\.proofMaterial.pedersenNonce)
            )
        #expect(
            playerCommit.pedersenTotalNonce == expectedPedersenTotalNonce
        )
        #expect(
            playerCommit.excessFeeSatoshis >= scenario.serverHello.minimumExcessFeeSatoshis
        )
        #expect(
            playerCommit.excessFeeSatoshis <= scenario.serverHello.maximumExcessFeeSatoshis
        )
    }

    @Test("Production workflow rejects invalid participant reservations early")
    func validateParticipantReservationFailures() throws {
        do {
            var scenario = try ProductionWorkflowTestFixtures.makeScenario()
            let invalidInput = OpalFusion.Host.ParticipantInput(
                outpointTransactionHash: scenario.reservation.inputs[0].outpointTransactionHash,
                outpointIndex: scenario.reservation.inputs[0].outpointIndex,
                amountSatoshis: scenario.reservation.inputs[0].amountSatoshis,
                lockingScript: scenario.reservation.inputs[0].lockingScript
            )
            let invalidReservation = OpalFusion.Host.ParticipantReservation(
                inputs: [invalidInput],
                outputs: scenario.reservation.outputs
            )
            scenario.round.participantReservation = invalidReservation
            _ = try scenario.workflow.buildPlayerCommit(round: &scenario.round)
            Issue.record("Expected missing public-key reservation to fail")
        } catch let error as OpalFusion.Execution.WorkflowFailure {
            #expect(error == .missingParticipantInputPublicKey(index: 0))
        }

        do {
            var scenario = try ProductionWorkflowTestFixtures.makeScenario()
            scenario.round.participantReservation = .init(
                inputs: scenario.reservation.inputs,
                outputs: []
            )
            _ = try scenario.workflow.buildPlayerCommit(round: &scenario.round)
            Issue.record("Expected empty-output reservation to fail")
        } catch let error as OpalFusion.Execution.WorkflowFailure {
            #expect(
                error == .invalidParticipantReservation(
                    "At least one participant output is required"
                )
            )
        }

        do {
            var scenario = try ProductionWorkflowTestFixtures.makeScenario()
            scenario.round.participantReservation = .init(
                inputs: scenario.reservation.inputs,
                outputs: [scenario.reservation.outputs[0], scenario.reservation.outputs[0], scenario.reservation.outputs[0]]
            )
            _ = try scenario.workflow.buildPlayerCommit(round: &scenario.round)
            Issue.record("Expected oversized reservation to fail")
        } catch let error as OpalFusion.Execution.WorkflowFailure {
            #expect(
                error == .invalidParticipantReservation(
                    "Participant reservation exceeds the server component limit"
                )
            )
        }

        do {
            var scenario = try ProductionWorkflowTestFixtures.makeScenario()
            scenario.round.participantReservation = .init(
                inputs: [
                    .init(
                        outpointTransactionHash: scenario.reservation.inputs[0].outpointTransactionHash,
                        outpointIndex: scenario.reservation.inputs[0].outpointIndex,
                        amountSatoshis: scenario.reservation.inputs[0].amountSatoshis,
                        lockingScript: scenario.reservation.inputs[0].lockingScript,
                        publicKey: [UInt8](repeating: 0x04, count: 65)
                    )
                ],
                outputs: scenario.reservation.outputs
            )
            _ = try scenario.workflow.buildPlayerCommit(round: &scenario.round)
            Issue.record("Expected malformed public-key reservation to fail")
        } catch let error as OpalFusion.Execution.WorkflowFailure {
            #expect(
                error == .invalidParticipantReservation(
                    "Participant input at index 0 must provide the compressed public key required for standard P2PKH support"
                )
            )
        }

        do {
            var scenario = try ProductionWorkflowTestFixtures.makeScenario()
            scenario.round.participantReservation = .init(
                inputs: [
                    .init(
                        outpointTransactionHash: scenario.reservation.inputs[0].outpointTransactionHash,
                        outpointIndex: scenario.reservation.inputs[0].outpointIndex,
                        amountSatoshis: scenario.reservation.inputs[0].amountSatoshis,
                        lockingScript: [0x51],
                        publicKey: scenario.reservation.inputs[0].publicKey
                    )
                ],
                outputs: scenario.reservation.outputs
            )
            _ = try scenario.workflow.buildPlayerCommit(round: &scenario.round)
            Issue.record("Expected non-P2PKH reservation to fail")
        } catch let error as OpalFusion.Execution.WorkflowFailure {
            #expect(
                error == .unsupportedExecution(
                    OpalFusion.Execution.ProtocolPrimitives.supportedParticipantInputSummary
                )
            )
        }
    }

    @Test("Production workflow derives the unsigned template and extracts local signatures")
    func validateTransactionTemplateAndSignatureExtraction() throws {
        var scenario = try ProductionWorkflowTestFixtures.makeScenario()
        let playerCommit = try scenario.buildPlayerCommit()
        _ = try scenario.buildBlindSignatureResponses(for: playerCommit)

        let covertMessages = try scenario.workflow.buildCovertComponentMessages(round: &scenario.round)
        #expect(covertMessages.count == 3)

        try scenario.useSharedRound(
            allCommitments: playerCommit.initialCommitments,
            serializedComponents: try ProductionWorkflowTestFixtures
                .extractSerializedComponents(from: covertMessages)
        )

        let proposal = try scenario.workflow.buildTransactionFinalizationProposal(round: &scenario.round)
        #expect(proposal.participantCount == nil)
        let unsignedTransaction = try OpalFusion.Execution.BCHTransaction.parse(
            proposal.serializedUnsignedTransaction
        )

        #expect(unsignedTransaction.version == 1)
        #expect(unsignedTransaction.inputs.count == 1)
        #expect(unsignedTransaction.outputs.count == 2)
        #expect(unsignedTransaction.lockTime == 0)
        #expect(
            unsignedTransaction.outputs[0].lockingScript
                == OpalFusion.Execution.ProtocolPrimitives.makeSessionHashLockingScript(
                    sessionHash: proposal.sessionHash ?? [],
                    baseline: scenario.baseline
                )
        )
        #expect(
            unsignedTransaction.outputs[1].amountSatoshis
                == scenario.reservation.outputs[0].amountSatoshis
        )
        #expect(
            unsignedTransaction.outputs[1].lockingScript
                == scenario.reservation.outputs[0].lockingScript
        )

        let signingResult = try scenario.makeSignedFinalizedTransaction(proposal: proposal)
        scenario.round.finalizedTransaction = signingResult.transaction

        let signatureMessages = try scenario.workflow.buildCovertSignatureMessages(
            round: &scenario.round
        )
        #expect(signatureMessages.count == 1)

        guard case let .transactionSignature(signatureMessage) = signatureMessages[0] else {
            Issue.record("Expected a covert transaction signature message")
            return
        }
        #expect(signatureMessage.roundPublicKey == scenario.startRound.roundPublicKey)
        #expect(signatureMessage.inputIndex == 0)
        #expect(signatureMessage.transactionSignature == signingResult.signature)

        do {
            var mismatchedRound = scenario.round
            var mismatchedTransaction = unsignedTransaction
            mismatchedTransaction.outputs[1].amountSatoshis += 1
            mismatchedRound.finalizedTransaction = .init(
                serializedTransaction: try mismatchedTransaction.serialized()
            )
            _ = try scenario.workflow.buildCovertSignatureMessages(round: &mismatchedRound)
            Issue.record("Expected mismatched finalized transaction to fail")
        } catch let error as OpalFusion.Execution.WorkflowFailure {
            #expect(
                error == .invalidTransactionTemplate(
                    "Finalized transaction outputs did not match the unsigned template"
                )
            )
        }

        do {
            var unsupportedRound = scenario.round
            let unsupportedSigningResult = try scenario.makeSignedFinalizedTransaction(
                proposal: proposal,
                unlockingScriptBuilder: { signature, publicKey in
                    [0x4C, 0x40] + signature + [0x21] + publicKey
                }
            )
            unsupportedRound.finalizedTransaction = unsupportedSigningResult.transaction
            _ = try scenario.workflow.buildCovertSignatureMessages(round: &unsupportedRound)
            Issue.record("Expected unsupported unlocking script to fail")
        } catch let error as OpalFusion.Execution.WorkflowFailure {
            #expect(
                error == .unsupportedExecution(
                    OpalFusion.Execution.ProtocolPrimitives.supportedUnlockingScriptSummary
                )
            )
        }
    }

    @Test("Production workflow generates decryptable proofs and blame outputs")
    func validateProofGenerationAndBlameMaterialization() throws {
        var scenario = try ProductionWorkflowTestFixtures.makeScenario()
        let playerCommit = try scenario.buildPlayerCommit()
        let extraInputComponent = try scenario.makeExternalInputComponent()

        try scenario.useSharedRound(
            allCommitments: playerCommit.initialCommitments + [extraInputComponent.initialCommitment],
            serializedComponents: scenario.localSerializedComponents() + [extraInputComponent.serializedComponent]
        )

        let myProofsList = try scenario.workflow.buildMyProofsList(round: &scenario.round)
        guard let playerCommitMaterial = scenario.round.executionMaterial.playerCommitMaterial else {
            Issue.record("Expected cached player-commit material before proof generation")
            return
        }
        guard let sharedRoundMaterial = scenario.round.executionMaterial.sharedRoundMaterial else {
            Issue.record("Expected cached shared-round material before proof generation")
            return
        }

        #expect(myProofsList.randomNumber == playerCommitMaterial.randomNumber)
        #expect(myProofsList.encryptedProofs.count == playerCommitMaterial.componentsByCommitmentOrder.count)

        let decryptedProof = try OpalCrypto.Communication.decrypt(
            Data(myProofsList.encryptedProofs[0]),
            privateKey: Data(extraInputComponent.communicationPrivateKey)
        )
        let parsedProof = try Fusion_Proof(serializedBytes: decryptedProof.message)
        #expect(sharedRoundMaterial.myComponentIndices.contains(Int(parsedProof.componentIdx)))

        let destinationComponent = playerCommitMaterial.componentsByCommitmentOrder[0]
        let invalidEncryptedProof = try Array(
            OpalCrypto.Communication.encrypt(
                message: Data([0x00]),
                recipientPublicKey: Data(destinationComponent.initialCommitment.communicationPublicKey)
            )
        )
        let validEncryptedProof = try ProductionWorkflowTestFixtures.encryptProof(
            componentIndex: sharedRoundMaterial.allComponentBytes.count - 1,
            salt: extraInputComponent.salt,
            pedersenNonce: extraInputComponent.pedersenNonce,
            recipientPublicKey: destinationComponent.initialCommitment.communicationPublicKey
        )

        scenario.round.fusionResult = .init(
            isSuccess: false,
            transactionSignatures: [],
            badComponentIndices: []
        )
        scenario.round.theirProofsList = .init(
            proofs: [
                .init(
                    encryptedProof: invalidEncryptedProof,
                    sourceCommitmentIndex: UInt32(sharedRoundMaterial.allCommitmentBytes.count - 1),
                    destinationKeyIndex: 0
                ),
                .init(
                    encryptedProof: validEncryptedProof,
                    sourceCommitmentIndex: UInt32(sharedRoundMaterial.allCommitmentBytes.count - 1),
                    destinationKeyIndex: 0
                )
            ]
        )

        let blames = try scenario.workflow.buildBlames(round: &scenario.round)
        #expect(blames.blames.count == 2)
        #expect(blames.blames[0].requiresBlockchainLookup == false)
        #expect(blames.blames[0].reason == "proof decode failed")
        if case let .sessionKey(sessionKey) = blames.blames[0].decrypter {
            #expect(sessionKey.count == 32)
        } else {
            Issue.record("Expected invalid proof blame to carry a session key")
        }
        #expect(blames.blames[1].requiresBlockchainLookup == true)
        #expect(blames.blames[1].reason == "input requires blockchain lookup")
        if case let .sessionKey(sessionKey) = blames.blames[1].decrypter {
            #expect(sessionKey.count == 32)
        } else {
            Issue.record("Expected input proof blame to carry a session key")
        }
    }
}

struct ProductionWorkflowScenario {
    let baseline: OpalFusion.Transport.BaselineConfiguration
    let workflow: OpalFusion.Execution.ProductionWorkflow
    let serverHello: OpalFusion.ProtocolModel.ServerHello
    let fusionBegin: OpalFusion.ProtocolModel.FusionBegin
    let reservation: OpalFusion.Host.ParticipantReservation
    let participantInputPrivateKey: [UInt8]
    var blindCoordinator: BlindSigningCoordinator
    var round: OpalFusion.Execution.RoundContext

    var startRound: OpalFusion.ProtocolModel.StartRound {
        round.startRound!
    }

    mutating func buildPlayerCommit() throws -> OpalFusion.ProtocolModel.PlayerCommit {
        let playerCommit = try workflow.buildPlayerCommit(round: &round)
        round.playerCommit = playerCommit
        return playerCommit
    }

    mutating func buildBlindSignatureResponses(
        for playerCommit: OpalFusion.ProtocolModel.PlayerCommit
    ) throws -> OpalFusion.ProtocolModel.BlindSignatureResponses {
        let responses = try blindCoordinator.responses(for: playerCommit)
        round.blindSignatureResponses = responses
        return responses
    }

    mutating func useSharedRound(
        allCommitments: [OpalFusion.Commitment.InitialCommitment],
        serializedComponents: [[UInt8]]
    ) throws {
        round.allCommitments = .init(initialCommitments: allCommitments)
        round.sharedComponents = .init(
            serializedComponents: serializedComponents,
            skipSignatures: false,
            sessionHash: nil
        )
    }

    func localSerializedComponents() -> [[UInt8]] {
        round.executionMaterial.playerCommitMaterial?.componentsByCommitmentOrder
            .map(\.serializedComponent) ?? []
    }

    func makeExternalInputComponent() throws -> ExternalInputComponentFixture {
        try ProductionWorkflowTestFixtures.makeExternalInputComponent(
            workflow: workflow,
            feeRateSatoshisPerKb: serverHello.componentFeeRateSatoshisPerKb
        )
    }

    func makeSignedFinalizedTransaction(
        proposal: OpalFusion.Host.TransactionFinalizationProposal,
        unlockingScriptBuilder: (([UInt8], [UInt8]) -> [UInt8])? = nil
    ) throws -> SigningTransactionFixture {
        try ProductionWorkflowTestFixtures.makeSignedFinalizedTransaction(
            proposal: proposal,
            participantInput: reservation.inputs[0],
            participantInputPrivateKey: participantInputPrivateKey,
            unlockingScriptBuilder: unlockingScriptBuilder
        )
    }
}

struct SigningTransactionFixture {
    let transaction: OpalFusion.Host.FinalizedTransaction
    let signature: [UInt8]
}

struct ExternalInputComponentFixture {
    let serializedComponent: [UInt8]
    let initialCommitment: OpalFusion.Commitment.InitialCommitment
    let communicationPrivateKey: [UInt8]
    let salt: [UInt8]
    let pedersenNonce: [UInt8]
}

struct BlindSigningCoordinator {
    let roundPrivateKey: [UInt8]
    let roundPublicKey: [UInt8]
    private var signers: [OpalCrypto.BlindSignature.Signer]

    init(numberOfComponents: Int) throws {
        let roundPrivateKey = [UInt8](repeating: 0x31, count: 32)
        self.roundPrivateKey = roundPrivateKey
        self.roundPublicKey = try Array(
            OpalCrypto.Signature.derivePublicKey(
                fromPrivateKey: Data(roundPrivateKey)
            )
        )
        self.signers = try (0..<numberOfComponents).map { _ in
            try OpalCrypto.BlindSignature.Signer()
        }
    }

    var startRound: OpalFusion.ProtocolModel.StartRound {
        .init(
            roundPublicKey: roundPublicKey,
            blindNoncePoints: signers.map { Array($0.noncePoint) },
            serverTimeUnixSeconds: 1_030
        )
    }

    mutating func responses(
        for playerCommit: OpalFusion.ProtocolModel.PlayerCommit
    ) throws -> OpalFusion.ProtocolModel.BlindSignatureResponses {
        guard playerCommit.blindSignatureRequests.count == signers.count else {
            throw BlindSigningCoordinatorError.invalidBlindRequestCount
        }

        var responses: [OpalFusion.BlindSignature.Response] = []
        responses.reserveCapacity(signers.count)

        for index in signers.indices {
            let scalar = try signers[index].sign(
                privateKey: Data(roundPrivateKey),
                requestScalar: Data(playerCommit.blindSignatureRequests[index].scalar)
            )
            responses.append(.init(scalar: Array(scalar)))
        }

        return .init(responses: responses)
    }
}

enum BlindSigningCoordinatorError: Swift.Error, Equatable {
    case invalidBlindRequestCount
}

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
                    outpointTransactionHash: [UInt8](repeating: 0xAA, count: 32),
                    outpointIndex: 1,
                    amountSatoshis: 100_000,
                    lockingScript: p2pkhLockingScript(publicKey: inputPublicKey),
                    publicKey: inputPublicKey
                )
            ],
            outputs: [
                .init(
                    lockingScript: p2pkhLockingScript(publicKey: outputPublicKey),
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
            proposal.serializedUnsignedTransaction
        )
        let sighash = try transaction.signatureHash(
            forInputAt: 0,
            lockingScript: participantInput.lockingScript,
            amountSatoshis: participantInput.amountSatoshis
        )
        let signature = try Array(
            OpalCrypto.Signature.sign(
                message: Data(sighash),
                privateKey: Data(participantInputPrivateKey),
                format: .schnorr,
                nonce: .bip340Deterministic
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
            transaction: .init(serializedTransaction: try transaction.serialized()),
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

enum ProductionWorkflowTestError: Swift.Error, Equatable {
    case expectedComponentMessage
    case missingParticipantInputPublicKey
}

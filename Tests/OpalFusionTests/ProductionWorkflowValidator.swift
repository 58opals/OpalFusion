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

    @Test("Production workflow reduces Pedersen nonce sums after carry folding")
    func validatePedersenNonceSumReducesFoldedCarry() throws {
        var orderMinusOne = Scalar256Value.order.bytes32
        orderMinusOne[31] -= 1
        let maximumNonce = [UInt8](repeating: 0xFF, count: 32)
        var expected = Scalar256Value.twoTo256MinusOrder.bytes32
        expected[31] -= 2

        let sum = try OpalFusion.Execution.ProtocolPrimitives.sumNoncesModOrder(
            [orderMinusOne, maximumNonce]
        )

        #expect(sum == expected)
    }

    @Test("Production workflow rejects invalid StartRound signing keys")
    func validateStartRoundRejectsInvalidBlindSigningKeys() throws {
        let invalidCompressedPublicKey = [UInt8](arrayLiteral: 0x02)
            + [UInt8](repeating: 0x00, count: 32)

        do {
            var scenario = try ProductionWorkflowTestFixtures.makeScenario()
            scenario.round.startRound = .init(
                roundPublicKey: invalidCompressedPublicKey,
                blindNoncePoints: scenario.startRound.blindNoncePoints,
                serverTimeUnixSeconds: scenario.startRound.serverTimeUnixSeconds
            )
            _ = try scenario.workflow.buildPlayerCommit(round: &scenario.round)
            Issue.record("Expected invalid round public key to fail")
        } catch let error as OpalFusion.Execution.WorkflowFailure {
            #expect(
                error == .protocolValidationFailed(
                    "StartRound round public key must be a valid compressed public key"
                )
            )
        }

        do {
            var scenario = try ProductionWorkflowTestFixtures.makeScenario()
            var blindNoncePoints = scenario.startRound.blindNoncePoints
            blindNoncePoints[0] = invalidCompressedPublicKey
            scenario.round.startRound = .init(
                roundPublicKey: scenario.startRound.roundPublicKey,
                blindNoncePoints: blindNoncePoints,
                serverTimeUnixSeconds: scenario.startRound.serverTimeUnixSeconds
            )
            _ = try scenario.workflow.buildPlayerCommit(round: &scenario.round)
            Issue.record("Expected invalid blind nonce point to fail")
        } catch let error as OpalFusion.Execution.WorkflowFailure {
            #expect(
                error == .protocolValidationFailed(
                    "StartRound blind nonce point at index 0 must be a valid compressed public key"
                )
            )
        }
    }

    @Test("Production workflow rejects invalid participant reservations early")
    func validateParticipantReservationFailures() throws {
        do {
            var scenario = try ProductionWorkflowTestFixtures.makeScenario()
            let invalidInput = OpalFusion.Host.ParticipantInput(
                outpointTransactionHashBytes: scenario.reservation.inputs[0].outpointTransactionHashBytes,
                outpointIndex: scenario.reservation.inputs[0].outpointIndex,
                amountSatoshis: scenario.reservation.inputs[0].amountSatoshis,
                lockingScriptBytes: scenario.reservation.inputs[0].lockingScriptBytes
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
                        outpointTransactionHashBytes: scenario.reservation.inputs[0].outpointTransactionHashBytes,
                        outpointIndex: scenario.reservation.inputs[0].outpointIndex,
                        amountSatoshis: scenario.reservation.inputs[0].amountSatoshis,
                        lockingScriptBytes: scenario.reservation.inputs[0].lockingScriptBytes,
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
                        outpointTransactionHashBytes: [UInt8](repeating: 0xAB, count: 31),
                        outpointIndex: scenario.reservation.inputs[0].outpointIndex,
                        amountSatoshis: scenario.reservation.inputs[0].amountSatoshis,
                        lockingScriptBytes: scenario.reservation.inputs[0].lockingScriptBytes,
                        publicKey: scenario.reservation.inputs[0].publicKey
                    )
                ],
                outputs: scenario.reservation.outputs
            )
            _ = try scenario.workflow.buildPlayerCommit(round: &scenario.round)
            Issue.record("Expected short previous transaction hash reservation to fail")
        } catch let error as OpalFusion.Execution.WorkflowFailure {
            #expect(
                error == .invalidParticipantReservation(
                    "Participant input at index 0 previous transaction hash must be 32 bytes"
                )
            )
        }

        do {
            var scenario = try ProductionWorkflowTestFixtures.makeScenario()
            scenario.round.participantReservation = .init(
                inputs: [
                    .init(
                        outpointTransactionHashBytes: scenario.reservation.inputs[0].outpointTransactionHashBytes,
                        outpointIndex: scenario.reservation.inputs[0].outpointIndex,
                        amountSatoshis: scenario.reservation.inputs[0].amountSatoshis,
                        lockingScriptBytes: [0x51],
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

        do {
            var scenario = try ProductionWorkflowTestFixtures.makeScenario()
            let input = scenario.reservation.inputs[0]
            let inputFee = OpalFusion.Execution.ProtocolPrimitives.componentFee(
                sizeBytes: OpalFusion.Execution.ProtocolPrimitives.inputSize(
                    for: input.publicKey ?? []
                ),
                feeRateSatoshisPerKb: scenario.serverHello.componentFeeRateSatoshisPerKb
            )
            let outputFee = OpalFusion.Execution.ProtocolPrimitives.componentFee(
                sizeBytes: OpalFusion.Execution.ProtocolPrimitives.outputSize(
                    for: scenario.reservation.outputs[0].lockingScriptBytes
                ),
                feeRateSatoshisPerKb: scenario.serverHello.componentFeeRateSatoshisPerKb
            )
            let outputAmount = (input.amountSatoshis * 2) - (inputFee * 2) - outputFee - 250
            scenario.round.participantReservation = .init(
                inputs: [input, input],
                outputs: [
                    .init(
                        lockingScriptBytes: scenario.reservation.outputs[0].lockingScriptBytes,
                        amountSatoshis: outputAmount
                    )
                ]
            )
            _ = try scenario.workflow.buildPlayerCommit(round: &scenario.round)
            Issue.record("Expected duplicate participant input outpoint to fail")
        } catch let error as OpalFusion.Execution.WorkflowFailure {
            #expect(
                error == .invalidParticipantReservation(
                    "Participant reservation contains duplicate input outpoints"
                )
            )
        }
    }

    @Test("Production workflow rejects compressed-length participant keys that are not curve points")
    func validateParticipantReservationRejectsInvalidCompressedPublicKey() throws {
        let invalidCompressedPublicKey = [UInt8](arrayLiteral: 0x02)
            + [UInt8](repeating: 0x00, count: 32)

        do {
            var scenario = try ProductionWorkflowTestFixtures.makeScenario()
            scenario.round.participantReservation = .init(
                inputs: [
                    .init(
                        outpointTransactionHashBytes: scenario.reservation.inputs[0].outpointTransactionHashBytes,
                        outpointIndex: scenario.reservation.inputs[0].outpointIndex,
                        amountSatoshis: scenario.reservation.inputs[0].amountSatoshis,
                        lockingScriptBytes: ProductionWorkflowTestFixtures.p2pkhLockingScript(
                            publicKey: invalidCompressedPublicKey
                        ),
                        publicKey: invalidCompressedPublicKey
                    )
                ],
                outputs: scenario.reservation.outputs
            )
            _ = try scenario.workflow.buildPlayerCommit(round: &scenario.round)
            Issue.record("Expected invalid curve-point reservation to fail")
        } catch let error as OpalFusion.Execution.WorkflowFailure {
            #expect(
                error == .invalidParticipantReservation(
                    "Participant input at index 0 must provide the compressed public key required for standard P2PKH support"
                )
            )
        }
    }

    @Test("Production workflow rejects participant amounts above the BCH money supply")
    func validateParticipantReservationRejectsImpossibleAmounts() throws {
        var scenario = try ProductionWorkflowTestFixtures.makeScenario()
        let impossibleInputAmount: UInt64 = 3_000_000_000_000_000
        let inputFee = OpalFusion.Execution.ProtocolPrimitives.componentFee(
            sizeBytes: OpalFusion.Execution.ProtocolPrimitives.inputSize(
                for: scenario.reservation.inputs[0].publicKey ?? []
            ),
            feeRateSatoshisPerKb: scenario.serverHello.componentFeeRateSatoshisPerKb
        )
        let outputFee = OpalFusion.Execution.ProtocolPrimitives.componentFee(
            sizeBytes: OpalFusion.Execution.ProtocolPrimitives.outputSize(
                for: scenario.reservation.outputs[0].lockingScriptBytes
            ),
            feeRateSatoshisPerKb: scenario.serverHello.componentFeeRateSatoshisPerKb
        )
        let impossibleOutputAmount = impossibleInputAmount - inputFee - outputFee - 250

        scenario.round.participantReservation = .init(
            inputs: [
                .init(
                    outpointTransactionHashBytes: scenario.reservation.inputs[0].outpointTransactionHashBytes,
                    outpointIndex: scenario.reservation.inputs[0].outpointIndex,
                    amountSatoshis: impossibleInputAmount,
                    lockingScriptBytes: scenario.reservation.inputs[0].lockingScriptBytes,
                    publicKey: scenario.reservation.inputs[0].publicKey
                )
            ],
            outputs: [
                .init(
                    lockingScriptBytes: scenario.reservation.outputs[0].lockingScriptBytes,
                    amountSatoshis: impossibleOutputAmount
                )
            ]
        )

        do {
            _ = try scenario.workflow.buildPlayerCommit(round: &scenario.round)
            Issue.record("Expected impossible participant amount to fail")
        } catch let error as OpalFusion.Execution.WorkflowFailure {
            #expect(
                error == .invalidParticipantReservation(
                    "Participant input at index 0 exceeds the maximum BCH money supply"
                )
            )
        }
    }

    @Test("Production workflow rejects coordinator fee rates that exceed safe arithmetic range")
    func validateCoordinatorFeeRateOverflowRejection() throws {
        var scenario = try ProductionWorkflowTestFixtures.makeScenario()
        let startRound = scenario.round.startRound
        let identifier = scenario.round.identifier
        let participantReservation = scenario.round.participantReservation
        let serverHello = OpalFusion.ProtocolModel.ServerHello(
            tiers: scenario.serverHello.tiers,
            numberOfComponents: scenario.serverHello.numberOfComponents,
            componentFeeRateSatoshisPerKb: UInt64.max,
            minimumExcessFeeSatoshis: scenario.serverHello.minimumExcessFeeSatoshis,
            maximumExcessFeeSatoshis: scenario.serverHello.maximumExcessFeeSatoshis,
            donationAddress: scenario.serverHello.donationAddress
        )
        scenario.round = .init(
            fusionBegin: scenario.fusionBegin,
            serverHello: serverHello,
            deadlines: scenario.round.deadlines
        )
        scenario.round.startRound = startRound
        scenario.round.identifier = identifier
        scenario.round.participantReservation = participantReservation

        do {
            _ = try scenario.workflow.buildPlayerCommit(round: &scenario.round)
            Issue.record("Expected impossible coordinator fee rate to fail")
        } catch let error as OpalFusion.Execution.WorkflowFailure {
            #expect(
                error == .protocolValidationFailed(
                    "Coordinator component fee rate was too large"
                )
            )
        }
    }

    @Test("Production workflow encodes long session-hash script pushes with PUSHDATA opcodes")
    func validateLongSessionHashScriptPushEncoding() {
        let longLokad = [UInt8](repeating: 0xAA, count: 76)
        let longSessionHash = [UInt8](repeating: 0xBB, count: 76)
        let baseline = OpalFusion.Transport.BaselineConfiguration(
            protocolIdentity: .init(
                versionBytes: [0x01],
                fusionLokadId: longLokad,
                minimumOutputAmountSatoshis: 10_000
            ),
            framing: ProductionWorkflowTestFixtures.baseline.framing,
            covertTiming: ProductionWorkflowTestFixtures.baseline.covertTiming,
            roundTiming: ProductionWorkflowTestFixtures.baseline.roundTiming
        )

        let script = OpalFusion.Execution.ProtocolPrimitives.makeSessionHashLockingScript(
            sessionHash: longSessionHash,
            baseline: baseline
        )

        #expect(script == [0x6A, 0x4C, 76] + longLokad + [0x4C, 76] + longSessionHash)
    }

    @Test("Production workflow derives the unsigned template and extracts local signatures")
    func validateTransactionTemplateAndSignatureExtraction() async throws {
        var scenario = try ProductionWorkflowTestFixtures.makeScenario()
        let playerCommit = try scenario.buildPlayerCommit()
        _ = try await scenario.buildBlindSignatureResponses(for: playerCommit)

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
            proposal.unsignedTransactionBytes
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
                == scenario.reservation.outputs[0].lockingScriptBytes
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
                transactionBytes: try mismatchedTransaction.serialized()
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

    @Test("Production workflow preserves coordinator input order when extracting local signatures")
    func validateTransactionTemplatePreservesCoordinatorInputOrder() async throws {
        var scenario = try ProductionWorkflowTestFixtures.makeTwoInputScenario()
        let playerCommit = try scenario.buildPlayerCommit()
        _ = try await scenario.buildBlindSignatureResponses(for: playerCommit)
        _ = try scenario.workflow.buildCovertComponentMessages(round: &scenario.round)

        guard let material = scenario.round.executionMaterial.playerCommitMaterial else {
            Issue.record("Expected player-commit material to be cached in round context")
            return
        }
        let componentsByOriginalSlot = Dictionary(
            uniqueKeysWithValues: material.componentsByCommitmentOrder.map {
                ($0.originalSlot, $0)
            }
        )
        guard let firstReservationInputComponent = componentsByOriginalSlot[0],
              let secondReservationInputComponent = componentsByOriginalSlot[1],
              let outputComponent = componentsByOriginalSlot[2],
              let blankComponent = componentsByOriginalSlot[3] else {
            Issue.record("Expected two inputs, one output, and one blank component")
            return
        }

        try scenario.useSharedRound(
            allCommitments: playerCommit.initialCommitments,
            serializedComponents: [
                secondReservationInputComponent.serializedComponent,
                firstReservationInputComponent.serializedComponent,
                outputComponent.serializedComponent,
                blankComponent.serializedComponent,
            ]
        )

        let proposal = try scenario.workflow.buildTransactionFinalizationProposal(
            round: &scenario.round
        )
        let unsignedTransaction = try OpalFusion.Execution.BCHTransaction.parse(
            proposal.unsignedTransactionBytes
        )

        #expect(unsignedTransaction.inputs.count == 2)
        #expect(
            unsignedTransaction.inputs[0].previousTransactionHashLittleEndian ==
                Array(scenario.reservation.inputs[1].outpointTransactionHashBytes.reversed())
        )
        #expect(
            unsignedTransaction.inputs[1].previousTransactionHashLittleEndian ==
                Array(scenario.reservation.inputs[0].outpointTransactionHashBytes.reversed())
        )

        let signingResult = try ProductionWorkflowTestFixtures.makeSignedFinalizedTransaction(
            proposal: proposal,
            participantInputs: scenario.reservation.inputs,
            participantInputPrivateKeys: scenario.participantInputPrivateKeys
        )
        scenario.round.finalizedTransaction = signingResult.transaction

        let signatureMessages = try scenario.workflow.buildCovertSignatureMessages(
            round: &scenario.round
        )
        var signaturePayloads: [OpalFusion.ProtocolModel.CovertTransactionSignature] = []
        for message in signatureMessages {
            guard case let .transactionSignature(payload) = message else {
                Issue.record("Expected a covert transaction signature message")
                return
            }
            signaturePayloads.append(payload)
        }

        #expect(signaturePayloads.map(\.inputIndex) == [UInt32(1), UInt32(0)])
        #expect(
            signaturePayloads.map(\.transactionSignature)
                == signingResult.signaturesByReservationInputIndex
        )
        #expect(
            signingResult.transactionInputIndicesByReservationInputIndex == [1, 0]
        )
    }

    @Test("Production workflow rejects shared output components above the BCH money supply")
    func validateSharedOutputComponentRejectsImpossibleAmount() throws {
        var scenario = try ProductionWorkflowTestFixtures.makeScenario()
        let playerCommit = try scenario.buildPlayerCommit()

        var component = FusionComponent()
        component.saltCommitment = Self.saltCommitment(0xA0)
        var output = FusionOutputComponent()
        output.scriptpubkey = Data([0x51])
        output.amount = OpalFusion.Execution.ProtocolPrimitives.maximumMoneySatoshis + 1
        component.component = .output(output)

        try scenario.useSharedRound(
            allCommitments: playerCommit.initialCommitments + [
                .init(
                    saltedComponentHash: [0xA1],
                    amountCommitment: [0xA2],
                    communicationPublicKey: [0xA3]
                )
            ],
            serializedComponents: scenario.localSerializedComponents()
                + [try Array(component.serializedData())]
        )

        do {
            _ = try scenario.workflow.buildTransactionFinalizationProposal(round: &scenario.round)
            Issue.record("Expected impossible shared output amount to fail")
        } catch let error as OpalFusion.Execution.WorkflowFailure {
            #expect(
                error == .protocolValidationFailed(
                    "Shared output component at index 3 exceeds the maximum BCH money supply"
                )
            )
        }
    }

    @Test("Production workflow rejects shared output components below the minimum amount")
    func validateSharedOutputComponentRejectsDustAmount() throws {
        var scenario = try ProductionWorkflowTestFixtures.makeScenario()
        let playerCommit = try scenario.buildPlayerCommit()

        var component = FusionComponent()
        component.saltCommitment = Self.saltCommitment(0xD0)
        var output = FusionOutputComponent()
        output.scriptpubkey = Data([0x51])
        output.amount = 1
        component.component = .output(output)

        try scenario.useSharedRound(
            allCommitments: playerCommit.initialCommitments + [
                .init(
                    saltedComponentHash: [0xD1],
                    amountCommitment: [0xD2],
                    communicationPublicKey: [0xD3]
                )
            ],
            serializedComponents: scenario.localSerializedComponents()
                + [try Array(component.serializedData())]
        )

        do {
            _ = try scenario.workflow.buildTransactionFinalizationProposal(round: &scenario.round)
            Issue.record("Expected dust shared output to fail")
        } catch let error as OpalFusion.Execution.WorkflowFailure {
            #expect(
                error == .protocolValidationFailed(
                    "Shared output component at index 3 is below the minimum allowed amount"
                )
            )
        }
    }

    @Test("Production workflow rejects shared component count mismatches")
    func validateSharedComponentCountMustMatchCommitments() throws {
        var scenario = try ProductionWorkflowTestFixtures.makeScenario()
        let playerCommit = try scenario.buildPlayerCommit()

        var extraComponent = FusionComponent()
        extraComponent.saltCommitment = Self.saltCommitment(0xE0)
        extraComponent.component = .blank(.init())

        try scenario.useSharedRound(
            allCommitments: playerCommit.initialCommitments,
            serializedComponents: scenario.localSerializedComponents()
                + [try Array(extraComponent.serializedData())]
        )

        do {
            _ = try scenario.workflow.buildTransactionFinalizationProposal(round: &scenario.round)
            Issue.record("Expected shared component count mismatch to fail")
        } catch let error as OpalFusion.Execution.WorkflowFailure {
            #expect(
                error == .protocolValidationFailed(
                    "Coordinator returned a different number of shared components than commitments"
                )
            )
        }
    }

    @Test("Production workflow rejects shared components with short salt commitments")
    func validateSharedComponentRejectsShortSaltCommitment() throws {
        var scenario = try ProductionWorkflowTestFixtures.makeScenario()
        let playerCommit = try scenario.buildPlayerCommit()

        var component = FusionComponent()
        component.saltCommitment = Data([0xE1])
        component.component = .blank(.init())

        try scenario.useSharedRound(
            allCommitments: playerCommit.initialCommitments + [
                .init(
                    saltedComponentHash: [0xE2],
                    amountCommitment: [0xE3],
                    communicationPublicKey: [0xE4]
                )
            ],
            serializedComponents: scenario.localSerializedComponents()
                + [try Array(component.serializedData())]
        )

        do {
            _ = try scenario.workflow.buildTransactionFinalizationProposal(round: &scenario.round)
            Issue.record("Expected short salt commitment to fail")
        } catch let error as OpalFusion.Execution.WorkflowFailure {
            #expect(
                error == .protocolValidationFailed(
                    "Shared component at index 3 salt commitment must be 32 bytes"
                )
            )
        }
    }

    @Test("Production workflow maps impossible transaction template totals")
    func validateTransactionFinalizationProposalRejectsImpossibleOutputTotal() throws {
        var scenario = try ProductionWorkflowTestFixtures.makeScenario()
        let playerCommit = try scenario.buildPlayerCommit()

        var component = FusionComponent()
        component.saltCommitment = Self.saltCommitment(0xF0)
        var output = FusionOutputComponent()
        output.scriptpubkey = Data([0x51])
        output.amount = OpalFusion.Execution.ProtocolPrimitives.maximumMoneySatoshis
        component.component = .output(output)

        try scenario.useSharedRound(
            allCommitments: playerCommit.initialCommitments + [
                .init(
                    saltedComponentHash: [0xF1],
                    amountCommitment: [0xF2],
                    communicationPublicKey: [0xF3]
                )
            ],
            serializedComponents: scenario.localSerializedComponents()
                + [try Array(component.serializedData())]
        )

        do {
            _ = try scenario.workflow.buildTransactionFinalizationProposal(round: &scenario.round)
            Issue.record("Expected impossible transaction template total to fail")
        } catch let error as OpalFusion.Execution.WorkflowFailure {
            #expect(
                error == .protocolValidationFailed(
                    "Transaction output total exceeds the maximum BCH money supply"
                )
            )
        }
    }

    @Test("Production workflow rejects shared input components with invalid public keys")
    func validateSharedInputComponentRejectsInvalidPublicKey() throws {
        var scenario = try ProductionWorkflowTestFixtures.makeScenario()
        let playerCommit = try scenario.buildPlayerCommit()

        var component = FusionComponent()
        component.saltCommitment = Self.saltCommitment(0xB0)
        var input = FusionInputComponent()
        input.prevTxid = Data([UInt8](repeating: 0xCC, count: 32).reversed())
        input.prevIndex = 2
        input.pubkey = Data([UInt8](arrayLiteral: 0x02) + [UInt8](repeating: 0x00, count: 32))
        input.amount = 60_000
        component.component = .input(input)

        try scenario.useSharedRound(
            allCommitments: playerCommit.initialCommitments + [
                .init(
                    saltedComponentHash: [0xB1],
                    amountCommitment: [0xB2],
                    communicationPublicKey: [0xB3]
                )
            ],
            serializedComponents: scenario.localSerializedComponents()
                + [try Array(component.serializedData())]
        )

        do {
            _ = try scenario.workflow.buildTransactionFinalizationProposal(round: &scenario.round)
            Issue.record("Expected invalid shared input public key to fail")
        } catch let error as OpalFusion.Execution.WorkflowFailure {
            #expect(
                error == .protocolValidationFailed(
                    "Shared input component at index 3 must provide a valid compressed public key"
                )
            )
        }
    }

    @Test("Production workflow rejects shared input components with short previous hashes")
    func validateSharedInputComponentRejectsShortPreviousHash() throws {
        var scenario = try ProductionWorkflowTestFixtures.makeScenario()
        let playerCommit = try scenario.buildPlayerCommit()

        guard let publicKey = scenario.reservation.inputs[0].publicKey else {
            Issue.record("Expected fixture public key")
            return
        }

        var component = FusionComponent()
        component.saltCommitment = Self.saltCommitment(0xC0)
        var input = FusionInputComponent()
        input.prevTxid = Data([UInt8](repeating: 0xCC, count: 31))
        input.prevIndex = 2
        input.pubkey = Data(publicKey)
        input.amount = 60_000
        component.component = .input(input)

        try scenario.useSharedRound(
            allCommitments: playerCommit.initialCommitments + [
                .init(
                    saltedComponentHash: [0xC1],
                    amountCommitment: [0xC2],
                    communicationPublicKey: [0xC3]
                )
            ],
            serializedComponents: scenario.localSerializedComponents()
                + [try Array(component.serializedData())]
        )

        do {
            _ = try scenario.workflow.buildTransactionFinalizationProposal(round: &scenario.round)
            Issue.record("Expected short previous transaction hash to fail")
        } catch let error as OpalFusion.Execution.WorkflowFailure {
            #expect(
                error == .protocolValidationFailed(
                    "Shared input component at index 3 previous transaction hash must be 32 bytes"
                )
            )
        }
    }

    @Test("Production workflow rejects duplicate shared input outpoints")
    func validateSharedInputComponentRejectsDuplicateOutpoint() throws {
        var scenario = try ProductionWorkflowTestFixtures.makeScenario()
        let playerCommit = try scenario.buildPlayerCommit()

        guard let publicKey = scenario.reservation.inputs[0].publicKey else {
            Issue.record("Expected fixture public key")
            return
        }

        var component = FusionComponent()
        component.saltCommitment = Self.saltCommitment(0xC8)
        var input = FusionInputComponent()
        input.prevTxid = Data(scenario.reservation.inputs[0].outpointTransactionHashBytes.reversed())
        input.prevIndex = scenario.reservation.inputs[0].outpointIndex
        input.pubkey = Data(publicKey)
        input.amount = scenario.reservation.inputs[0].amountSatoshis
        component.component = .input(input)

        try scenario.useSharedRound(
            allCommitments: playerCommit.initialCommitments + [
                .init(
                    saltedComponentHash: [0xC9],
                    amountCommitment: [0xCA],
                    communicationPublicKey: [0xCB]
                )
            ],
            serializedComponents: scenario.localSerializedComponents()
                + [try Array(component.serializedData())]
        )

        do {
            _ = try scenario.workflow.buildTransactionFinalizationProposal(round: &scenario.round)
            Issue.record("Expected duplicate shared input outpoint to fail")
        } catch let error as OpalFusion.Execution.WorkflowFailure {
            #expect(
                error == .protocolValidationFailed(
                    "Coordinator returned duplicate input outpoints"
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
            OpalCrypto.Communication.Ciphertext(
                rawRepresentation: Data(myProofsList.encryptedProofs[0])
            ),
            privateKey: OpalCrypto.Secp256k1.PrivateKey(
                rawRepresentation: Data(extraInputComponent.communicationPrivateKey)
            )
        )
        let parsedProof = try FusionProof(serializedBytes: decryptedProof.message)
        #expect(sharedRoundMaterial.myComponentIndices.contains(Int(parsedProof.componentIdx)))

        let destinationComponent = playerCommitMaterial.componentsByCommitmentOrder[0]
        let invalidEncryptedProof = try Array(
            OpalCrypto.Communication.encrypt(
                message: Data([0x00]),
                recipientPublicKey: OpalCrypto.Secp256k1.PublicKey(
                    rawRepresentation: Data(
                        destinationComponent.initialCommitment.communicationPublicKey
                    )
                )
            ).rawRepresentation
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

    @Test("Production workflow fails proof generation when a destination communication key is invalid")
    func validateProofGenerationRejectsInvalidDestinationCommunicationKey() throws {
        var scenario = try ProductionWorkflowTestFixtures.makeScenario()
        let playerCommit = try scenario.buildPlayerCommit()
        let externalComponent = try scenario.makeExternalInputComponent()
        let invalidCommunicationPublicKey = [UInt8](arrayLiteral: 0x02)
            + [UInt8](repeating: 0x00, count: 32)
        let invalidExternalCommitment = OpalFusion.Commitment.InitialCommitment(
            saltedComponentHash: externalComponent.initialCommitment.saltedComponentHash,
            amountCommitment: externalComponent.initialCommitment.amountCommitment,
            communicationPublicKey: invalidCommunicationPublicKey
        )
        try scenario.useSharedRound(
            allCommitments: playerCommit.initialCommitments + [invalidExternalCommitment],
            serializedComponents: scenario.localSerializedComponents()
                + [externalComponent.serializedComponent]
        )

        do {
            _ = try scenario.workflow.buildMyProofsList(round: &scenario.round)
            Issue.record("Expected invalid proof destination key to fail")
        } catch let error as OpalFusion.Execution.WorkflowFailure {
            guard case let .protocolValidationFailed(summary) = error else {
                Issue.record("Expected protocol validation failure")
                return
            }
            #expect(summary.hasPrefix("Proof encryption failed"))
        }
    }
}

private extension ProductionWorkflowValidator {
    static func saltCommitment(_ byte: UInt8) -> Data {
        Data(repeating: byte, count: 32)
    }
}

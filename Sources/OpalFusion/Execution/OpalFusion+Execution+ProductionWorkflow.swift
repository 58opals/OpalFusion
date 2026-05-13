// OpalFusion+Execution+ProductionWorkflow.swift

import Foundation
import OpalCrypto
import SwiftProtobuf
extension OpalFusion.Execution {
    struct ProductionWorkflow: Sendable {
        let baseline: OpalFusion.Transport.BaselineConfiguration
        let pedersenSetup: OpalCrypto.Pedersen.Setup

        init(
            baseline: OpalFusion.Transport.BaselineConfiguration
        ) {
            self.baseline = baseline
            self.pedersenSetup = try! OpalCrypto.Pedersen.Setup(
                alternateBasePoint: OpalFusion.Execution.ProtocolPrimitives
                    .pedersenAlternateBasePublicKey
            )
        }

        func buildPlayerCommit(
            round: inout OpalFusion.Execution.RoundContext
        ) throws -> OpalFusion.ProtocolModel.PlayerCommit {
            let material = try ensurePlayerCommitMaterial(round: &round)
            let randomCommitment = OpalFusion.Execution.ProtocolPrimitives.sha256(
                material.randomNumber
            )
            let blindRequests = material.blindSignatureRequests.map {
                OpalFusion.BlindSignature.Request(scalar: Array($0.scalar.rawRepresentation))
            }
            return .init(
                initialCommitments: material.componentsByCommitmentOrder.map(\.initialCommitment),
                excessFeeSatoshis: material.excessFeeSatoshis,
                pedersenTotalNonce: material.pedersenTotalNonce,
                randomNumberCommitment: randomCommitment,
                blindSignatureRequests: blindRequests
            )
        }

        func buildCovertComponentMessages(
            round: inout OpalFusion.Execution.RoundContext
        ) throws -> [OpalFusion.ProtocolModel.CovertMessage] {
            let material = try ensurePlayerCommitMaterial(round: &round)
            guard let startRound = round.startRound else {
                throw OpalFusion.Execution.WorkflowFailure.protocolValidationFailed(
                    "StartRound must be present before covert component submission"
                )
            }
            guard let responses = round.blindSignatureResponses else {
                throw OpalFusion.Execution.WorkflowFailure.protocolValidationFailed(
                    "Blind signature responses were missing for covert component submission"
                )
            }
            guard responses.responses.count == material.blindSignatureRequests.count else {
                throw OpalFusion.Execution.WorkflowFailure.protocolValidationFailed(
                    "Coordinator returned the wrong number of blind signature responses"
                )
            }

            let finalizedBlindSignatures: [[UInt8]]
            do {
                finalizedBlindSignatures = try zip(
                    material.blindSignatureRequests,
                    responses.responses
                ).map { request, response in
                    try Array(
                        request.finalize(
                            responseScalar: try OpalCrypto.Secp256k1.Scalar(
                                rawRepresentation: Data(response.scalar)
                            ),
                            verify: true
                        ).rawRepresentation
                    )
                }
            } catch {
                throw OpalFusion.Execution.WorkflowFailure.protocolValidationFailed(
                    "Blind signature finalization failed"
                )
            }

            round.executionMaterial.finalizedBlindSignatures = finalizedBlindSignatures

            return zip(
                material.componentsByCommitmentOrder,
                finalizedBlindSignatures
            )
            .sorted { lhs, rhs in
                lhs.0.originalSlot < rhs.0.originalSlot
            }
            .map { component, blindSignature in
                .component(
                    .init(
                        roundPublicKey: startRound.roundPublicKey,
                        signature: blindSignature,
                        serializedComponent: component.serializedComponent
                    )
                )
            }
        }

        func buildTransactionFinalizationProposal(
            round: inout OpalFusion.Execution.RoundContext
        ) throws -> OpalFusion.Host.TransactionFinalizationProposal {
            let sharedMaterial = try ensureSharedRoundMaterial(round: &round)
            let unsignedTransactionBytes: [UInt8]
            do {
                unsignedTransactionBytes = try sharedMaterial.transactionTemplate.serialized()
            } catch let error as OpalFusion.Execution.BCHTransactionError {
                throw mapTransactionError(error)
            }
            return .init(
                unsignedTransactionBytes: unsignedTransactionBytes,
                sessionHash: sharedMaterial.sessionHash,
                expectedInputCount: sharedMaterial.transactionTemplate.inputs.count,
                expectedOutputCount: sharedMaterial.transactionTemplate.outputs.count,
                participantCount: nil
            )
        }

        func buildCovertSignatureMessages(
            round: inout OpalFusion.Execution.RoundContext
        ) throws -> [OpalFusion.ProtocolModel.CovertMessage] {
            try ensureCovertSignatureMessages(round: &round)
        }

        func buildMyProofsList(
            round: inout OpalFusion.Execution.RoundContext
        ) throws -> OpalFusion.ProtocolModel.MyProofsList {
            let playerCommitMaterial = try ensurePlayerCommitMaterial(round: &round)
            let sharedMaterial = try ensureSharedRoundMaterial(round: &round)

            let othersCommitmentIndices = sharedMaterial.allCommitmentBytes.indices.filter {
                sharedMaterial.myCommitmentIndices.contains($0) == false
            }
            guard othersCommitmentIndices.isEmpty == false else {
                throw OpalFusion.Execution.WorkflowFailure.protocolValidationFailed(
                    "Blame handling requires commitments from other participants"
                )
            }

            let encryptedProofs = try playerCommitMaterial.componentsByCommitmentOrder.enumerated().map {
                index, component in
                let destinationCommitmentIndex = othersCommitmentIndices[
                    OpalFusion.Execution.ProtocolPrimitives.randPosition(
                        seed: playerCommitMaterial.randomNumber,
                        numberOfPositions: othersCommitmentIndices.count,
                        counter: index
                    )
                ]
                let destinationCommitment = try parseInitialCommitment(
                    bytes: sharedMaterial.allCommitmentBytes[destinationCommitmentIndex]
                )
                let proof = try serializeProof(
                    componentIndex: UInt32(sharedMaterial.myComponentIndices[index]),
                    salt: component.proofMaterial.salt,
                    pedersenNonce: component.proofMaterial.pedersenNonce
                )
                do {
                    return Array(
                        try OpalCrypto.Communication.encrypt(
                            message: Data(proof),
                            recipientPublicKey: OpalCrypto.Secp256k1.PublicKey(
                                rawRepresentation: Data(destinationCommitment.communicationPublicKey)
                            ),
                            paddedPlaintextLength: 80
                        ).rawRepresentation
                    )
                } catch {
                    throw OpalFusion.Execution.WorkflowFailure.protocolValidationFailed(
                        "Proof encryption failed"
                    )
                }
            }

            return .init(
                encryptedProofs: encryptedProofs,
                randomNumber: playerCommitMaterial.randomNumber
            )
        }

        func buildBlames(
            round: inout OpalFusion.Execution.RoundContext
        ) throws -> OpalFusion.ProtocolModel.Blames {
            let playerCommitMaterial = try ensurePlayerCommitMaterial(round: &round)
            let sharedMaterial = try ensureSharedRoundMaterial(round: &round)
            guard let theirProofsList = round.theirProofsList else {
                throw OpalFusion.Execution.WorkflowFailure.protocolValidationFailed(
                    "TheirProofsList must be present before blame construction"
                )
            }

            var blames: [OpalFusion.Blame.BlameProof] = []
            let badComponentIndices = Set(round.fusionResult?.badComponentIndices ?? [])

            for (proofIndex, relayedProof) in theirProofsList.proofs.enumerated() {
                let destinationIndex = Int(relayedProof.destinationKeyIndex)
                guard playerCommitMaterial.componentsByCommitmentOrder.indices.contains(destinationIndex) else {
                    throw OpalFusion.Execution.WorkflowFailure.protocolValidationFailed(
                        "Coordinator relayed a proof with an invalid destination key index"
                    )
                }
                let sourceCommitmentIndex = Int(relayedProof.sourceCommitmentIndex)
                guard sharedMaterial.allCommitmentBytes.indices.contains(sourceCommitmentIndex) else {
                    throw OpalFusion.Execution.WorkflowFailure.protocolValidationFailed(
                        "Coordinator relayed a proof with an invalid source commitment index"
                    )
                }

                let localComponent = playerCommitMaterial.componentsByCommitmentOrder[destinationIndex]
                let sourceCommitment = try parseInitialCommitment(
                    bytes: sharedMaterial.allCommitmentBytes[sourceCommitmentIndex]
                )

                let decrypted: OpalCrypto.Communication.DecryptionResult
                do {
                    decrypted = try OpalCrypto.Communication.decrypt(
                        OpalCrypto.Communication.Ciphertext(
                            rawRepresentation: Data(relayedProof.encryptedProof)
                        ),
                        privateKey: OpalCrypto.Secp256k1.PrivateKey(
                            rawRepresentation: Data(localComponent.communicationPrivateKey)
                        )
                    )
                } catch {
                    blames.append(
                        .init(
                            proofIndex: UInt32(proofIndex),
                            decrypter: .privateKey(localComponent.communicationPrivateKey),
                            reason: "undecryptable"
                        )
                    )
                    continue
                }

                let validatedProof: OpalFusion.Execution.ValidatedProof
                do {
                    validatedProof = try validateRelayedProof(
                        decrypted.message.bytes,
                        sourceCommitment: sourceCommitment,
                        sharedRoundMaterial: sharedMaterial,
                        badComponentIndices: badComponentIndices,
                        feeRateSatoshisPerKb: round.serverHello.componentFeeRateSatoshisPerKb
                    )
                } catch let error as OpalFusion.Execution.RelayedProofValidationFailure {
                    blames.append(
                        .init(
                            proofIndex: UInt32(proofIndex),
                            decrypter: .sessionKey(decrypted.symmetricKey.rawRepresentation.bytes),
                            requiresBlockchainLookup: false,
                            reason: error.reason
                        )
                    )
                    continue
                }

                if case .input = validatedProof {
                    blames.append(
                        .init(
                            proofIndex: UInt32(proofIndex),
                            decrypter: .sessionKey(decrypted.symmetricKey.rawRepresentation.bytes),
                            requiresBlockchainLookup: true,
                            reason: "input requires blockchain lookup"
                        )
                    )
                }
            }

            return .init(blames: blames)
        }

        private func ensureCovertSignatureMessages(
            round: inout OpalFusion.Execution.RoundContext
        ) throws -> [OpalFusion.ProtocolModel.CovertMessage] {
            guard let finalizedTransaction = round.finalizedTransaction else {
                throw OpalFusion.Execution.WorkflowFailure.protocolValidationFailed(
                    "Finalized transaction was missing for signature submission"
                )
            }
            if let cachedMessages = round.executionMaterial.covertSignatureMessages,
               round.executionMaterial.covertSignatureSourceTransaction ==
                finalizedTransaction.transactionBytes {
                return cachedMessages
            }

            let sharedMaterial = try ensureSharedRoundMaterial(round: &round)
            guard let startRound = round.startRound else {
                throw OpalFusion.Execution.WorkflowFailure.protocolValidationFailed(
                    "StartRound must be present before signature submission"
                )
            }

            let parsedFinalizedTransaction: OpalFusion.Execution.BCHTransaction
            do {
                parsedFinalizedTransaction = try .parse(finalizedTransaction.transactionBytes)
            } catch let error as OpalFusion.Execution.BCHTransactionError {
                throw mapTransactionError(error)
            }

            do {
                try validateFinalizedTransaction(
                    parsedFinalizedTransaction,
                    against: sharedMaterial.transactionTemplate,
                    localInputReferences: sharedMaterial.localInputReferences
                )
            } catch let error as OpalFusion.Execution.BCHTransactionError {
                throw mapTransactionError(error)
            }

            let messages: [OpalFusion.ProtocolModel.CovertMessage]
            do {
                messages = try sharedMaterial.localInputReferences
                    .sorted(by: { $0.originalSlot < $1.originalSlot })
                    .map { inputReference in
                        let signature = try extractLocalSignature(
                            from: parsedFinalizedTransaction.inputs[inputReference.transactionInputIndex],
                            transaction: parsedFinalizedTransaction,
                            inputReference: inputReference
                        )
                        return OpalFusion.ProtocolModel.CovertMessage.transactionSignature(
                            .init(
                                roundPublicKey: startRound.roundPublicKey,
                                inputIndex: UInt32(inputReference.transactionInputIndex),
                                transactionSignature: signature
                            )
                        )
                    }
            } catch let error as OpalFusion.Execution.BCHTransactionError {
                throw mapTransactionError(error)
            }

            round.executionMaterial.covertSignatureMessages = messages
            round.executionMaterial.covertSignatureSourceTransaction =
                finalizedTransaction.transactionBytes
            return messages
        }

        private func ensurePlayerCommitMaterial(
            round: inout OpalFusion.Execution.RoundContext
        ) throws -> OpalFusion.Execution.PlayerCommitMaterial {
            if let material = round.executionMaterial.playerCommitMaterial {
                return material
            }
            guard let reservation = round.participantReservation else {
                throw OpalFusion.Execution.WorkflowFailure.invalidParticipantReservation(
                    "Participant reservation was not loaded"
                )
            }
            guard let startRound = round.startRound else {
                throw OpalFusion.Execution.WorkflowFailure.protocolValidationFailed(
                    "StartRound must be present before player commit construction"
                )
            }

            let numberOfComponents = Int(round.serverHello.numberOfComponents)
            guard reservation.inputs.isEmpty == false else {
                throw OpalFusion.Execution.WorkflowFailure.invalidParticipantReservation(
                    "At least one participant input is required"
                )
            }
            guard reservation.outputs.isEmpty == false else {
                throw OpalFusion.Execution.WorkflowFailure.invalidParticipantReservation(
                    "At least one participant output is required"
                )
            }
            guard reservation.inputs.count + reservation.outputs.count <= numberOfComponents else {
                throw OpalFusion.Execution.WorkflowFailure.invalidParticipantReservation(
                    "Participant reservation exceeds the server component limit"
                )
            }
            guard startRound.blindNoncePoints.count == numberOfComponents else {
                throw OpalFusion.Execution.WorkflowFailure.protocolValidationFailed(
                    "Coordinator returned the wrong number of blind nonce points"
                )
            }

            let feeRateSatoshisPerKb = round.serverHello.componentFeeRateSatoshisPerKb
            var components: [OpalFusion.Execution.LocalComponentMaterial] = []
            components.reserveCapacity(numberOfComponents)

            for (index, input) in reservation.inputs.enumerated() {
                guard input.amountSatoshis <= OpalFusion.Execution.ProtocolPrimitives.maximumMoneySatoshis else {
                    throw OpalFusion.Execution.WorkflowFailure.invalidParticipantReservation(
                        "Participant input at index \(index) exceeds the maximum BCH money supply"
                    )
                }

                let publicKey = try OpalFusion.Execution.ProtocolPrimitives
                    .validateSupportedParticipantInput(
                        input,
                        inputIndex: index
                    )

                let componentPayload = OpalFusion.Commitment.ComponentPayload.input(
                    .init(
                        outpointTransactionHash: input.outpointTransactionHashBytes,
                        outpointIndex: input.outpointIndex,
                        publicKey: publicKey,
                        amountSatoshis: input.amountSatoshis
                    )
                )
                let fee = try checkedComponentFee(
                    sizeBytes: OpalFusion.Execution.ProtocolPrimitives.inputSize(for: publicKey),
                    feeRateSatoshisPerKb: feeRateSatoshisPerKb
                )
                components.append(
                    try buildComponentMaterial(
                        originalSlot: index,
                        payload: componentPayload,
                        contributionSatoshis: Int64(input.amountSatoshis) - Int64(fee)
                    )
                )
            }

            for (index, output) in reservation.outputs.enumerated() {
                guard output.amountSatoshis <= OpalFusion.Execution.ProtocolPrimitives.maximumMoneySatoshis else {
                    throw OpalFusion.Execution.WorkflowFailure.invalidParticipantReservation(
                        "Participant output at index \(index) exceeds the maximum BCH money supply"
                    )
                }

                let minimumAmount = OpalFusion.Execution.ProtocolPrimitives.minimumOutputAmount(
                    for: output.lockingScriptBytes,
                    baseline: baseline
                )
                guard output.amountSatoshis >= minimumAmount else {
                    throw OpalFusion.Execution.WorkflowFailure.invalidParticipantReservation(
                        "Participant output at index \(index) is below the minimum allowed amount"
                    )
                }

                let componentPayload = OpalFusion.Commitment.ComponentPayload.output(
                    .init(
                        lockingScript: output.lockingScriptBytes,
                        amountSatoshis: output.amountSatoshis
                    )
                )
                let fee = try checkedComponentFee(
                    sizeBytes: OpalFusion.Execution.ProtocolPrimitives.outputSize(
                        for: output.lockingScriptBytes
                    ),
                    feeRateSatoshisPerKb: feeRateSatoshisPerKb
                )
                let amount = Int64(output.amountSatoshis)
                let signedFee = Int64(fee)
                guard signedFee <= Int64.max - amount else {
                    throw OpalFusion.Execution.WorkflowFailure.protocolValidationFailed(
                        "Coordinator component fee rate was too large"
                    )
                }
                components.append(
                    try buildComponentMaterial(
                        originalSlot: reservation.inputs.count + index,
                        payload: componentPayload,
                        contributionSatoshis: -(amount + signedFee)
                    )
                )
            }

            for slot in components.count..<numberOfComponents {
                components.append(
                    try buildComponentMaterial(
                        originalSlot: slot,
                        payload: .blank(.init()),
                        contributionSatoshis: 0
                    )
                )
            }

            let serializedComponents = components.map(\.serializedComponent)
            guard Self.hasDuplicateByteArrays(serializedComponents) == false else {
                throw OpalFusion.Execution.WorkflowFailure.invalidParticipantReservation(
                    "Participant reservation produced duplicate components"
                )
            }

            let sortedComponents = components.sorted {
                Data($0.serializedInitialCommitment).lexicographicallyPrecedes(
                    Data($1.serializedInitialCommitment)
                )
            }
            let excessFee = sortedComponents.reduce(Int64(0)) { partial, component in
                partial + component.contributionSatoshis
            }
            guard excessFee >= 0 else {
                throw OpalFusion.Execution.WorkflowFailure.invalidParticipantReservation(
                    "Participant reservation does not satisfy the coordinator fee requirements"
                )
            }
            let excessFeeSatoshis = UInt64(excessFee)
            guard excessFeeSatoshis >= round.serverHello.minimumExcessFeeSatoshis,
                  excessFeeSatoshis <= round.serverHello.maximumExcessFeeSatoshis else {
                throw OpalFusion.Execution.WorkflowFailure.invalidParticipantReservation(
                    "Participant reservation produced an excess fee outside the coordinator range"
                )
            }
            guard OpalFusion.Execution.ProtocolPrimitives.isCompressedSecp256k1PublicKey(
                startRound.roundPublicKey
            ) else {
                throw OpalFusion.Execution.WorkflowFailure.protocolValidationFailed(
                    "StartRound round public key must be a valid compressed public key"
                )
            }
            for (index, blindNoncePoint) in startRound.blindNoncePoints.enumerated() {
                guard OpalFusion.Execution.ProtocolPrimitives.isCompressedSecp256k1PublicKey(
                    blindNoncePoint
                ) else {
                    throw OpalFusion.Execution.WorkflowFailure.protocolValidationFailed(
                        "StartRound blind nonce point at index \(index) must be a valid compressed public key"
                    )
                }
            }

            let blindRequests: [OpalCrypto.BlindSignature.Request]
            do {
                blindRequests = try zip(
                    startRound.blindNoncePoints,
                    sortedComponents
                ).map { blindNoncePoint, component in
                    try OpalCrypto.BlindSignature.Request(
                        signerPublicKey: OpalCrypto.Secp256k1.PublicKey(
                            rawRepresentation: Data(startRound.roundPublicKey)
                        ),
                        noncePoint: OpalCrypto.Secp256k1.PublicKey(
                            rawRepresentation: Data(blindNoncePoint)
                        ),
                        messageDigest: OpalCrypto.Signature.Digest(
                            rawRepresentation: Data(
                                OpalFusion.Execution.ProtocolPrimitives.sha256(
                                    component.serializedComponent
                                )
                            )
                        )
                    )
                }
            } catch {
                throw OpalFusion.Execution.WorkflowFailure.protocolValidationFailed(
                    "Blind signature request construction failed"
                )
            }

            let pedersenTotalNonce = try OpalFusion.Execution.ProtocolPrimitives.sumNoncesModOrder(
                sortedComponents.map(\.proofMaterial.pedersenNonce)
            )
            let material = OpalFusion.Execution.PlayerCommitMaterial(
                componentsByCommitmentOrder: sortedComponents,
                blindSignatureRequests: blindRequests,
                pedersenTotalNonce: pedersenTotalNonce,
                excessFeeSatoshis: excessFeeSatoshis,
                randomNumber: try OpalFusion.Execution.ProtocolPrimitives.randomBytes(count: 32)
            )
            round.executionMaterial.playerCommitMaterial = material
            round.executionMaterial.finalizedBlindSignatures = []
            round.executionMaterial.covertSignatureMessages = nil
            round.executionMaterial.covertSignatureSourceTransaction = nil
            return material
        }

        private func ensureSharedRoundMaterial(
            round: inout OpalFusion.Execution.RoundContext
        ) throws -> OpalFusion.Execution.SharedRoundMaterial {
            if let sharedRoundMaterial = round.executionMaterial.sharedRoundMaterial {
                return sharedRoundMaterial
            }

            let playerCommitMaterial = try ensurePlayerCommitMaterial(round: &round)
            guard let startRound = round.startRound,
                  let allCommitments = round.allCommitments,
                  let sharedComponents = round.sharedComponents,
                  let reservation = round.participantReservation else {
                throw OpalFusion.Execution.WorkflowFailure.protocolValidationFailed(
                    "Round data was incomplete for shared component validation"
                )
            }

            let allCommitmentBytes = try allCommitments.initialCommitments.map(serializeInitialCommitment)
            guard Self.hasDuplicateByteArrays(allCommitmentBytes) == false else {
                throw OpalFusion.Execution.WorkflowFailure.protocolValidationFailed(
                    "Coordinator returned duplicate initial commitments"
                )
            }
            let myCommitmentIndices = try playerCommitMaterial.componentsByCommitmentOrder.map { component in
                guard let index = allCommitmentBytes.firstIndex(of: component.serializedInitialCommitment) else {
                    throw OpalFusion.Execution.WorkflowFailure.protocolValidationFailed(
                        "Coordinator omitted one of the local commitments"
                    )
                }
                return index
            }

            let allComponentBytes = sharedComponents.serializedComponents
            guard allComponentBytes.count == allCommitmentBytes.count else {
                throw OpalFusion.Execution.WorkflowFailure.protocolValidationFailed(
                    "Coordinator returned a different number of shared components than commitments"
                )
            }

            guard Self.hasDuplicateByteArrays(allComponentBytes) == false else {
                throw OpalFusion.Execution.WorkflowFailure.protocolValidationFailed(
                    "Coordinator returned duplicate shared components"
                )
            }
            let myComponentIndices = try playerCommitMaterial.componentsByCommitmentOrder.map { component in
                guard let index = allComponentBytes.firstIndex(of: component.serializedComponent) else {
                    throw OpalFusion.Execution.WorkflowFailure.protocolValidationFailed(
                        "Coordinator omitted one of the local components"
                    )
                }
                return index
            }

            let decodedComponents = try allComponentBytes.enumerated().map {
                try decodeComponent(bytes: $0.element, componentIndex: $0.offset)
            }
            let previousHash = OpalFusion.Execution.ProtocolPrimitives.calculateInitialHash(
                fusionBegin: round.fusionBegin,
                baseline: baseline
            )
            let sessionHash = OpalFusion.Execution.ProtocolPrimitives.calculateRoundHash(
                previousHash: previousHash,
                startRound: startRound,
                allCommitmentBytes: allCommitmentBytes,
                allComponentBytes: allComponentBytes
            )
            if let sharedSessionHash = sharedComponents.sessionHash, sharedSessionHash != sessionHash {
                throw OpalFusion.Execution.WorkflowFailure.protocolValidationFailed(
                    "Coordinator returned a mismatched session hash"
                )
            }

            let (transactionTemplate, transactionInputComponentIndices) = try makeTransactionTemplate(
                decodedComponents: decodedComponents,
                sessionHash: sessionHash
            )
            let localInputReferences = try makeLocalInputReferences(
                reservation: reservation,
                playerCommitMaterial: playerCommitMaterial,
                myComponentIndices: myComponentIndices,
                transactionInputComponentIndices: transactionInputComponentIndices
            )
            let material = OpalFusion.Execution.SharedRoundMaterial(
                allCommitmentBytes: allCommitmentBytes,
                allComponentBytes: allComponentBytes,
                sessionHash: sessionHash,
                decodedComponents: decodedComponents,
                myCommitmentIndices: myCommitmentIndices,
                myComponentIndices: myComponentIndices,
                transactionTemplate: transactionTemplate,
                transactionInputComponentIndices: transactionInputComponentIndices,
                localInputReferences: localInputReferences
            )
            round.executionMaterial.sharedRoundMaterial = material
            round.executionMaterial.covertSignatureMessages = nil
            round.executionMaterial.covertSignatureSourceTransaction = nil
            return material
        }

        private func buildComponentMaterial(
            originalSlot: Int,
            payload: OpalFusion.Commitment.ComponentPayload,
            contributionSatoshis: Int64
        ) throws -> OpalFusion.Execution.LocalComponentMaterial {
            let salt = try OpalFusion.Execution.ProtocolPrimitives.randomBytes(count: 32)
            let serializedComponent = try serializeComponent(
                payload: payload,
                saltCommitment: OpalFusion.Execution.ProtocolPrimitives.sha256(salt)
            )
            let pedersenCommitment: OpalCrypto.Pedersen.Commitment
            do {
                pedersenCommitment = try pedersenSetup.commit(amount: contributionSatoshis)
            } catch {
                throw OpalFusion.Execution.WorkflowFailure.protocolValidationFailed(
                    "Pedersen commitment construction failed"
                )
            }
            let communicationPrivateKey: OpalCrypto.Secp256k1.PrivateKey
            let communicationPublicKey: OpalCrypto.Secp256k1.PublicKey
            do {
                communicationPrivateKey = try OpalCrypto.Secp256k1.PrivateKey.generate()
                communicationPublicKey = try OpalCrypto.Secp256k1
                    .derivePublicKey(from: communicationPrivateKey)
            } catch {
                throw OpalFusion.Execution.WorkflowFailure.unsupportedExecution(
                    "Communication key generation failed"
                )
            }

            let initialCommitment = OpalFusion.Commitment.InitialCommitment(
                saltedComponentHash: OpalFusion.Execution.ProtocolPrimitives.sha256(
                    salt + serializedComponent
                ),
                amountCommitment: pedersenCommitment.point.uncompressedRepresentation.bytes,
                communicationPublicKey: communicationPublicKey.rawRepresentation.bytes
            )
            return .init(
                originalSlot: originalSlot,
                payload: payload,
                serializedComponent: serializedComponent,
                serializedInitialCommitment: try serializeInitialCommitment(initialCommitment),
                initialCommitment: initialCommitment,
                proofMaterial: .init(
                    salt: salt,
                    pedersenNonce: pedersenCommitment.nonce.rawRepresentation.bytes
                ),
                communicationPrivateKey: communicationPrivateKey.rawRepresentation.bytes,
                contributionSatoshis: contributionSatoshis
            )
        }

        private func makeTransactionTemplate(
            decodedComponents: [OpalFusion.Execution.DecodedComponent],
            sessionHash: [UInt8]
        ) throws -> (
            transaction: OpalFusion.Execution.BCHTransaction,
            inputComponentIndices: [Int]
        ) {
            var inputs: [OpalFusion.Execution.BCHTransaction.Input] = []
            var outputs: [OpalFusion.Execution.BCHTransaction.Output] = [
                .init(
                    amountSatoshis: 0,
                    lockingScript: OpalFusion.Execution.ProtocolPrimitives
                        .makeSessionHashLockingScript(
                            sessionHash: sessionHash,
                            baseline: baseline
                        )
                )
            ]
            var inputComponentIndices: [Int] = []
            var inputOutpoints = Set<InputOutpoint>()

            for (componentIndex, component) in decodedComponents.enumerated() {
                switch component.payload {
                case let .input(inputComponent):
                    guard inputOutpoints.insert(.init(inputComponent)).inserted else {
                        throw OpalFusion.Execution.WorkflowFailure.protocolValidationFailed(
                            "Coordinator returned duplicate input outpoints"
                        )
                    }

                    inputs.append(
                        .init(
                            previousTransactionHashLittleEndian: Array(
                                inputComponent.outpointTransactionHash.reversed()
                            ),
                            previousOutputIndex: inputComponent.outpointIndex,
                            unlockingScript: [],
                            sequence: 0xFFFF_FFFF
                        )
                    )
                    inputComponentIndices.append(componentIndex)
                case let .output(outputComponent):
                    outputs.append(
                        .init(
                            amountSatoshis: outputComponent.amountSatoshis,
                            lockingScript: outputComponent.lockingScript
                        )
                    )
                case .blank:
                    break
                }
            }

            return (
                .init(
                    version: 1,
                    inputs: inputs,
                    outputs: outputs,
                    lockTime: 0
                ),
                inputComponentIndices
            )
        }

        private func makeLocalInputReferences(
            reservation: OpalFusion.Host.ParticipantReservation,
            playerCommitMaterial: OpalFusion.Execution.PlayerCommitMaterial,
            myComponentIndices: [Int],
            transactionInputComponentIndices: [Int]
        ) throws -> [OpalFusion.Execution.LocalInputReference] {
            var references: [OpalFusion.Execution.LocalInputReference] = []
            let localComponentsByComponentIndex = Dictionary(
                uniqueKeysWithValues: zip(
                    myComponentIndices,
                    playerCommitMaterial.componentsByCommitmentOrder
                ).map { ($0, $1) }
            )

            for (transactionInputIndex, componentIndex) in transactionInputComponentIndices.enumerated() {
                guard let localComponent = localComponentsByComponentIndex[componentIndex] else {
                    continue
                }
                guard case .input = localComponent.payload else {
                    continue
                }
                let reservationInputIndex = localComponent.originalSlot
                guard reservation.inputs.indices.contains(reservationInputIndex) else {
                    throw OpalFusion.Execution.WorkflowFailure.protocolValidationFailed(
                        "Local reservation input mapping was inconsistent"
                    )
                }
                references.append(
                    .init(
                        transactionInputIndex: transactionInputIndex,
                        componentIndex: componentIndex,
                        reservationInputIndex: reservationInputIndex,
                        originalSlot: localComponent.originalSlot,
                        participantInput: reservation.inputs[reservationInputIndex]
                    )
                )
            }

            return references
        }

        private func validateFinalizedTransaction(
            _ finalizedTransaction: OpalFusion.Execution.BCHTransaction,
            against template: OpalFusion.Execution.BCHTransaction,
            localInputReferences: [OpalFusion.Execution.LocalInputReference]
        ) throws {
            guard finalizedTransaction.version == template.version else {
                throw OpalFusion.Execution.BCHTransactionError.templateMismatch(
                    "Finalized transaction version did not match the unsigned template"
                )
            }
            guard finalizedTransaction.lockTime == template.lockTime else {
                throw OpalFusion.Execution.BCHTransactionError.templateMismatch(
                    "Finalized transaction locktime did not match the unsigned template"
                )
            }
            guard finalizedTransaction.inputs.count == template.inputs.count else {
                throw OpalFusion.Execution.BCHTransactionError.templateMismatch(
                    "Finalized transaction input count did not match the unsigned template"
                )
            }
            guard finalizedTransaction.outputs == template.outputs else {
                throw OpalFusion.Execution.BCHTransactionError.templateMismatch(
                    "Finalized transaction outputs did not match the unsigned template"
                )
            }

            let localInputIndices = Set(localInputReferences.map(\.transactionInputIndex))
            for (inputIndex, (finalizedInput, templateInput)) in zip(
                finalizedTransaction.inputs.indices,
                zip(finalizedTransaction.inputs, template.inputs)
            ) {
                guard finalizedInput.previousTransactionHashLittleEndian ==
                    templateInput.previousTransactionHashLittleEndian,
                      finalizedInput.previousOutputIndex == templateInput.previousOutputIndex,
                      finalizedInput.sequence == templateInput.sequence else {
                    throw OpalFusion.Execution.BCHTransactionError.templateMismatch(
                        "Finalized transaction input \(inputIndex) did not match the unsigned template"
                    )
                }

                if localInputIndices.contains(inputIndex) == false,
                   finalizedInput.unlockingScript.isEmpty == false {
                    throw OpalFusion.Execution.BCHTransactionError.templateMismatch(
                        "Finalized transaction included signatures for non-local inputs"
                    )
                }
            }
        }

        private func extractLocalSignature(
            from input: OpalFusion.Execution.BCHTransaction.Input,
            transaction: OpalFusion.Execution.BCHTransaction,
            inputReference: OpalFusion.Execution.LocalInputReference
        ) throws -> [UInt8] {
            guard let publicKey = inputReference.participantInput.publicKey else {
                throw OpalFusion.Execution.WorkflowFailure.missingParticipantInputPublicKey(
                    index: inputReference.reservationInputIndex
                )
            }
            let (signature, pushedPublicKey) = try parseP2PKHUnlockingScript(input.unlockingScript)
            guard pushedPublicKey == publicKey else {
                throw OpalFusion.Execution.BCHTransactionError.templateMismatch(
                    "Finalized transaction public key did not match the reserved participant input"
                )
            }

            let sighash = try transaction.signatureHash(
                forInputAt: inputReference.transactionInputIndex,
                lockingScript: inputReference.participantInput.lockingScriptBytes,
                amountSatoshis: inputReference.participantInput.amountSatoshis
            )
            let isValid: Bool
            do {
                isValid = try OpalCrypto.Signature.Schnorr(
                    rawRepresentation: Data(signature)
                ).verify(
                    digest: OpalCrypto.Signature.Digest(rawRepresentation: Data(sighash)),
                    publicKey: OpalCrypto.Secp256k1.PublicKey(
                        rawRepresentation: Data(publicKey)
                    )
                )
            } catch {
                throw OpalFusion.Execution.BCHTransactionError.templateMismatch(
                    "Finalized transaction signature verification failed"
                )
            }
            guard isValid else {
                throw OpalFusion.Execution.BCHTransactionError.templateMismatch(
                    "Finalized transaction included an invalid signature"
                )
            }
            return signature
        }

        private func parseP2PKHUnlockingScript(
            _ unlockingScript: [UInt8]
        ) throws -> (signature: [UInt8], publicKey: [UInt8]) {
            guard unlockingScript.isEmpty == false else {
                throw OpalFusion.Execution.BCHTransactionError.templateMismatch(
                    "Finalized transaction was missing a required local unlocking script"
                )
            }
            var cursor = 0
            let signaturePush = try parsePushData(from: unlockingScript, cursor: &cursor)
            let publicKeyPush = try parsePushData(from: unlockingScript, cursor: &cursor)
            guard cursor == unlockingScript.count else {
                throw OpalFusion.Execution.BCHTransactionError.unsupportedInput(
                    OpalFusion.Execution.ProtocolPrimitives.supportedUnlockingScriptSummary
                )
            }
            guard signaturePush.count == 65, signaturePush.last == 0x41 else {
                throw OpalFusion.Execution.BCHTransactionError.unsupportedInput(
                    OpalFusion.Execution.ProtocolPrimitives.supportedUnlockingScriptSummary
                )
            }
            guard OpalFusion.Execution.ProtocolPrimitives.isCompressedSecp256k1PublicKey(
                publicKeyPush
            ) else {
                throw OpalFusion.Execution.BCHTransactionError.unsupportedInput(
                    OpalFusion.Execution.ProtocolPrimitives.supportedUnlockingScriptSummary
                )
            }
            return (Array(signaturePush.dropLast()), publicKeyPush)
        }

        private func parsePushData(
            from script: [UInt8],
            cursor: inout Int
        ) throws -> [UInt8] {
            guard cursor < script.count else {
                throw OpalFusion.Execution.BCHTransactionError.unsupportedInput(
                    OpalFusion.Execution.ProtocolPrimitives.supportedUnlockingScriptSummary
                )
            }
            let opcode = script[cursor]
            cursor += 1
            guard opcode > 0x00, opcode < 0x4C else {
                throw OpalFusion.Execution.BCHTransactionError.unsupportedInput(
                    OpalFusion.Execution.ProtocolPrimitives.supportedUnlockingScriptSummary
                )
            }
            let pushLength = Int(opcode)
            guard cursor + pushLength <= script.count else {
                throw OpalFusion.Execution.BCHTransactionError.unsupportedInput(
                    OpalFusion.Execution.ProtocolPrimitives.supportedUnlockingScriptSummary
                )
            }
            defer { cursor += pushLength }
            return Array(script[cursor..<(cursor + pushLength)])
        }

        private func validateRelayedProof(
            _ proofBytes: [UInt8],
            sourceCommitment: OpalFusion.Commitment.InitialCommitment,
            sharedRoundMaterial: OpalFusion.Execution.SharedRoundMaterial,
            badComponentIndices: Set<UInt32>,
            feeRateSatoshisPerKb: UInt64
        ) throws -> OpalFusion.Execution.ValidatedProof {
            let parsedProof = try parseProof(bytes: proofBytes)
            let componentIndex = Int(parsedProof.componentIndex)
            guard sharedRoundMaterial.decodedComponents.indices.contains(componentIndex) else {
                throw OpalFusion.Execution.RelayedProofValidationFailure(
                    reason: "component index out of range"
                )
            }
            guard badComponentIndices.contains(parsedProof.componentIndex) == false else {
                throw OpalFusion.Execution.RelayedProofValidationFailure(
                    reason: "component in bad list"
                )
            }

            let component = sharedRoundMaterial.decodedComponents[componentIndex]
            guard parsedProof.salt.count == 32 else {
                throw OpalFusion.Execution.RelayedProofValidationFailure(
                    reason: "salt wrong length"
                )
            }
            guard OpalFusion.Execution.ProtocolPrimitives.sha256(parsedProof.salt) ==
                component.saltCommitment else {
                throw OpalFusion.Execution.RelayedProofValidationFailure(
                    reason: "salt commitment mismatch"
                )
            }
            guard OpalFusion.Execution.ProtocolPrimitives.sha256(
                parsedProof.salt + component.serializedComponent
            ) == sourceCommitment.saltedComponentHash else {
                throw OpalFusion.Execution.RelayedProofValidationFailure(
                    reason: "salted component hash mismatch"
                )
            }

            let contribution = try contributionForComponent(
                component.payload,
                feeRateSatoshisPerKb: feeRateSatoshisPerKb
            )
            let expectedCommitment: OpalCrypto.Pedersen.Commitment
            do {
                expectedCommitment = try pedersenSetup.commit(
                    amount: contribution,
                    nonce: OpalCrypto.Pedersen.Nonce(
                        rawRepresentation: Data(parsedProof.pedersenNonce)
                    )
                )
            } catch {
                throw OpalFusion.Execution.RelayedProofValidationFailure(
                    reason: "pedersen commitment verification error"
                )
            }
            guard expectedCommitment.point.uncompressedRepresentation.bytes ==
                sourceCommitment.amountCommitment else {
                throw OpalFusion.Execution.RelayedProofValidationFailure(
                    reason: "pedersen commitment mismatch"
                )
            }

            switch component.payload {
            case let .input(inputComponent):
                return .input(inputComponent)
            case .output, .blank:
                return .nonInput
            }
        }

        private func contributionForComponent(
            _ payload: OpalFusion.Commitment.ComponentPayload,
            feeRateSatoshisPerKb: UInt64
        ) throws -> Int64 {
            switch payload {
            case let .input(inputComponent):
                let fee = try checkedProofComponentFee(
                    sizeBytes: OpalFusion.Execution.ProtocolPrimitives.inputSize(
                        for: inputComponent.publicKey
                    ),
                    feeRateSatoshisPerKb: feeRateSatoshisPerKb
                )
                return Int64(inputComponent.amountSatoshis) - Int64(fee)
            case let .output(outputComponent):
                let fee = try checkedProofComponentFee(
                    sizeBytes: OpalFusion.Execution.ProtocolPrimitives.outputSize(
                        for: outputComponent.lockingScript
                    ),
                    feeRateSatoshisPerKb: feeRateSatoshisPerKb
                )
                let amount = Int64(outputComponent.amountSatoshis)
                let signedFee = Int64(fee)
                guard signedFee <= Int64.max - amount else {
                    throw OpalFusion.Execution.RelayedProofValidationFailure(
                        reason: "component fee rate too large"
                    )
                }
                return -(amount + signedFee)
            case .blank:
                return 0
            }
        }

        private func checkedComponentFee(
            sizeBytes: Int,
            feeRateSatoshisPerKb: UInt64
        ) throws -> UInt64 {
            let fee = OpalFusion.Execution.ProtocolPrimitives.componentFee(
                sizeBytes: sizeBytes,
                feeRateSatoshisPerKb: feeRateSatoshisPerKb
            )
            guard fee <= UInt64(Int64.max) else {
                throw OpalFusion.Execution.WorkflowFailure.protocolValidationFailed(
                    "Coordinator component fee rate was too large"
                )
            }
            return fee
        }

        private func checkedProofComponentFee(
            sizeBytes: Int,
            feeRateSatoshisPerKb: UInt64
        ) throws -> UInt64 {
            let fee = OpalFusion.Execution.ProtocolPrimitives.componentFee(
                sizeBytes: sizeBytes,
                feeRateSatoshisPerKb: feeRateSatoshisPerKb
            )
            guard fee <= UInt64(Int64.max) else {
                throw OpalFusion.Execution.RelayedProofValidationFailure(
                    reason: "component fee rate too large"
                )
            }
            return fee
        }

        private func decodeComponent(
            bytes: [UInt8],
            componentIndex: Int
        ) throws -> OpalFusion.Execution.DecodedComponent {
            let message = try parseComponent(bytes: bytes)
            guard message.saltCommitment.count == 32 else {
                throw OpalFusion.Execution.WorkflowFailure.protocolValidationFailed(
                    "Shared component at index \(componentIndex) salt commitment must be 32 bytes"
                )
            }

            let payload: OpalFusion.Commitment.ComponentPayload
            switch message.component {
            case let .input(input):
                guard input.prevTxid.count == 32 else {
                    throw OpalFusion.Execution.WorkflowFailure.protocolValidationFailed(
                        "Shared input component at index \(componentIndex) previous transaction hash must be 32 bytes"
                    )
                }

                guard input.amount <= OpalFusion.Execution.ProtocolPrimitives.maximumMoneySatoshis else {
                    throw OpalFusion.Execution.WorkflowFailure.protocolValidationFailed(
                        "Shared input component at index \(componentIndex) exceeds the maximum BCH money supply"
                    )
                }
                guard OpalFusion.Execution.ProtocolPrimitives.isCompressedSecp256k1PublicKey(
                    input.pubkey.bytes
                ) else {
                    throw OpalFusion.Execution.WorkflowFailure.protocolValidationFailed(
                        "Shared input component at index \(componentIndex) must provide a valid compressed public key"
                    )
                }

                payload = .input(
                    .init(
                        outpointTransactionHash: Array(input.prevTxid.reversed()),
                        outpointIndex: input.prevIndex,
                        publicKey: input.pubkey.bytes,
                        amountSatoshis: input.amount
                    )
                )
            case let .output(output):
                guard output.amount <= OpalFusion.Execution.ProtocolPrimitives.maximumMoneySatoshis else {
                    throw OpalFusion.Execution.WorkflowFailure.protocolValidationFailed(
                        "Shared output component at index \(componentIndex) exceeds the maximum BCH money supply"
                    )
                }

                let minimumAmount = OpalFusion.Execution.ProtocolPrimitives.minimumOutputAmount(
                    for: output.scriptpubkey.bytes,
                    baseline: baseline
                )
                guard output.amount >= minimumAmount else {
                    throw OpalFusion.Execution.WorkflowFailure.protocolValidationFailed(
                        "Shared output component at index \(componentIndex) is below the minimum allowed amount"
                    )
                }

                payload = .output(
                    .init(
                        lockingScript: output.scriptpubkey.bytes,
                        amountSatoshis: output.amount
                    )
                )
            case .blank(_):
                payload = .blank(.init())
            case .none:
                throw OpalFusion.Execution.WorkflowFailure.protocolValidationFailed(
                    "Shared component was missing its payload"
                )
            }
            return .init(
                serializedComponent: bytes,
                saltCommitment: message.saltCommitment.bytes,
                payload: payload
            )
        }

        private func parseComponent(
            bytes: [UInt8]
        ) throws -> FusionComponent {
            do {
                return try FusionComponent(serializedBytes: Data(bytes))
            } catch let error as OpalFusion.Execution.WorkflowFailure {
                throw error
            } catch {
                throw OpalFusion.Execution.WorkflowFailure.protocolValidationFailed(
                    "Component decode failed"
                )
            }
        }

        private func parseInitialCommitment(
            bytes: [UInt8]
        ) throws -> OpalFusion.Commitment.InitialCommitment {
            do {
                let message = try FusionInitialCommitment(serializedBytes: Data(bytes))
                return .init(
                    saltedComponentHash: message.saltedComponentHash.bytes,
                    amountCommitment: message.amountCommitment.bytes,
                    communicationPublicKey: message.communicationKey.bytes
                )
            } catch let error as OpalFusion.Execution.WorkflowFailure {
                throw error
            } catch {
                throw OpalFusion.Execution.WorkflowFailure.protocolValidationFailed(
                    "Initial commitment decode failed"
                )
            }
        }

        private func parseProof(
            bytes: [UInt8]
        ) throws -> OpalFusion.Blame.Proof {
            do {
                let message = try FusionProof(serializedBytes: Data(bytes))
                return .init(
                    componentIndex: message.componentIdx,
                    salt: message.salt.bytes,
                    pedersenNonce: message.pedersenNonce.bytes
                )
            } catch let error as OpalFusion.Execution.RelayedProofValidationFailure {
                throw error
            } catch {
                throw OpalFusion.Execution.RelayedProofValidationFailure(
                    reason: "proof decode failed"
                )
            }
        }

        private func serializeComponent(
            payload: OpalFusion.Commitment.ComponentPayload,
            saltCommitment: [UInt8]
        ) throws -> [UInt8] {
            var message = FusionComponent()
            message.saltCommitment = Data(saltCommitment)
            switch payload {
            case let .input(inputComponent):
                var input = FusionInputComponent()
                input.prevTxid = Data(inputComponent.outpointTransactionHash.reversed())
                input.prevIndex = inputComponent.outpointIndex
                input.pubkey = Data(inputComponent.publicKey)
                input.amount = inputComponent.amountSatoshis
                message.component = .input(input)
            case let .output(outputComponent):
                var output = FusionOutputComponent()
                output.scriptpubkey = Data(outputComponent.lockingScript)
                output.amount = outputComponent.amountSatoshis
                message.component = .output(output)
            case .blank:
                message.component = .blank(.init())
            }
            return try Array(message.serializedData())
        }

        private func serializeInitialCommitment(
            _ commitment: OpalFusion.Commitment.InitialCommitment
        ) throws -> [UInt8] {
            var message = FusionInitialCommitment()
            message.saltedComponentHash = Data(commitment.saltedComponentHash)
            message.amountCommitment = Data(commitment.amountCommitment)
            message.communicationKey = Data(commitment.communicationPublicKey)
            return try Array(message.serializedData())
        }

        private func serializeProof(
            componentIndex: UInt32,
            salt: [UInt8],
            pedersenNonce: [UInt8]
        ) throws -> [UInt8] {
            var message = FusionProof()
            message.componentIdx = componentIndex
            message.salt = Data(salt)
            message.pedersenNonce = Data(pedersenNonce)
            return try Array(message.serializedData())
        }

        private func mapTransactionError(
            _ error: OpalFusion.Execution.BCHTransactionError
        ) -> OpalFusion.Execution.WorkflowFailure {
            switch error {
            case let .malformed(summary):
                return .protocolValidationFailed(summary)
            case let .templateMismatch(summary):
                return .invalidTransactionTemplate(summary)
            case let .unsupportedInput(summary):
                return .unsupportedExecution(summary)
            }
        }

        private static func hasDuplicateByteArrays(_ arrays: [[UInt8]]) -> Bool {
            var seen = Set<Data>()
            for array in arrays {
                if seen.insert(Data(array)).inserted == false {
                    return true
                }
            }
            return false
        }

        private struct InputOutpoint: Hashable {
            let transactionHash: [UInt8]
            let index: UInt32

            init(_ inputComponent: OpalFusion.Commitment.InputComponent) {
                self.transactionHash = inputComponent.outpointTransactionHash
                self.index = inputComponent.outpointIndex
            }
        }
    }
}

private extension Data {
    var bytes: [UInt8] { Array(self) }
}

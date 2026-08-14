// OpalFusion+Mosaic+OpalMainnetAlpha+LocalContributionMaterial.swift

import Foundation
import OpalCrypto

extension OpalFusion.Mosaic.OpalMainnetAlpha {
    struct LocalContributionMaterial: Sendable {
        typealias AttemptIdentifier = OpalFusion.Mosaic.LocalAttempt.AttemptIdentifier
        typealias GenerationIdentifier = OpalFusion.Mosaic.LocalAttempt.GenerationIdentifier
        typealias MaterialIdentifier = OpalFusion.Mosaic.LocalAttempt.MaterialIdentifier
        typealias ControlIdentity = OpalFusion.Mosaic.Attempt.ControlIdentity

        enum BuildError: Error, Sendable, Equatable {
            case conductorCannotContribute
            case contributorNotInRoster
            case leaseComponentLimitExceeded(actual: Int)
            case slotSecretCountMismatch(actual: Int)
            case duplicateInputOutpoint(index: Int)
            case inputPublicKeyMissing(index: Int)
            case invalidInputPublicKey(index: Int)
            case invalidInputP2PKHLockingScript(index: Int)
            case invalidInput(index: Int)
            case invalidOutput(index: Int)
            case duplicateSalt(slot: Int)
            case duplicatePedersenNonce(slot: Int)
            case duplicateCommunicationKey(slot: Int)
            case duplicateComponentEnvelopeKey(slot: Int)
            case duplicateBCHSignatureEnvelopeKey(slot: Int)
            case duplicateComponentAuthorizationNonce(slot: Int)
            case duplicateBCHSignatureAuthorizationNonce(slot: Int)
            case duplicateRecipientEventIdentity(slot: Int)
            case anonymousIdentityReusesControlIdentity(slot: Int)
            case contributionBalanceMismatch(expected: UInt64, actual: Int64)
            case cryptographicMaterialInvalid(slot: Int)
            case groupedCommitmentInvalid
            case playerCommitInvalid
        }

        enum ValidationError: Error, Sendable, Equatable {
            case bindingMismatch
            case componentOpeningMismatch(slot: Int)
            case commitmentMissing(slot: Int)
            case componentMissing(slot: Int)
        }

        let attemptIdentifier: AttemptIdentifier
        let generationIdentifier: GenerationIdentifier
        let materialIdentifier: MaterialIdentifier
        let contributor: ControlIdentity
        let manifest: RoundManifest
        let reservationLease: OpalFusion.Host.MosaicReservationLease
        let slots: [ComponentSlotMaterial]
        let playerCommit: PlayerCommit

        private init(
            attemptIdentifier: AttemptIdentifier,
            generationIdentifier: GenerationIdentifier,
            materialIdentifier: MaterialIdentifier,
            contributor: ControlIdentity,
            manifest: RoundManifest,
            reservationLease: OpalFusion.Host.MosaicReservationLease,
            slots: [ComponentSlotMaterial],
            playerCommit: PlayerCommit
        ) {
            self.attemptIdentifier = attemptIdentifier
            self.generationIdentifier = generationIdentifier
            self.materialIdentifier = materialIdentifier
            self.contributor = contributor
            self.manifest = manifest
            self.reservationLease = reservationLease
            self.slots = slots
            self.playerCommit = playerCommit
        }

        static func build(
            attemptIdentifier: AttemptIdentifier,
            generationIdentifier: GenerationIdentifier,
            materialIdentifier: MaterialIdentifier,
            contributor: ControlIdentity,
            manifest: RoundManifest,
            reservationLease: OpalFusion.Host.MosaicReservationLease,
            slotSecrets: [ComponentSlotSecrets]
        ) throws(BuildError) -> Self {
            guard contributor != manifest.core.roster.conductor else {
                throw .conductorCannotContribute
            }
            guard manifest.core.roster.contributors.contains(contributor) else {
                throw .contributorNotInRoster
            }
            let reservation = reservationLease.participantReservation
            let nonblankCount = reservation.inputs.count + reservation.outputs.count
            guard nonblankCount <= componentCountPerContributor else {
                throw .leaseComponentLimitExceeded(actual: nonblankCount)
            }
            guard slotSecrets.count == componentCountPerContributor else {
                throw .slotSecretCountMismatch(actual: slotSecrets.count)
            }
            try validateUniqueSlotSecrets(slotSecrets)
            try validateAnonymousIdentities(
                slotSecrets,
                against: manifest.core.roster
            )

            var outpoints: Set<Outpoint> = []
            var payloads: [OpalFusion.Mosaic.OpalV0.ComponentPayload] = []
            payloads.reserveCapacity(componentCountPerContributor)
            for (index, input) in reservation.inputs.enumerated() {
                guard outpoints.insert(.init(input)).inserted else {
                    throw .duplicateInputOutpoint(index: index)
                }
                guard let publicKey = input.publicKey else {
                    throw .inputPublicKeyMissing(index: index)
                }
                guard OpalFusion.Execution.ProtocolPrimitives
                    .isCompressedSecp256k1PublicKey(publicKey) else {
                    throw .invalidInputPublicKey(index: index)
                }
                guard OpalFusion.Execution.ProtocolPrimitives
                    .isStandardP2PKHLockingScript(
                        input.lockingScriptBytes,
                        publicKey: publicKey
                    ) else {
                    throw .invalidInputP2PKHLockingScript(index: index)
                }
                do {
                    payloads.append(
                        .input(
                            try .init(
                                previousTransactionHash:
                                    input.outpointTransactionHashBytes,
                                outputIndex: input.outpointIndex,
                                amountSatoshis: input.amountSatoshis
                            )
                        )
                    )
                } catch {
                    throw .invalidInput(index: index)
                }
            }
            for (index, output) in reservation.outputs.enumerated() {
                do {
                    payloads.append(
                        .output(
                            try .init(
                                lockingScript: output.lockingScriptBytes,
                                amountSatoshis: output.amountSatoshis
                            )
                        )
                    )
                } catch {
                    throw .invalidOutput(index: index)
                }
            }
            payloads.append(
                contentsOf: repeatElement(
                    OpalFusion.Mosaic.OpalV0.ComponentPayload.blank,
                    count: componentCountPerContributor - nonblankCount
                )
            )

            let setup: OpalCrypto.Pedersen.Setup
            do {
                setup = try .init()
            } catch {
                throw .cryptographicMaterialInvalid(slot: 0)
            }
            var pedersenCommitments: [OpalCrypto.Pedersen.Commitment] = []
            pedersenCommitments.reserveCapacity(componentCountPerContributor)
            var slots: [ComponentSlotMaterial] = []
            slots.reserveCapacity(componentCountPerContributor)
            var contributionTotal: Int64 = 0

            for slot in 0 ..< componentCountPerContributor {
                let payload = payloads[slot]
                let secrets = slotSecrets[slot]
                let contribution = ContributionFeePolicy.contributionSatoshis(
                    for: payload
                )
                contributionTotal += contribution

                do {
                    let saltCommitment = try ComponentHashing.saltCommitment(
                        roundIdentifier: manifest.core.roundIdentifier,
                        salt: secrets.salt
                    )
                    let component = try OpalFusion.Mosaic.OpalV0.Component(
                        saltCommitment: saltCommitment,
                        payload: payload
                    )
                    let pedersenCommitment = try setup.commit(
                        amount: contribution,
                        nonce: secrets.pedersenNonce
                    )
                    let communicationPublicKey = secrets.communicationPrivateKey
                        .makeSigningKey().publicKey
                    let commitment = try OpalFusion.Mosaic.OpalV0
                        .ComponentCommitment(
                            saltedComponentDigest: try ComponentHashing
                                .saltedComponentDigest(
                                    roundIdentifier: manifest.core.roundIdentifier,
                                    salt: secrets.salt,
                                    payload: payload
                                ),
                            amountCommitment: [UInt8](
                                pedersenCommitment.point.uncompressedRepresentation
                            ),
                            communicationPublicKey: [UInt8](
                                communicationPublicKey.compressedRepresentation
                            )
                        )
                    let componentInput = try AuthorizationTokenInput(
                        roundIdentifier: manifest.core.roundIdentifier,
                        keyIdentifier: [UInt8](
                            manifest.core.componentAuthorizationVerificationKey
                                .keyIdentifier
                        ),
                        purpose: .component,
                        nonce: secrets.componentAuthorizationNonce,
                        binding: try AuthorizationTokenInput.componentBinding(
                            for: component
                        )
                    )
                    let bchSignatureInput = try AuthorizationTokenInput(
                        roundIdentifier: manifest.core.roundIdentifier,
                        keyIdentifier: [UInt8](
                            manifest.core.bchSignatureAuthorizationVerificationKey
                                .keyIdentifier
                        ),
                        purpose: .bchSignature,
                        nonce: secrets.bchSignatureAuthorizationNonce,
                        binding: componentInput.spentIdentifier
                    )
                    let componentRequest = try AuthorizationRequest(
                        input: componentInput,
                        using: manifest.core.componentAuthorizationVerificationKey
                    )
                    let bchSignatureRequest = try AuthorizationRequest(
                        input: bchSignatureInput,
                        using: manifest.core.bchSignatureAuthorizationVerificationKey
                    )
                    pedersenCommitments.append(pedersenCommitment)
                    slots.append(
                        .init(
                            slot: slot,
                            component: component,
                            salt: secrets.salt,
                            contributionSatoshis: contribution,
                            pedersenNonce: secrets.pedersenNonce,
                            commitment: commitment,
                            communicationPrivateKey:
                                secrets.communicationPrivateKey,
                            componentEnvelopePrivateKey:
                                secrets.componentEnvelopePrivateKey,
                            bchSignatureEnvelopePrivateKey:
                                secrets.bchSignatureEnvelopePrivateKey,
                            recipientEventIdentity:
                                secrets.recipientEventIdentity,
                            componentAuthorizationRequest: componentRequest,
                            bchSignatureAuthorizationRequest:
                                bchSignatureRequest
                        )
                    )
                } catch {
                    throw .cryptographicMaterialInvalid(slot: slot)
                }
            }

            let requiredExcess: UInt64
            do {
                requiredExcess = try ContributionFeePolicy
                    .requiredExcessFeeSatoshis(
                        for: contributor,
                        in: manifest.core.roster
                    )
            } catch {
                throw .contributorNotInRoster
            }
            guard contributionTotal == Int64(requiredExcess) else {
                throw .contributionBalanceMismatch(
                    expected: requiredExcess,
                    actual: contributionTotal
                )
            }

            let groupedCommitment: OpalFusion.Mosaic.OpalV0
                .GroupedCommitmentPayload
            do {
                let combined = try setup.combine(pedersenCommitments)
                groupedCommitment = try .init(
                    profile: .opalMainnetAlpha,
                    commitments: slots.map(\.commitment),
                    excessFeeSatoshis: requiredExcess,
                    pedersenTotalNonce: [UInt8](combined.nonce.rawRepresentation)
                )
            } catch {
                throw .groupedCommitmentInvalid
            }

            let playerCommit: PlayerCommit
            do {
                playerCommit = try .init(
                    roundIdentifier: manifest.core.roundIdentifier,
                    contributor: contributor,
                    groupedCommitment: groupedCommitment,
                    componentAuthorizationRequests: try slots.map {
                        try .init(
                            slot: $0.slot,
                            blindedMessage:
                                $0.componentAuthorizationRequest.blindedMessage
                        )
                    },
                    bchSignatureAuthorizationRequests: try slots.map {
                        try .init(
                            slot: $0.slot,
                            blindedMessage:
                                $0.bchSignatureAuthorizationRequest.blindedMessage
                        )
                    }
                )
            } catch {
                throw .playerCommitInvalid
            }

            return .init(
                attemptIdentifier: attemptIdentifier,
                generationIdentifier: generationIdentifier,
                materialIdentifier: materialIdentifier,
                contributor: contributor,
                manifest: manifest,
                reservationLease: reservationLease,
                slots: slots,
                playerCommit: playerCommit
            )
        }

        private struct Outpoint: Hashable {
            let hash: [UInt8]
            let index: UInt32

            init(_ input: OpalFusion.Host.ParticipantInput) {
                hash = input.outpointTransactionHashBytes
                index = input.outpointIndex
            }
        }

        private static func validateUniqueSlotSecrets(
            _ secrets: [ComponentSlotSecrets]
        ) throws(BuildError) {
            var oneTimeMaterial: Set<Data> = []
            for (slot, value) in secrets.enumerated() {
                guard oneTimeMaterial.insert(Data(value.salt)).inserted else {
                    throw .duplicateSalt(slot: slot)
                }
                guard oneTimeMaterial.insert(
                    value.pedersenNonce.rawRepresentation
                ).inserted else {
                    throw .duplicatePedersenNonce(slot: slot)
                }
                guard oneTimeMaterial.insert(
                    value.communicationPrivateKey.rawRepresentation
                ).inserted else {
                    throw .duplicateCommunicationKey(slot: slot)
                }
                let communicationIdentity = value.communicationPrivateKey
                    .makeSigningKey().publicKey.compressedRepresentation.dropFirst()
                guard oneTimeMaterial.insert(
                    Data(communicationIdentity)
                ).inserted else {
                    throw .duplicateCommunicationKey(slot: slot)
                }
                guard oneTimeMaterial.insert(
                    value.componentEnvelopePrivateKey.rawRepresentation
                ).inserted else {
                    throw .duplicateComponentEnvelopeKey(slot: slot)
                }
                let componentEnvelopeIdentity = value
                    .componentEnvelopePrivateKey.makeSigningKey().publicKey
                    .compressedRepresentation.dropFirst()
                guard oneTimeMaterial.insert(
                    Data(componentEnvelopeIdentity)
                ).inserted else {
                    throw .duplicateComponentEnvelopeKey(slot: slot)
                }
                guard oneTimeMaterial.insert(
                    value.bchSignatureEnvelopePrivateKey.rawRepresentation
                ).inserted else {
                    throw .duplicateBCHSignatureEnvelopeKey(slot: slot)
                }
                let bchSignatureEnvelopeIdentity = value
                    .bchSignatureEnvelopePrivateKey.makeSigningKey().publicKey
                    .compressedRepresentation.dropFirst()
                guard oneTimeMaterial.insert(
                    Data(bchSignatureEnvelopeIdentity)
                ).inserted else {
                    throw .duplicateBCHSignatureEnvelopeKey(slot: slot)
                }
                guard oneTimeMaterial.insert(
                    Data(value.componentAuthorizationNonce)
                ).inserted else {
                    throw .duplicateComponentAuthorizationNonce(slot: slot)
                }
                guard oneTimeMaterial.insert(
                    Data(value.bchSignatureAuthorizationNonce)
                ).inserted else {
                    throw .duplicateBCHSignatureAuthorizationNonce(slot: slot)
                }
                guard oneTimeMaterial.insert(
                    Data(value.recipientEventIdentity)
                ).inserted else {
                    throw .duplicateRecipientEventIdentity(slot: slot)
                }
            }
        }

        private static func validateAnonymousIdentities(
            _ secrets: [ComponentSlotSecrets],
            against roster: OpalFusion.Mosaic.Attempt.Roster
        ) throws(BuildError) {
            let controlIdentities = Set(
                roster.controlIdentities.map { Data($0.validatedBytes) }
            )
            for (slot, value) in secrets.enumerated() {
                let identities = [
                    Data(
                        value.communicationPrivateKey.makeSigningKey()
                            .publicKey.compressedRepresentation.dropFirst()
                    ),
                    Data(
                        value.componentEnvelopePrivateKey.makeSigningKey()
                            .publicKey.compressedRepresentation.dropFirst()
                    ),
                    Data(
                        value.bchSignatureEnvelopePrivateKey.makeSigningKey()
                            .publicKey.compressedRepresentation.dropFirst()
                    ),
                    Data(value.recipientEventIdentity),
                ]
                guard identities.allSatisfy({
                    !controlIdentities.contains($0)
                }) else {
                    throw .anonymousIdentityReusesControlIdentity(slot: slot)
                }
            }
        }

        func validateCommitmentInclusion(
            in commitmentSet: OpalFusion.Mosaic.OpalV0.CommitmentSet
        ) throws(ValidationError) {
            for slot in slots {
                guard commitmentSet.commitments.filter({
                    $0 == slot.commitment
                }).count == 1 else {
                    throw .commitmentMissing(slot: slot.slot)
                }
            }
        }
    }
}

extension OpalFusion.Mosaic.OpalMainnetAlpha.LocalContributionMaterial:
    OpalFusion.Mosaic.OpalMainnetAlpha.RuntimeSession
        .ReservationPublicationValidating
{
    func validateReservationPublication(
        _ request: OpalFusion.Mosaic.OpalMainnetAlpha.RuntimeSession
            .ReservationPublicationRequest
    ) throws {
        do {
            try OpalFusion.Mosaic.OpalMainnetAlpha
                .ReservationMaterialLeaseValidator.validate(
                    actualLease: request.reservationLease,
                    materialLease: reservationLease
                )
        } catch {
            throw ValidationError.bindingMismatch
        }
        guard request.attemptIdentifier == attemptIdentifier,
              request.generationIdentifier == generationIdentifier,
              request.materialIdentifier == materialIdentifier,
              request.contributor == contributor,
              request.manifest == manifest,
              request.playerCommit == playerCommit else {
            throw ValidationError.bindingMismatch
        }
    }
}

extension OpalFusion.Mosaic.OpalMainnetAlpha.LocalContributionMaterial:
    OpalFusion.Mosaic.LocalAttempt.TranscriptInclusionValidating
{
    func validateCompleteInclusion(
        attemptIdentifier: OpalFusion.Mosaic.LocalAttempt.AttemptIdentifier,
        generationIdentifier: OpalFusion.Mosaic.LocalAttempt.GenerationIdentifier,
        contributor: OpalFusion.Mosaic.Attempt.ControlIdentity,
        materialIdentifier: OpalFusion.Mosaic.LocalAttempt.MaterialIdentifier,
        transcript: OpalFusion.Mosaic.OpalV0.UnsignedTransactionTranscript
    ) throws {
        guard attemptIdentifier == self.attemptIdentifier,
              generationIdentifier == self.generationIdentifier,
              materialIdentifier == self.materialIdentifier,
              contributor == self.contributor,
              transcript.profile == .opalMainnetAlpha,
              transcript.manifest == manifest.binding else {
            throw ValidationError.bindingMismatch
        }
        try validateCommitmentInclusion(in: transcript.commitmentSet)
        let setup = try OpalCrypto.Pedersen.Setup()
        for slot in slots {
            let expectedSaltCommitment = try OpalFusion.Mosaic.OpalMainnetAlpha
                .ComponentHashing.saltCommitment(
                roundIdentifier: manifest.core.roundIdentifier,
                salt: slot.salt
            )
            let expectedDigest = try OpalFusion.Mosaic.OpalMainnetAlpha
                .ComponentHashing.saltedComponentDigest(
                roundIdentifier: manifest.core.roundIdentifier,
                salt: slot.salt,
                payload: slot.component.payload
            )
            let expectedCommunicationKey = slot.communicationPrivateKey
                .makeSigningKey().publicKey.compressedRepresentation
            let point = try OpalCrypto.Pedersen.CommitmentPoint(
                rawRepresentation: Data(slot.commitment.amountCommitment)
            )
            guard slot.component.saltCommitment == expectedSaltCommitment,
                  slot.commitment.saltedComponentDigest == expectedDigest,
                  Data(slot.commitment.communicationPublicKey)
                    == expectedCommunicationKey,
                  try setup.verify(
                      commitment: point,
                      amount: slot.contributionSatoshis,
                      nonce: slot.pedersenNonce
                  ) else {
                throw ValidationError.componentOpeningMismatch(slot: slot.slot)
            }
            guard transcript.componentSet.components.filter({
                $0 == slot.component
            }).count == 1 else {
                throw ValidationError.componentMissing(slot: slot.slot)
            }
        }
    }
}

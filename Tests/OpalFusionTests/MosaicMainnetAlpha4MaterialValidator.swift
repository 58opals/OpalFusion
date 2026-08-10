// MosaicMainnetAlpha4MaterialValidator.swift

import Foundation
import OpalCrypto
import Testing
@testable import OpalFusion

@Suite("Mosaic mainnet-alpha.4 local contribution material")
struct MosaicMainnetAlpha4MaterialValidator {
    typealias Alpha = OpalFusion.Mosaic.OpalMainnetAlpha
    typealias Attempt = OpalFusion.Mosaic.Attempt
    typealias LocalAttempt = OpalFusion.Mosaic.LocalAttempt
    typealias OpalV0 = OpalFusion.Mosaic.OpalV0

    private struct PreparedMaterial {
        let election: MosaicRoleElectionFixtures.Election
        let manifest: Alpha.RoundManifest
        let material: Alpha.LocalContributionMaterial
        let secrets: [Alpha.ComponentSlotSecrets]
    }

    @Test("Build exactly 23 purpose-separated, opening-valid slots")
    func buildCompleteLocalMaterial() throws {
        let prepared = try makePreparedMaterial()
        let material = prepared.material

        #expect(material.slots.count == Alpha.componentCountPerContributor)
        #expect(material.playerCommit.componentAuthorizationRequests.count == 23)
        #expect(material.playerCommit.bchSignatureAuthorizationRequests.count == 23)
        #expect(material.slots.filter { $0.component.payload == .blank }.count == 21)
        #expect(
            material.slots.reduce(Int64(0)) {
                $0 + $1.contributionSatoshis
            } == Int64(material.playerCommit.groupedCommitment.excessFeeSatoshis)
        )

        let setup = try OpalCrypto.Pedersen.Setup()
        for slot in material.slots {
            let componentInput = slot.componentAuthorizationRequest.input
            let signatureInput = slot.bchSignatureAuthorizationRequest.input
            #expect(componentInput.purpose == .component)
            #expect(signatureInput.purpose == .bchSignature)
            #expect(
                componentInput.binding
                    == (try Alpha.AuthorizationTokenInput.componentBinding(
                        for: slot.component
                    ))
            )
            #expect(signatureInput.binding == componentInput.spentIdentifier)
            #expect(componentInput.nonce != signatureInput.nonce)
            #expect(
                try setup.verify(
                    commitment: .init(
                        rawRepresentation: Data(
                            slot.commitment.amountCommitment
                        )
                    ),
                    amount: slot.contributionSatoshis,
                    nonce: slot.pedersenNonce
                )
            )
        }

        let first = try #require(material.slots.first)
        #expect(
            MosaicOpalV0WireContractValidator.hexadecimal(
                first.component.saltCommitment
            ) == "1d3e77804ca7ec2cc020913ed3ae0f720bc919a3a0ad718c8fc8603709eee0a5"
        )
        #expect(
            MosaicOpalV0WireContractValidator.hexadecimal(
                first.commitment.saltedComponentDigest
            ) == "7e590f182bf52fbb58919b469272a156247ddeecca9debf92a89a1ade99ac19e"
        )
    }

    @Test("Validate exact local openings and inclusion in a complete transcript")
    func validateCompleteLocalInclusion() throws {
        let election = try MosaicMainnetAlphaFixtures.makeElection()
        let manifest = try MosaicMainnetAlphaFixtures.makeManifest(
            election: election,
            verificationKey: MosaicMainnetAlphaFixtures.rsaVerificationKey()
        )
        let contributors = manifest.core.orderedContributors
        let materials = try contributors.enumerated().map { index, contributor in
            try makeMaterial(
                election: election,
                manifest: manifest,
                contributor: contributor,
                contributorIndex: index
            ).material
        }
        let commitmentSet = try OpalV0.CommitmentSet(
            profile: .opalMainnetAlpha,
            commitments: materials.flatMap { $0.slots.map(\.commitment) }
        )
        let componentSet = try OpalV0.ComponentSet(
            profile: .opalMainnetAlpha,
            components: materials.flatMap { $0.slots.map(\.component) }
        )
        let commitmentValidation = try Attempt.CommitmentSetValidation(
            profile: .opalMainnetAlpha,
            roster: manifest.core.roster,
            commitmentSet: commitmentSet
        )
        let transcript = try OpalV0.UnsignedTransactionTranscript(
            profile: .opalMainnetAlpha,
            roster: manifest.core.roster,
            manifest: manifest.binding,
            commitmentSet: commitmentValidation,
            componentSet: componentSet
        )
        let local = materials[0]
        let validation = try LocalAttempt.TranscriptInclusionValidation(
            attemptIdentifier: local.attemptIdentifier,
            generationIdentifier: local.generationIdentifier,
            contributor: local.contributor,
            materialIdentifier: local.materialIdentifier,
            transcript: transcript,
            using: local
        )
        #expect(validation.transcript == transcript)

        var substitutedComponents = componentSet.components
        let localComponent = try #require(local.slots.first?.component)
        let localComponentIndex = try #require(
            substitutedComponents.firstIndex(of: localComponent)
        )
        substitutedComponents[localComponentIndex] = try .init(
            saltCommitment: MosaicUnsignedTransactionTranscriptFixtures
                .indexedDigest(50_000),
            payload: localComponent.payload
        )
        let substitutedSet = try OpalV0.ComponentSet(
            profile: .opalMainnetAlpha,
            components: substitutedComponents
        )
        let substitutedTranscript = try OpalV0.UnsignedTransactionTranscript(
            profile: .opalMainnetAlpha,
            roster: manifest.core.roster,
            manifest: manifest.binding,
            commitmentSet: commitmentValidation,
            componentSet: substitutedSet
        )
        #expect(throws: LocalAttempt.TranscriptInclusionValidation.ValidationError
            .inclusionRejected) {
            _ = try LocalAttempt.TranscriptInclusionValidation(
                attemptIdentifier: local.attemptIdentifier,
                generationIdentifier: local.generationIdentifier,
                contributor: local.contributor,
                materialIdentifier: local.materialIdentifier,
                transcript: substitutedTranscript,
                using: local
            )
        }
    }

    @Test("Reject reused attempt secrets before blind-request construction")
    func rejectSecretReuse() throws {
        let prepared = try makePreparedMaterial()

        var duplicateSalt = prepared.secrets
        duplicateSalt[1] = try replacing(
            duplicateSalt[1],
            salt: duplicateSalt[0].salt
        )
        #expect(throws: Alpha.LocalContributionMaterial.BuildError
            .duplicateSalt(slot: 1)) {
            _ = try rebuild(prepared, secrets: duplicateSalt)
        }

        var duplicatePedersen = prepared.secrets
        duplicatePedersen[1] = try replacing(
            duplicatePedersen[1],
            pedersenNonce: duplicatePedersen[0].pedersenNonce
        )
        #expect(throws: Alpha.LocalContributionMaterial.BuildError
            .duplicatePedersenNonce(slot: 1)) {
            _ = try rebuild(prepared, secrets: duplicatePedersen)
        }

        var duplicateCommunicationKey = prepared.secrets
        duplicateCommunicationKey[1] = try replacing(
            duplicateCommunicationKey[1],
            communicationPrivateKey:
                duplicateCommunicationKey[0].communicationPrivateKey
        )
        #expect(throws: Alpha.LocalContributionMaterial.BuildError
            .duplicateCommunicationKey(slot: 1)) {
            _ = try rebuild(prepared, secrets: duplicateCommunicationKey)
        }

        var oppositeParityCommunicationKey = prepared.secrets
        oppositeParityCommunicationKey[1] = try replacing(
            oppositeParityCommunicationKey[1],
            communicationPrivateKey: .init(
                rawRepresentation: Data(
                    MosaicOpalV0WireContractValidator.bytes(
                        hexadecimal:
                            "fffffffffffffffffffffffffffffffebaaedce6af48a03bbfd25e8cd036410e"
                    )
                )
            )
        )
        #expect(throws: Alpha.LocalContributionMaterial.BuildError
            .duplicateCommunicationKey(slot: 1)) {
            _ = try rebuild(
                prepared,
                secrets: oppositeParityCommunicationKey
            )
        }

        var crossPurposeNonce = prepared.secrets
        crossPurposeNonce[1] = try replacing(
            crossPurposeNonce[1],
            componentAuthorizationNonce:
                crossPurposeNonce[0].bchSignatureAuthorizationNonce
        )
        #expect(throws: Alpha.LocalContributionMaterial.BuildError
            .duplicateComponentAuthorizationNonce(slot: 1)) {
            _ = try rebuild(prepared, secrets: crossPurposeNonce)
        }

        var crossKindNonce = prepared.secrets
        crossKindNonce[1] = try replacing(
            crossKindNonce[1],
            componentAuthorizationNonce: crossKindNonce[0].salt
        )
        #expect(throws: Alpha.LocalContributionMaterial.BuildError
            .duplicateComponentAuthorizationNonce(slot: 1)) {
            _ = try rebuild(prepared, secrets: crossKindNonce)
        }

        var duplicateBCHSignatureNonce = prepared.secrets
        duplicateBCHSignatureNonce[1] = try replacing(
            duplicateBCHSignatureNonce[1],
            bchSignatureAuthorizationNonce:
                duplicateBCHSignatureNonce[0]
                    .bchSignatureAuthorizationNonce
        )
        #expect(throws: Alpha.LocalContributionMaterial.BuildError
            .duplicateBCHSignatureAuthorizationNonce(slot: 1)) {
            _ = try rebuild(
                prepared,
                secrets: duplicateBCHSignatureNonce
            )
        }

        var duplicateMailbox = prepared.secrets
        duplicateMailbox[1] = try replacing(
            duplicateMailbox[1],
            recipientEventIdentity: duplicateMailbox[0].recipientEventIdentity
        )
        #expect(throws: Alpha.LocalContributionMaterial.BuildError
            .duplicateRecipientEventIdentity(slot: 1)) {
            _ = try rebuild(prepared, secrets: duplicateMailbox)
        }

        var senderMailboxCollision = prepared.secrets
        senderMailboxCollision[1] = try replacing(
            senderMailboxCollision[1],
            recipientEventIdentity: Array(
                senderMailboxCollision[0].communicationPrivateKey
                    .makeSigningKey().publicKey.compressedRepresentation
                    .dropFirst()
            )
        )
        #expect(throws: Alpha.LocalContributionMaterial.BuildError
            .duplicateRecipientEventIdentity(slot: 1)) {
            _ = try rebuild(prepared, secrets: senderMailboxCollision)
        }
    }

    @Test("Reject lease inputs outside the frozen compressed-key P2PKH shape")
    func rejectInvalidLeaseInputs() throws {
        let prepared = try makePreparedMaterial()
        let input = try #require(
            prepared.material.reservationLease.participantReservation.inputs.first
        )
        let output = try #require(
            prepared.material.reservationLease.participantReservation.outputs.first
        )

        #expect(throws: Alpha.LocalContributionMaterial.BuildError
            .inputPublicKeyMissing(index: 0)) {
            _ = try rebuild(
                prepared,
                lease: try lease(
                    input: replacing(input, publicKey: .some(nil)),
                    output: output
                )
            )
        }
        #expect(throws: Alpha.LocalContributionMaterial.BuildError
            .invalidInputPublicKey(index: 0)) {
            _ = try rebuild(
                prepared,
                lease: try lease(
                    input: replacing(
                        input,
                        publicKey: .some(
                            [0x04] + [UInt8](repeating: 0x02, count: 32)
                        )
                    ),
                    output: output
                )
            )
        }
        #expect(throws: Alpha.LocalContributionMaterial.BuildError
            .invalidInputP2PKHLockingScript(index: 0)) {
            _ = try rebuild(
                prepared,
                lease: try lease(
                    input: replacing(
                        input,
                        lockingScript: MosaicUnsignedTransactionTranscriptFixtures
                            .p2pkhLockingScript(fill: 0xAA)
                    ),
                    output: output
                )
            )
        }
    }

    @Test("Enforce the exact 23-slot construction boundary without truncation")
    func enforceComponentCountAndBalance() throws {
        let prepared = try makePreparedMaterial()
        #expect(throws: Alpha.LocalContributionMaterial.BuildError
            .slotSecretCountMismatch(actual: 22)) {
            _ = try rebuild(
                prepared,
                secrets: Array(prepared.secrets.dropLast())
            )
        }

        let input = try #require(
            prepared.material.reservationLease.participantReservation.inputs.first
        )
        let output = try #require(
            prepared.material.reservationLease.participantReservation.outputs.first
        )
        let outputCount = Alpha.componentCountPerContributor - 1
        let requiredShare = try Alpha.ContributionFeePolicy
            .requiredExcessFeeSatoshis(
                for: prepared.material.contributor,
                in: prepared.manifest.core.roster
            )
        let totalOutputAmount = input.amountSatoshis
            - 141
            - requiredShare
            - UInt64(outputCount * 34)
        let quotient = totalOutputAmount / UInt64(outputCount)
        let remainder = Int(totalOutputAmount % UInt64(outputCount))
        let exactOutputs = (0 ..< outputCount).map { index in
            OpalFusion.Host.ParticipantOutput(
                lockingScriptBytes: output.lockingScriptBytes,
                amountSatoshis: quotient + (index < remainder ? 1 : 0)
            )
        }
        let exactLease = try lease(inputs: [input], outputs: exactOutputs)
        let exact = try rebuild(prepared, lease: exactLease)
        #expect(exact.slots.allSatisfy { $0.component.payload != .blank })

        let overfullLease = try lease(
            inputs: [input],
            outputs: exactOutputs + [output]
        )
        #expect(throws: Alpha.LocalContributionMaterial.BuildError
            .leaseComponentLimitExceeded(actual: 24)) {
            _ = try rebuild(prepared, lease: overfullLease)
        }

        var unbalancedOutputs = exactOutputs
        let first = try #require(unbalancedOutputs.first)
        unbalancedOutputs[0] = .init(
            lockingScriptBytes: first.lockingScriptBytes,
            amountSatoshis: first.amountSatoshis + 1
        )
        #expect(throws: Alpha.LocalContributionMaterial.BuildError
            .contributionBalanceMismatch(
                expected: requiredShare,
                actual: Int64(requiredShare) - 1
            )) {
            _ = try rebuild(
                prepared,
                lease: try lease(inputs: [input], outputs: unbalancedOutputs)
            )
        }
    }

    @Test("Seal reservation publication to the exact built material")
    func sealReservationPublication() throws {
        let prepared = try makePreparedMaterial()
        let material = prepared.material
        let request = Alpha.RuntimeSession.ReservationPublicationRequest(
            attemptIdentifier: material.attemptIdentifier,
            generationIdentifier: material.generationIdentifier,
            materialIdentifier: material.materialIdentifier,
            contributor: material.contributor,
            manifest: material.manifest,
            reservationLease: material.reservationLease,
            playerCommit: material.playerCommit
        )
        let validation = try Alpha.RuntimeSession
            .ReservationPublicationValidation(
                validating: request,
                using: material
            )
        #expect(validation.request == request)

        let substituted = Alpha.RuntimeSession.ReservationPublicationRequest(
            attemptIdentifier: request.attemptIdentifier,
            generationIdentifier: request.generationIdentifier,
            materialIdentifier: .init(
                opaqueBytes: [UInt8](repeating: 0xFF, count: 32)
            ),
            contributor: request.contributor,
            manifest: request.manifest,
            reservationLease: request.reservationLease,
            playerCommit: request.playerCommit
        )
        #expect(throws: Alpha.RuntimeSession.ReservationPublicationValidation
            .ValidationError.rejected) {
            _ = try Alpha.RuntimeSession.ReservationPublicationValidation(
                validating: substituted,
                using: material
            )
        }
    }

    private func makePreparedMaterial() throws -> PreparedMaterial {
        let election = try MosaicMainnetAlphaFixtures.makeElection()
        let manifest = try MosaicMainnetAlphaFixtures.makeManifest(
            election: election,
            verificationKey: MosaicMainnetAlphaFixtures.rsaVerificationKey()
        )
        let contributor = try #require(manifest.core.orderedContributors.first)
        return try makeMaterial(
            election: election,
            manifest: manifest,
            contributor: contributor,
            contributorIndex: 0
        )
    }

    private func makeMaterial(
        election: MosaicRoleElectionFixtures.Election,
        manifest: Alpha.RoundManifest,
        contributor: Attempt.ControlIdentity,
        contributorIndex: Int
    ) throws -> PreparedMaterial {
        let inputSigningKey = try signingKey(scalar: 220 + contributorIndex)
        let publicKey = [UInt8](
            inputSigningKey.publicKey.compressedRepresentation
        )
        let lockingScript = p2pkhLockingScript(publicKey: publicKey)
        let share = try Alpha.ContributionFeePolicy.requiredExcessFeeSatoshis(
            for: contributor,
            in: manifest.core.roster
        )
        let inputAmount: UInt64 = 100_000 + UInt64(contributorIndex * 1_000)
        let outputAmount = inputAmount - 175 - share
        let lease = try self.lease(
            input: .init(
                outpointTransactionHashBytes:
                    MosaicUnsignedTransactionTranscriptFixtures.indexedDigest(
                        1_000 + contributorIndex
                    ),
                outpointIndex: UInt32(contributorIndex),
                amountSatoshis: inputAmount,
                lockingScriptBytes: lockingScript,
                publicKey: publicKey
            ),
            output: .init(
                lockingScriptBytes: lockingScript,
                amountSatoshis: outputAmount
            ),
            finalReferenceByte: UInt8(contributorIndex + 1)
        )
        let secrets = try (0 ..< Alpha.componentCountPerContributor).map {
            slot in
            let ordinal = contributorIndex * Alpha.componentCountPerContributor
                + slot + 1
            return try Alpha.ComponentSlotSecrets(
                salt: MosaicUnsignedTransactionTranscriptFixtures.indexedDigest(
                    10_000 + ordinal
                ),
                pedersenNonce: .init(
                    rawRepresentation: scalarBytes(ordinal)
                ),
                communicationPrivateKey: .init(
                    rawRepresentation: scalarBytes(ordinal + 50)
                ),
                componentAuthorizationNonce:
                    MosaicUnsignedTransactionTranscriptFixtures.indexedDigest(
                        20_000 + ordinal
                    ),
                bchSignatureAuthorizationNonce:
                    MosaicUnsignedTransactionTranscriptFixtures.indexedDigest(
                        30_000 + ordinal
                    ),
                recipientEventIdentity: [UInt8](
                    try signingKey(scalar: ordinal + 100)
                        .bip340VerificationKey.rawRepresentation
                )
            )
        }
        let material = try Alpha.LocalContributionMaterial.build(
            attemptIdentifier: .init(
                validatedBytes: [UInt8](repeating: 0xA1, count: 32)
            ),
            generationIdentifier: .init(
                opaqueBytes: [UInt8](repeating: 0xA2, count: 32)
            ),
            materialIdentifier: .init(
                opaqueBytes: MosaicUnsignedTransactionTranscriptFixtures
                    .indexedDigest(40_000 + contributorIndex)
            ),
            contributor: contributor,
            manifest: manifest,
            reservationLease: lease,
            slotSecrets: secrets
        )
        return .init(
            election: election,
            manifest: manifest,
            material: material,
            secrets: secrets
        )
    }

    private func rebuild(
        _ prepared: PreparedMaterial,
        lease: OpalFusion.Host.MosaicReservationLease? = nil,
        secrets: [Alpha.ComponentSlotSecrets]? = nil
    ) throws -> Alpha.LocalContributionMaterial {
        try Alpha.LocalContributionMaterial.build(
            attemptIdentifier: prepared.material.attemptIdentifier,
            generationIdentifier: prepared.material.generationIdentifier,
            materialIdentifier: prepared.material.materialIdentifier,
            contributor: prepared.material.contributor,
            manifest: prepared.manifest,
            reservationLease: lease ?? prepared.material.reservationLease,
            slotSecrets: secrets ?? prepared.secrets
        )
    }

    private func lease(
        input: OpalFusion.Host.ParticipantInput,
        output: OpalFusion.Host.ParticipantOutput,
        finalReferenceByte: UInt8 = 1
    ) throws -> OpalFusion.Host.MosaicReservationLease {
        try lease(
            inputs: [input],
            outputs: [output],
            finalReferenceByte: finalReferenceByte
        )
    }

    private func lease(
        inputs: [OpalFusion.Host.ParticipantInput],
        outputs: [OpalFusion.Host.ParticipantOutput],
        finalReferenceByte: UInt8 = 1
    ) throws -> OpalFusion.Host.MosaicReservationLease {
        try .init(
            reference: .init(
                identifier: UUID(
                    uuid: (
                        0, 0, 0, 0, 0, 0, 0, 0,
                        0, 0, 0, 0, 0, 0, 0, finalReferenceByte
                    )
                ),
                generation: 1
            ),
            expiresAt: Date(timeIntervalSince1970: 1_900_000_000),
            participantReservation: .init(inputs: inputs, outputs: outputs)
        )
    }

    private func replacing(
        _ input: OpalFusion.Host.ParticipantInput,
        lockingScript: [UInt8]? = nil,
        publicKey: [UInt8]?? = nil
    ) -> OpalFusion.Host.ParticipantInput {
        .init(
            outpointTransactionHashBytes: input.outpointTransactionHashBytes,
            outpointIndex: input.outpointIndex,
            amountSatoshis: input.amountSatoshis,
            lockingScriptBytes: lockingScript ?? input.lockingScriptBytes,
            publicKey: publicKey ?? input.publicKey
        )
    }

    private func replacing(
        _ value: Alpha.ComponentSlotSecrets,
        salt: [UInt8]? = nil,
        pedersenNonce: OpalCrypto.Pedersen.Nonce? = nil,
        communicationPrivateKey: OpalCrypto.Secp256k1.PrivateKey? = nil,
        componentAuthorizationNonce: [UInt8]? = nil,
        bchSignatureAuthorizationNonce: [UInt8]? = nil,
        recipientEventIdentity: [UInt8]? = nil
    ) throws -> Alpha.ComponentSlotSecrets {
        try .init(
            salt: salt ?? value.salt,
            pedersenNonce: pedersenNonce ?? value.pedersenNonce,
            communicationPrivateKey:
                communicationPrivateKey ?? value.communicationPrivateKey,
            componentAuthorizationNonce:
                componentAuthorizationNonce
                    ?? value.componentAuthorizationNonce,
            bchSignatureAuthorizationNonce:
                bchSignatureAuthorizationNonce
                    ?? value.bchSignatureAuthorizationNonce,
            recipientEventIdentity:
                recipientEventIdentity ?? value.recipientEventIdentity
        )
    }

    private func signingKey(
        scalar: Int
    ) throws -> OpalCrypto.Secp256k1.SigningKey {
        try .init(rawRepresentation: scalarBytes(scalar))
    }

    private func scalarBytes(_ scalar: Int) -> Data {
        precondition((1 ... 255).contains(scalar))
        return Data(repeating: 0, count: 31) + Data([UInt8(scalar)])
    }

    private func p2pkhLockingScript(publicKey: [UInt8]) -> [UInt8] {
        [0x76, 0xA9, 0x14]
            + OpalFusion.Execution.ProtocolPrimitives.hash160(publicKey)
            + [0x88, 0xAC]
    }
}

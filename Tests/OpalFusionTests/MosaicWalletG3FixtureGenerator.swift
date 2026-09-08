// MosaicWalletG3FixtureGenerator.swift

#if os(macOS)
import Compression
import Foundation
import Security
import Testing
@_spi(MosaicPrivateAlpha) import OpalCrypto
@_spi(MosaicPrivateAlpha) @testable import OpalFusion

@Suite("Wallet G3 fixture generator")
struct MosaicWalletG3FixtureGenerator {
    typealias Alpha = OpalFusion.Mosaic.OpalMainnetAlpha
    typealias Attempt = OpalFusion.Mosaic.Attempt
    typealias Host = OpalFusion.Host
    typealias LocalAttempt = OpalFusion.Mosaic.LocalAttempt
    typealias Nostr = OpalFusion.Mosaic.NostrNamespace
    typealias OpalV0 = OpalFusion.Mosaic.OpalV0
    typealias Runtime = OpalFusion.MosaicPrivateAlphaRuntime
    typealias Transport = Alpha.PostManifestNIP59Transport

    private struct StoredEvent: Encodable {
        let acceptedAtUnixSeconds: UInt64
        let canonicalEventBytes: Data

        init(
            _ event: OpalFusion.MosaicPrivateAlphaRuntime
                .PrivateDeploymentEvent
        ) {
            acceptedAtUnixSeconds = event.acceptedAtUnixSeconds
            canonicalEventBytes = event.canonicalEventBytes
        }
    }

    private struct GeneratedFixture: Encodable {
        let epoch: UInt64
        let opaquePoolDocument: Data
        let relaySetDocument: Data
        let localBeaconProofOfWorkNonce: UInt64
        let localDiscoveryKeyScalar: UInt8
        let localAdmissionControlKeyScalar: UInt8
        let localRoleKeyScalar: UInt8
        let localConductorKeyScalar: UInt8
        let localManifestSignerKeyScalar: UInt8
        let roleRandomness: Data
        let publicSources: [Data]
        let componentAuthorizationKey: Data
        let bchSignatureAuthorizationKey: Data
        let beaconEvents: [StoredEvent]
        let acknowledgementEvents: [StoredEvent]
        let admissionEvents: [StoredEvent]
        let commitmentEvents: [StoredEvent]
        let revealEvents: [StoredEvent]
        let nonceEvent: StoredEvent
        let proposalEvent: StoredEvent
        let signatureEvents: [StoredEvent]
        let postManifestMailbox: PostManifestMailbox
        let postManifestRelayPhases: [[Data]]
        let postManifestOutboundPublicationCounts:
            OutboundPublicationCounts
        let postManifestCompletionEvent: StoredEvent
        let previousTransactions: [Data]
        let localPreviousTransaction: Data
        let expectedCompleteTransaction: Data
        let localContributorIndex: Int
    }

    private struct PostManifestMailbox: Encodable {
        let currentUnixSeconds: UInt64
        let authorizationKey: Data
        let controlClaimSet: Data
        let blindResponseSet: Data
        let registrationSet: Data
        let acknowledgementSet: Data
        let registration: Data
        let assignment: Data
        let contributorControlIdentity: Data
        let localControlRecipientPrivateKey: Data
        let authorizationRecoveryStates: [AuthorizationRecoveryState]
    }

    private struct AuthorizationRecoveryState: Encodable {
        let componentRequest: Data
        let bchSignatureRequest: Data
    }

    private struct OutboundPublicationCounts: Encodable {
        let playerCommit: Int
        let anonymousComponents: Int
        let preSignAcknowledgement: Int
        let bchSignatures: Int

        var total: Int {
            playerCommit
                + anonymousComponents
                + preSignAcknowledgement
                + bchSignatures
        }
    }

    private struct Materialized {
        let materials: [Attempt.ControlIdentity: Alpha.LocalContributionMaterial]
        let commitmentSet: OpalV0.CommitmentSet
        let componentSet: OpalV0.ComponentSet
        let transcript: OpalV0.UnsignedTransactionTranscript
    }

    private struct AggregateRun {
        let envelopes: [Alpha.ControlEnvelope]
        let nextSequence: UInt64
    }

    private struct Outpoint: Hashable {
        let transactionHash: [UInt8]
        let outputIndex: UInt32

        init(_ input: Host.ParticipantInput) {
            transactionHash = input.outpointTransactionHashBytes
            outputIndex = input.outpointIndex
        }

        init(_ request: Host.MosaicPreviousOutputRequest) {
            transactionHash = request.transactionHashBytes
            outputIndex = request.outputIndex
        }
    }

    private struct PreviousOutputSource: Host.MosaicPreviousOutputSource {
        let inputs: [Outpoint: Host.ParticipantInput]

        func resolvePreviousOutputs(
            for requests: [Host.MosaicPreviousOutputRequest]
        ) async throws -> [Host.MosaicPreviousOutput] {
            try requests.map { request in
                guard let input = inputs[Outpoint(request)] else {
                    throw GeneratorFailure.missingValue
                }
                return try .init(
                    transactionHashBytes: request.transactionHashBytes,
                    outputIndex: request.outputIndex,
                    amountSatoshis: input.amountSatoshis,
                    lockingScriptBytes: input.lockingScriptBytes,
                    tokenState: .absent
                )
            }
        }
    }

    private struct PreparedPostManifest {
        let mailbox: PostManifestMailbox
        let phases: [[Data]]
        let outboundPublicationCounts: OutboundPublicationCounts
        let completionEvent: Runtime.PrivateDeploymentEvent
        let previousTransactions: [Data]
        let localPreviousTransaction: Data
        let completeTransaction: Data
        let localContributorIndex: Int
    }

    private enum GeneratorFailure: Error {
        case compressionFailed
        case keyImportFailed
        case missingValue
        case scalarUnavailable
    }

    @Test("Generate Wallet G3 serialized relay fixture")
    func generate() async throws {
        let componentSigningKey = try RFC9500RSATestKeyFixture
            .makeSigningKey()
        let bchSigningKey = try makeSecondRSASigningKey()
        let fixture = try MosaicPrivateDeploymentFixtures
            .makePrivateAlphaRuntimeProof(
                componentAuthorizationVerificationKey:
                    componentSigningKey.verificationKey,
                bchSignatureAuthorizationVerificationKey:
                    bchSigningKey.verificationKey
            )
        let inputs = try MosaicPrivateDeploymentFixtures
            .makeLocalFormationInputs(formation: fixture.formation)
        let postManifest = try await makePostManifest(
            proof: fixture.proof,
            formation: fixture.formation,
            componentSigningKey: componentSigningKey,
            bchSigningKey: bchSigningKey
        )
        let beaconInput = MosaicPrivateDeploymentFixtures
            .makeLocalBeaconInput(formation: fixture.formation)
        let result = GeneratedFixture(
            epoch: fixture.epoch,
            opaquePoolDocument: fixture.opaquePoolDocument,
            relaySetDocument: fixture.relaySetDocument,
            localBeaconProofOfWorkNonce: beaconInput.proofOfWorkNonce,
            localDiscoveryKeyScalar: try scalar(
                for: inputs.discoveryCandidate.signingKey
            ),
            localAdmissionControlKeyScalar: try scalar(
                for: inputs.admissionControlCandidate.signingKey
            ),
            localRoleKeyScalar: try scalar(
                for: inputs.roleCandidate.signingKey
            ),
            localConductorKeyScalar: try scalar(
                for: inputs.conductorCandidate.signingKey
            ),
            localManifestSignerKeyScalar: try scalar(
                for: inputs.manifestSigner.signingKey
            ),
            roleRandomness: inputs.roleRandomness,
            publicSources: inputs.publicSources,
            componentAuthorizationKey: Data(
                componentSigningKey.verificationKey.subjectPublicKeyInfo
            ),
            bchSignatureAuthorizationKey: Data(
                bchSigningKey.verificationKey.subjectPublicKeyInfo
            ),
            beaconEvents: fixture.beaconEvents.map(StoredEvent.init),
            acknowledgementEvents:
                fixture.acknowledgementEvents.map(StoredEvent.init),
            admissionEvents: fixture.admissionEvents.map(StoredEvent.init),
            commitmentEvents: fixture.commitmentEvents.map(StoredEvent.init),
            revealEvents: fixture.revealEvents.map(StoredEvent.init),
            nonceEvent: .init(fixture.nonceEvent),
            proposalEvent: .init(fixture.proposalEvent),
            signatureEvents: fixture.signatureEvents.map(StoredEvent.init),
            postManifestMailbox: postManifest.mailbox,
            postManifestRelayPhases: postManifest.phases,
            postManifestOutboundPublicationCounts:
                postManifest.outboundPublicationCounts,
            postManifestCompletionEvent:
                .init(postManifest.completionEvent),
            previousTransactions: postManifest.previousTransactions,
            localPreviousTransaction:
                postManifest.localPreviousTransaction,
            expectedCompleteTransaction: postManifest.completeTransaction,
            localContributorIndex: postManifest.localContributorIndex
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let json = try encoder.encode(result)
        let compressed = try compress(json)
        let rawURL = URL(
            fileURLWithPath: "/private/tmp/mosaic-wallet-g3-fixture.json"
        )
        let base64URL = URL(
            fileURLWithPath:
                "/private/tmp/mosaic-wallet-g3-fixture.base64.txt"
        )
        try json.write(to: rawURL, options: .atomic)
        try compressed.base64EncodedData(
            options: [.lineLength76Characters, .endLineWithLineFeed]
        ).write(to: base64URL, options: .atomic)
        let digest = OpalCrypto.Hashing.sha256(json).map {
            String(format: "%02x", $0)
        }.joined()
        #expect(json.count == 1_705_322)
        #expect(
            digest
                == "ec6755c6cf6a736ddf8538d32e0fa48afc247342fe6a4a424d826a0a62f2ee7a"
        )
        print(
            "WALLET_G3_FIXTURE json=\(json.count) compressed=\(compressed.count) sha256=\(digest) phases=\(postManifest.phases.map(\.count)) outbound=\(postManifest.outboundPublicationCounts.total) localContributorIndex=\(postManifest.localContributorIndex)"
        )
    }

    private func makePostManifest(
        proof: OpalFusion.MosaicPrivateAlphaRuntime.PrivateDeploymentProof,
        formation: MosaicPrivateDeploymentFixtures.Formation,
        componentSigningKey: OpalCrypto.RSABSSA.SigningKey,
        bchSigningKey: OpalCrypto.RSABSSA.SigningKey
    ) async throws -> PreparedPostManifest {
        let manifest = proof.completeManifest
        let localIdentity = formation.controlCandidates[0].controlIdentity
        guard let localContributorIndex = manifest.core.roster.contributors
            .firstIndex(of: localIdentity),
              let localOrderedIndex = manifest.core.orderedContributors
                .firstIndex(of: localIdentity),
              let localControlIndex = manifest.core.roster.controlIdentities
                .firstIndex(of: localIdentity) else {
            throw GeneratorFailure.missingValue
        }
        let attemptIdentifier = LocalAttempt.AttemptIdentifier(
            validatedBytes: [UInt8](repeating: 0x71, count: 32)
        )
        let generationIdentifier = LocalAttempt.GenerationIdentifier(
            opaqueBytes: [UInt8](repeating: 0x72, count: 32)
        )
        let localMaterialIdentifier = LocalAttempt.MaterialIdentifier(
            opaqueBytes: [UInt8](repeating: 0x73, count: 32)
        )
        let inputSigningKey = try walletSigningKey(usage: 1)
        let outputSigningKey = try walletSigningKey(usage: 0)
        var materials: [
            Attempt.ControlIdentity: Alpha.LocalContributionMaterial
        ] = [:]
        var previousTransactions: [Data] = []
        var localPreviousTransaction: Data?
        for (index, contributor) in manifest.core.orderedContributors
            .enumerated() {
            let isLocal = contributor == localIdentity
            let contributorSigningKey = isLocal
                ? inputSigningKey
                : try signingKey(seed: 10_000 + index)
            let inputAmount = UInt64(100_000 + (isLocal ? 0 : index * 1_000))
            let outputAmount: UInt64
            if isLocal {
                outputAmount = 99_823
            } else {
                let requiredShare = try Alpha.ContributionFeePolicy
                    .requiredExcessFeeSatoshis(
                        for: contributor,
                        in: manifest.core.roster
                    )
                outputAmount = inputAmount - 175 - requiredShare
            }
            let previousTransaction = try previousTransaction(
                discriminator: index,
                amountSatoshis: inputAmount,
                lockingScript: lockingScript(contributorSigningKey)
            )
            previousTransactions.append(previousTransaction)
            if isLocal {
                localPreviousTransaction = previousTransaction
            }
            let lease = try reservationLease(
                contributorIndex: index,
                isLocal: isLocal,
                manifest: manifest,
                signingKey: contributorSigningKey,
                outputSigningKey: isLocal
                    ? outputSigningKey
                    : contributorSigningKey,
                previousTransaction: previousTransaction,
                inputAmountSatoshis: inputAmount,
                outputAmountSatoshis: outputAmount
            )
            let materialIdentifier = isLocal
                ? localMaterialIdentifier
                : LocalAttempt.MaterialIdentifier(
                    opaqueBytes:
                        MosaicUnsignedTransactionTranscriptFixtures
                            .indexedDigest(52_000 + index)
                )
            let slotSecrets = try isLocal
                ? localSlotSecrets(
                    contributorIndex: localContributorIndex
                )
                : remoteSlotSecrets(contributorIndex: index)
            let randomizedMaterial = try Alpha.LocalContributionMaterial.build(
                attemptIdentifier: attemptIdentifier,
                generationIdentifier: generationIdentifier,
                materialIdentifier: materialIdentifier,
                contributor: contributor,
                manifest: manifest,
                reservationLease: lease,
                slotSecrets: slotSecrets
            )
            let recoveryStates = try randomizedMaterial
                .componentSlotAuthorizationRecoveryStates.enumerated().map {
                    slot, state in
                    let base = index * Alpha.componentCountPerContributor * 2
                        + slot * 2
                    return Alpha.ComponentSlotAuthorizationRecoveryState(
                        componentRequest:
                            try deterministicFixtureRecoveryState(
                                binding: state.componentRequest,
                                discriminator: base
                            ),
                        bchSignatureRequest:
                            try deterministicFixtureRecoveryState(
                                binding: state.bchSignatureRequest,
                                discriminator: base + 1
                            )
                    )
                }
            materials[contributor] = try Alpha.LocalContributionMaterial.build(
                attemptIdentifier: attemptIdentifier,
                generationIdentifier: generationIdentifier,
                materialIdentifier: materialIdentifier,
                contributor: contributor,
                manifest: manifest,
                reservationLease: lease,
                slotSecrets: slotSecrets,
                authorizationRecoveryStates: recoveryStates
            )
        }
        guard let localMaterial = materials[localIdentity],
              let localPreviousTransaction else {
            throw GeneratorFailure.missingValue
        }
        let mailbox = try makePostManifestMailbox(
            proof: proof,
            formation: formation,
            authorizationSigningKey: componentSigningKey,
            localIdentity: localIdentity,
            authorizationRecoveryStates: localMaterial
                .componentSlotAuthorizationRecoveryStates.map {
                    .init(
                        componentRequest:
                            $0.componentRequest.rawRepresentation,
                        bchSignatureRequest:
                            $0.bchSignatureRequest.rawRepresentation
                    )
                }
        )
        let materialized = try materialize(
            manifest: manifest,
            materials: materials
        )
        let responseSets = try manifest.core.orderedContributors.map {
            contributor in
            guard let material = materials[contributor] else {
                throw GeneratorFailure.missingValue
            }
            return try authorizationResponseSet(
                material: material,
                componentSigningKey: componentSigningKey,
                bchSigningKey: bchSigningKey
            )
        }
        let acknowledgementSet = try makeAcknowledgementSet(
            formation: formation,
            manifest: manifest,
            transcript: materialized.transcript
        )
        let previousOutputSource = PreviousOutputSource(
            inputs: Dictionary(
                uniqueKeysWithValues: materials.values.flatMap { material in
                    material.reservationLease.participantReservation.inputs
                        .map { (Outpoint($0), $0) }
                }
            )
        )
        let previousOutputs = try await Alpha.PreviousOutputResolver(
            source: previousOutputSource
        ).resolve(for: materialized.transcript)
        var signingKeys: [Outpoint: OpalCrypto.Secp256k1.SigningKey] = [:]
        for (index, contributor) in manifest.core.orderedContributors
            .enumerated() {
            guard let material = materials[contributor] else {
                throw GeneratorFailure.missingValue
            }
            let key = index == localOrderedIndex
                ? inputSigningKey
                : try signingKey(seed: 10_000 + index)
            for input in material.reservationLease.participantReservation.inputs {
                signingKeys[Outpoint(input)] = key
            }
        }
        let signatureSet = try makeSignatureSet(
            manifest: manifest,
            transcript: materialized.transcript,
            previousOutputs: previousOutputs,
            signingKeys: signingKeys
        )
        let completeTransaction = try Alpha.CompleteTransactionAssembler
            .assemble(
                transcript: materialized.transcript,
                signatureSet: signatureSet,
                spentInputs: previousOutputs.spentInputs
            )
        let completePayload = try Alpha.CompleteTransactionPayload(
            roundIdentifier: manifest.core.roundIdentifier,
            transcriptRoot:
                materialized.transcript.transcriptRoot.validatedBytes,
            completeTransaction: completeTransaction
        )
        let completeCandidate = try Alpha.CompleteTransactionCandidate(
            attemptIdentifier: attemptIdentifier,
            generationIdentifier: generationIdentifier,
            materialIdentifier: localMaterialIdentifier,
            transcript: materialized.transcript,
            signatureSet: signatureSet,
            payload: completePayload
        )
        let completeValidation = try Alpha.CompleteTransactionValidation(
            validating: completeCandidate,
            previousOutputs: previousOutputs
        )
        let completionValidation = try Alpha
            .PrivateDeploymentCompletionValidation(
                manifest: proof.proposalValidation.manifest,
                roundManifest: manifest,
                completeTransactionValidation: completeValidation
            )
        let completionPayload = try Alpha.PreManifestNostrPayloadDocument
            .makeCompletion(
                .init(validation: completionValidation),
                validation: completionValidation
            )
        let completionEvent = try Runtime.PrivateDeploymentEvent.makeLocal(
            payload: completionPayload,
            createdAtUnixSeconds: manifest.core.deadlines.bchSigning,
            signing: .init(
                signingKey: formation.controlCandidate(
                    for: manifest.core.roster.conductor
                ).signingKey,
                documentAuxiliaryRandomness: try .init(
                    rawRepresentation: Data(repeating: 0xD2, count: 32)
                ),
                eventAuxiliaryRandomness: try .init(
                    rawRepresentation: Data(repeating: 0xD3, count: 32)
                )
            )
        )
        let playerCommitEnvelopeCount = try aggregateRun(
            canonicalBytes: localMaterial.playerCommit.canonicalBytes,
            kind: .playerCommit,
            sender: localIdentity,
            phase: .groupedCommitment,
            sequence: 0,
            manifest: manifest,
            formation: formation
        ).envelopes.count
        let outboundPublicationCounts = OutboundPublicationCounts(
            playerCommit:
                playerCommitEnvelopeCount
                    * manifest.core.roster.controlIdentities.count,
            anonymousComponents: localMaterial.slots.count,
            preSignAcknowledgement:
                manifest.core.roster.controlIdentities.count,
            bchSignatures: localMaterial.reservationLease
                .participantReservation.inputs.count
        )
        let conductor = manifest.core.roster.conductor
        let recipientKey = try signingKey(seed: 1_000 + localControlIndex)
        let manifestRun = try aggregateRun(
            canonicalBytes: manifest.canonicalBytes,
            kind: .completeManifest,
            sender: conductor,
            phase: .manifestAgreement,
            sequence: 0,
            manifest: manifest,
            formation: formation
        )
        var conductorSequence = manifestRun.nextSequence
        var reservationPhase: [Alpha.ControlEnvelope] = []
        for responseSet in responseSets {
            let run = try aggregateRun(
                canonicalBytes: responseSet.canonicalBytes,
                kind: .authorizationResponseSet,
                sender: conductor,
                phase: .walletReservation,
                sequence: conductorSequence,
                manifest: manifest,
                formation: formation
            )
            reservationPhase.append(contentsOf: run.envelopes)
            conductorSequence = run.nextSequence
        }
        let commitmentRun = try aggregateRun(
            canonicalBytes: materialized.commitmentSet.canonicalBytes,
            kind: .commitmentSet,
            sender: conductor,
            phase: .groupedCommitment,
            sequence: conductorSequence,
            manifest: manifest,
            formation: formation
        )
        reservationPhase.append(contentsOf: commitmentRun.envelopes)
        let componentRun = try aggregateRun(
            canonicalBytes: materialized.componentSet.canonicalBytes,
            kind: .componentSet,
            sender: conductor,
            phase: .anonymousComponentSubmission,
            sequence: commitmentRun.nextSequence,
            manifest: manifest,
            formation: formation
        )
        let acknowledgementRun = try aggregateRun(
            canonicalBytes: acknowledgementSet.canonicalBytes,
            kind: .preSignAcknowledgementSet,
            sender: conductor,
            phase: .transcriptAgreement,
            sequence: componentRun.nextSequence,
            manifest: manifest,
            formation: formation
        )
        let signatureRun = try aggregateRun(
            canonicalBytes: signatureSet.canonicalBytes,
            kind: .bchSignatureSet,
            sender: conductor,
            phase: .bchSigning,
            sequence: acknowledgementRun.nextSequence,
            manifest: manifest,
            formation: formation
        )
        let completeRun = try aggregateRun(
            canonicalBytes: completePayload.canonicalBytes,
            kind: .completeTransaction,
            sender: conductor,
            phase: .bchSigning,
            sequence: signatureRun.nextSequence,
            manifest: manifest,
            formation: formation
        )
        var giftWrapOrdinal = 0
        let phases = try [
            manifestRun.envelopes,
            reservationPhase,
            componentRun.envelopes,
            acknowledgementRun.envelopes,
            signatureRun.envelopes + completeRun.envelopes,
        ].map { envelopes in
            try envelopes.map { envelope in
                defer { giftWrapOrdinal += 1 }
                return try giftWrapBytes(
                    envelope: envelope,
                    recipientKey: recipientKey,
                    manifest: manifest,
                    formation: formation,
                    ordinal: giftWrapOrdinal
                )
            }
        }
        return .init(
            mailbox: mailbox,
            phases: phases,
            outboundPublicationCounts: outboundPublicationCounts,
            completionEvent: completionEvent,
            previousTransactions: previousTransactions,
            localPreviousTransaction: localPreviousTransaction,
            completeTransaction: Data(completeTransaction.transactionBytes),
            localContributorIndex: localContributorIndex
        )
    }

    private func makePostManifestMailbox(
        proof: Runtime.PrivateDeploymentProof,
        formation: MosaicPrivateDeploymentFixtures.Formation,
        authorizationSigningKey: OpalCrypto.RSABSSA.SigningKey,
        localIdentity: Attempt.ControlIdentity,
        authorizationRecoveryStates: [AuthorizationRecoveryState]
    ) throws -> PostManifestMailbox {
        let currentUnixSeconds = proof.phaseStartUnixSeconds + 1
        let conductorIdentity = Attempt.ControlIdentity(
            validatedBytes: Array(proof.conductorControlIdentity)
        )
        let conductorKey = formation.controlCandidate(
            for: conductorIdentity
        ).signingKey
        let authorizationKey = try Runtime
            .makeTransportBootstrapAuthorizationKeyDocument(
                proof: proof,
                authorizationSigningKey: authorizationSigningKey,
                conductorControlSigningKey: conductorKey,
                auxiliaryRandomness: try .init(
                    rawRepresentation: Data(repeating: 0x31, count: 32)
                )
            )

        var requests: [
            Data: Runtime.TransportBootstrapAnonymousMailboxRequest
        ] = [:]
        var anonymousSenderKeys: [
            Data: OpalCrypto.Secp256k1.SigningKey
        ] = [:]
        for (index, identity) in proof.contributorControlIdentities
            .enumerated() {
            let senderPrivateKey = try privateKey(seed: 2_000 + index)
            anonymousSenderKeys[identity] = senderPrivateKey.makeSigningKey()
            let randomizedRequest = try Runtime
                .makeTransportBootstrapAnonymousMailboxRequest(
                    proof: proof,
                    authorizationKey: authorizationKey,
                    authorizationNonce: Data(
                        repeating: UInt8(0x80 + index),
                        count: 32
                    ),
                    anonymousSenderPrivateKey: senderPrivateKey
                )
            let recoveryState = try deterministicFixtureRecoveryState(
                binding: randomizedRequest.recoveryState,
                discriminator: 10_000 + index
            )
            let restoredBlindRequest = try OpalCrypto.RSABSSA
                .restoreBlindRequest(
                    message: randomizedRequest.input.canonicalDocument,
                    using: authorizationKey.verificationKey,
                    from: recoveryState
                )
            requests[identity] = try Runtime
                .restoreTransportBootstrapAnonymousMailboxRequest(
                    proof: proof,
                    authorizationKey: authorizationKey,
                    authorizationNonce: Data(
                        repeating: UInt8(0x80 + index),
                        count: 32
                    ),
                    anonymousSenderPrivateKey: senderPrivateKey,
                    recoveryState: recoveryState,
                    expectedBlindedMessage:
                        restoredBlindRequest.blindedMessage.rawRepresentation
                )
        }

        var controlRecipientPrivateKeys: [
            Data: OpalCrypto.Secp256k1.PrivateKey
        ] = [:]
        var claims: [Runtime.TransportBootstrapControlMailboxClaim] = []
        for (index, identity) in proof.controlIdentities.enumerated() {
            let recipientPrivateKey = try privateKey(seed: 1_000 + index)
            controlRecipientPrivateKeys[identity] = recipientPrivateKey
            claims.append(
                try Runtime.makeTransportBootstrapControlMailboxClaim(
                    proof: proof,
                    authorizationKey: authorizationKey,
                    controlSigningKey: formation.controlCandidate(
                        for: .init(validatedBytes: Array(identity))
                    ).signingKey,
                    recipientEventVerificationKey:
                        recipientPrivateKey.makeSigningKey()
                            .bip340VerificationKey,
                    anonymousMailboxRequest: requests[identity],
                    auxiliaryRandomness: try .init(
                        rawRepresentation: Data(
                            repeating: UInt8(0x40 + index),
                            count: 32
                        )
                    )
                )
            )
        }
        let claimSet = try Runtime
            .makeTransportBootstrapControlMailboxClaimSet(
                proof: proof,
                authorizationKey: authorizationKey,
                claims: claims
            )
        let responseSet = try Runtime.makeTransportBootstrapBlindResponseSet(
            proof: proof,
            authorizationKey: authorizationKey,
            claimSet: claimSet,
            authorizationSigningKey: authorizationSigningKey,
            conductorControlSigningKey: conductorKey,
            auxiliaryRandomness: try .init(
                rawRepresentation: Data(repeating: 0x61, count: 32)
            )
        )

        var registrations: [
            Data: Runtime.TransportBootstrapAnonymousMailboxRegistration
        ] = [:]
        var assignments: [
            Data: Runtime.TransportBootstrapConductorMailboxAssignment
        ] = [:]
        for (contributorIndex, identity) in proof
            .contributorControlIdentities.enumerated() {
            guard let request = requests[identity],
                  let senderKey = anonymousSenderKeys[identity] else {
                throw GeneratorFailure.missingValue
            }
            let registration = try Runtime
                .makeTransportBootstrapAnonymousMailboxRegistration(
                    proof: proof,
                    authorizationKey: authorizationKey,
                    claimSet: claimSet,
                    responseSet: responseSet,
                    contributorControlIdentity: identity,
                    request: request,
                    anonymousSenderSigningKey: senderKey,
                    auxiliaryRandomness: try .init(
                        rawRepresentation: Data(
                            repeating: UInt8(0x70 + contributorIndex),
                            count: 32
                        )
                    )
                )
            registrations[identity] = registration
            assignments[identity] = try Runtime
                .makeTransportBootstrapAnonymousMailboxAssignment(
                    proof: proof,
                    authorizationKey: authorizationKey,
                    claimSet: claimSet,
                    responseSet: responseSet,
                    registration: registration,
                    recipientPrivateKeys: try (0 ..< 23).map { slot in
                        try privateKey(
                            seed: 3_000 + contributorIndex * 23 + slot
                        )
                    },
                    conductorControlSigningKey: conductorKey,
                    auxiliaryRandomness: try .init(
                        rawRepresentation: Data(
                            repeating: UInt8(0xA0 + contributorIndex),
                            count: 32
                        )
                    ),
                    currentUnixSeconds: currentUnixSeconds
                )
        }
        let orderedRegistrations = try proof.contributorControlIdentities.map {
            guard let registration = registrations[$0] else {
                throw GeneratorFailure.missingValue
            }
            return registration
        }
        let orderedAssignments = try proof.contributorControlIdentities.map {
            guard let assignment = assignments[$0] else {
                throw GeneratorFailure.missingValue
            }
            return assignment
        }
        let registrationSet = try Runtime
            .makeTransportBootstrapAnonymousMailboxRegistrationSet(
                proof: proof,
                authorizationKey: authorizationKey,
                claimSet: claimSet,
                responseSet: responseSet,
                registrations: orderedRegistrations,
                conductorAssignments: orderedAssignments,
                conductorControlSigningKey: conductorKey,
                auxiliaryRandomness: try .init(
                    rawRepresentation: Data(repeating: 0xB0, count: 32)
                ),
                currentUnixSeconds: currentUnixSeconds
            )
        var acknowledgements: [
            Runtime.TransportBootstrapRegistrationSetAcknowledgement
        ] = []
        for (index, identity) in proof.controlIdentities.enumerated() {
            acknowledgements.append(
                try Runtime
                    .makeTransportBootstrapRegistrationSetAcknowledgement(
                        proof: proof,
                        authorizationKey: authorizationKey,
                        claimSet: claimSet,
                        responseSet: responseSet,
                        registrationSet: registrationSet,
                        controlSigningKey: formation.controlCandidate(
                            for: .init(validatedBytes: Array(identity))
                        ).signingKey,
                        localAnonymousMailboxAssignment:
                            assignments[identity]?.assignment,
                        auxiliaryRandomness: try .init(
                            rawRepresentation: Data(
                                repeating: UInt8(0xC0 + index),
                                count: 32
                            )
                        ),
                        currentUnixSeconds: currentUnixSeconds
                    )
            )
        }
        let acknowledgementSet = try Runtime
            .makeTransportBootstrapRegistrationSetAcknowledgementSet(
                proof: proof,
                authorizationKey: authorizationKey,
                claimSet: claimSet,
                responseSet: responseSet,
                registrationSet: registrationSet,
                acknowledgements: acknowledgements,
                currentUnixSeconds: currentUnixSeconds
            )

        let localIdentityData = Data(localIdentity.validatedBytes)
        guard let registration = registrations[localIdentityData],
              let assignment = assignments[localIdentityData]?.assignment,
              let localControlRecipientPrivateKey =
                controlRecipientPrivateKeys[localIdentityData] else {
            throw GeneratorFailure.missingValue
        }
        return .init(
            currentUnixSeconds: currentUnixSeconds,
            authorizationKey: authorizationKey.canonicalDocument,
            controlClaimSet: claimSet.canonicalDocument,
            blindResponseSet: responseSet.canonicalDocument,
            registrationSet: registrationSet.canonicalDocument,
            acknowledgementSet: acknowledgementSet.canonicalDocument,
            registration: registration.canonicalDocument,
            assignment: assignment.canonicalDocument,
            contributorControlIdentity: localIdentityData,
            localControlRecipientPrivateKey:
                localControlRecipientPrivateKey.rawRepresentation,
            authorizationRecoveryStates: authorizationRecoveryStates
        )
    }

    private func materialize(
        manifest: Alpha.RoundManifest,
        materials: [Attempt.ControlIdentity: Alpha.LocalContributionMaterial]
    ) throws -> Materialized {
        let ordered = try manifest.core.orderedContributors.map {
            contributor in
            guard let material = materials[contributor] else {
                throw GeneratorFailure.missingValue
            }
            return material
        }
        let commitmentSet = try OpalV0.CommitmentSet(
            profile: .opalMainnetAlpha,
            commitments: ordered.flatMap { $0.slots.map(\.commitment) }
        )
        let componentSet = try OpalV0.ComponentSet(
            profile: .opalMainnetAlpha,
            components: ordered.flatMap { $0.slots.map(\.component) }
        )
        let validation = try Attempt.CommitmentSetValidation(
            profile: .opalMainnetAlpha,
            roster: manifest.core.roster,
            commitmentSet: commitmentSet
        )
        let transcript = try OpalV0.UnsignedTransactionTranscript(
            profile: .opalMainnetAlpha,
            roster: manifest.core.roster,
            manifest: manifest.binding,
            commitmentSet: validation,
            componentSet: componentSet
        )
        return .init(
            materials: materials,
            commitmentSet: commitmentSet,
            componentSet: componentSet,
            transcript: transcript
        )
    }

    private func authorizationResponseSet(
        material: Alpha.LocalContributionMaterial,
        componentSigningKey: OpalCrypto.RSABSSA.SigningKey,
        bchSigningKey: OpalCrypto.RSABSSA.SigningKey
    ) throws -> Alpha.AuthorizationResponseSet {
        try .init(
            roundIdentifier: material.manifest.core.roundIdentifier,
            contributor: material.contributor,
            playerCommitDigest: material.playerCommit.digest,
            componentAuthorizationResponses: try material.slots.map { slot in
                try .init(
                    slot: slot.slot,
                    blindSignature: componentSigningKey.blindSign(
                        slot.componentAuthorizationRequest.blindedMessage
                    )
                )
            },
            bchSignatureAuthorizationResponses: try material.slots.map { slot in
                try .init(
                    slot: slot.slot,
                    blindSignature: bchSigningKey.blindSign(
                        slot.bchSignatureAuthorizationRequest.blindedMessage
                    )
                )
            }
        )
    }

    private func makeAcknowledgementSet(
        formation: MosaicPrivateDeploymentFixtures.Formation,
        manifest: Alpha.RoundManifest,
        transcript: OpalV0.UnsignedTransactionTranscript
    ) throws -> Alpha.PreSignAcknowledgementSet {
        let digest = Attempt.TranscriptAcknowledgementValidation
            .signatureDigest(
                profile: .opalMainnetAlpha,
                roundIdentifier: manifest.core.roundIdentifier,
                transcriptRoot: transcript.transcriptRoot.validatedBytes
            )
        let unsorted: [Alpha.PreSignAcknowledgementSubmission] = try manifest
            .core.roster.contributors.map { contributor in
            let signature = try formation.controlCandidate(for: contributor)
                .signingKey.signBIP340(
                    digest: digest,
                    auxiliaryRandomness: .init(
                        rawRepresentation: Data(repeating: 0x5A, count: 32)
                    )
                )
            return try Alpha.PreSignAcknowledgementSubmission(
                contributor: contributor,
                roundIdentifier: manifest.core.roundIdentifier,
                transcriptRoot: transcript.transcriptRoot.validatedBytes,
                signature: Array(signature.rawRepresentation)
            )
        }
        let submissions = unsorted.sorted(by: {
            (lhs: Alpha.PreSignAcknowledgementSubmission,
             rhs: Alpha.PreSignAcknowledgementSubmission) in
            lhs.acknowledgement.contributor.validatedBytes
                .lexicographicallyPrecedes(
                    rhs.acknowledgement.contributor.validatedBytes
                )
        })
        return try .init(
            roundIdentifier: manifest.core.roundIdentifier,
            transcriptRoot: transcript.transcriptRoot.validatedBytes,
            roster: manifest.core.roster,
            submissions: submissions
        )
    }

    private func makeSignatureSet(
        manifest: Alpha.RoundManifest,
        transcript: OpalV0.UnsignedTransactionTranscript,
        previousOutputs: Alpha.PreviousOutputResolver.Validation,
        signingKeys: [Outpoint: OpalCrypto.Secp256k1.SigningKey]
    ) throws -> Alpha.BCHSignatureSet {
        let entries = try previousOutputs.spentInputs.enumerated().map {
            inputIndex, input in
            guard let signingKey = signingKeys[Outpoint(input)] else {
                throw GeneratorFailure.missingValue
            }
            let digest = try transcript.transaction.signatureHash(
                forInputAt: inputIndex,
                lockingScript: input.lockingScriptBytes,
                amountSatoshis: input.amountSatoshis,
                sighashType: 0x41
            )
            let signature = try signingKey.signSchnorr(
                digest: .init(rawRepresentation: Data(digest))
            )
            return try Alpha.BCHSignatureEntry(
                inputIndex: UInt32(inputIndex),
                signature: Array(signature.rawRepresentation),
                publicKey: Array(
                    signingKey.publicKey.compressedRepresentation
                )
            )
        }
        return try .init(
            roundIdentifier: manifest.core.roundIdentifier,
            transcriptRoot: transcript.transcriptRoot.validatedBytes,
            entries: entries,
            expectedInputCount: transcript.transaction.inputs.count
        )
    }

    private func aggregateRun(
        canonicalBytes: [UInt8],
        kind: Alpha.AggregateKind,
        sender: Attempt.ControlIdentity,
        phase: Attempt.Phase,
        sequence: UInt64,
        manifest: Alpha.RoundManifest,
        formation: MosaicPrivateDeploymentFixtures.Formation
    ) throws -> AggregateRun {
        let digest = Alpha.RoleSeedValidator.hash(
            domainSuffix: kind.digestDomainSuffix,
            fields: [canonicalBytes]
        )
        let reservation = try Alpha.AggregateReservation(
            aggregateKind: kind,
            aggregateDigest: digest,
            declaredCanonicalByteCount: canonicalBytes.count
        )
        var envelopes = [try controlEnvelope(
            sender: sender,
            phase: phase,
            payloadType: .aggregateReservation,
            payload: try Alpha.CanonicalWireCodec.encodeAggregateReservation(
                reservation
            ),
            sequence: sequence,
            manifest: manifest,
            formation: formation
        )]
        for index in 0 ..< reservation.fragmentCount {
            let lowerBound = index * Alpha.maximumAggregateFragmentBodyByteCount
            let upperBound = min(
                lowerBound + Alpha.maximumAggregateFragmentBodyByteCount,
                canonicalBytes.count
            )
            let fragment = try Alpha.AggregateFragment(
                reservationSequence: sequence,
                fragmentIndex: index,
                body: Array(canonicalBytes[lowerBound ..< upperBound]),
                reservation: reservation
            )
            envelopes.append(try controlEnvelope(
                sender: sender,
                phase: phase,
                payloadType: .aggregateFragment,
                payload: try Alpha.CanonicalWireCodec
                    .encodeAggregateFragment(fragment),
                sequence: sequence + UInt64(index) + 1,
                manifest: manifest,
                formation: formation
            ))
        }
        return .init(
            envelopes: envelopes,
            nextSequence: sequence + UInt64(reservation.fragmentCount) + 1
        )
    }

    private func controlEnvelope(
        sender: Attempt.ControlIdentity,
        phase: Attempt.Phase,
        payloadType: Alpha.ControlPayloadType,
        payload: [UInt8],
        sequence: UInt64,
        manifest: Alpha.RoundManifest,
        formation: MosaicPrivateDeploymentFixtures.Formation
    ) throws -> Alpha.ControlEnvelope {
        guard let senderIndex = manifest.core.roster.controlIdentities
            .firstIndex(of: sender) else {
            throw GeneratorFailure.missingValue
        }
        let eventKey = try signingKey(seed: 5_000 + senderIndex)
        let eventIdentity = Array(
            eventKey.bip340VerificationKey.rawRepresentation
        )
        let expiry = manifest.core.deadlines.bchSigning
        let digest = try Alpha.ControlEnvelope.signingDigest(
            roundIdentifier: manifest.core.roundIdentifier,
            phase: phase,
            senderControlIdentity: sender,
            senderEventIdentity: eventIdentity,
            sequence: sequence,
            payloadType: payloadType,
            expiryUnixSeconds: expiry,
            payload: payload
        )
        let signature = try formation.controlCandidate(for: sender)
            .signingKey.signBIP340(
                digest: .init(rawRepresentation: Data(digest)),
                auxiliaryRandomness: .init(
                    rawRepresentation: Data(repeating: 0xA4, count: 32)
                )
            )
        return try .init(
            roundIdentifier: manifest.core.roundIdentifier,
            phase: phase,
            senderControlIdentity: sender,
            senderEventIdentity: eventIdentity,
            sequence: sequence,
            payloadType: payloadType,
            expiryUnixSeconds: expiry,
            controlSignature: Array(signature.rawRepresentation),
            payload: payload
        )
    }

    private func giftWrapBytes(
        envelope: Alpha.ControlEnvelope,
        recipientKey: OpalCrypto.Secp256k1.SigningKey,
        manifest: Alpha.RoundManifest,
        formation _: MosaicPrivateDeploymentFixtures.Formation,
        ordinal: Int
    ) throws -> Data {
        guard let senderIndex = manifest.core.roster.controlIdentities
            .firstIndex(of: envelope.senderControlIdentity) else {
            throw GeneratorFailure.missingValue
        }
        let eventKey = try signingKey(seed: 5_000 + senderIndex)
        let phaseStart = manifest.core.deadlines.phaseStart
        func derivedBytes(_ lane: UInt8) -> Data {
            var input = Data(
                "opal-wallet-g3-gift-wrap-\(ordinal)".utf8
            )
            input.append(lane)
            return OpalCrypto.Hashing.sha256(input)
        }
        let event = try Transport.makeControlGiftWrap(
            envelope,
            context: .init(
                attemptIdentifier: .init(
                    validatedBytes: [UInt8](repeating: 0x71, count: 32)
                ),
                generationIdentifier: .init(
                    opaqueBytes: [UInt8](repeating: 0x72, count: 32)
                ),
                phaseStartUnixSeconds: phaseStart
            ),
            timestamps: .init(
                phaseStartUnixSeconds: phaseStart,
                currentUnixSeconds: phaseStart + 1,
                sealCreatedAt: phaseStart,
                giftWrapCreatedAt: phaseStart
            ),
            senderEventSigningKey: eventKey,
            recipientPublicKey: recipientKey.bip340VerificationKey,
            randomness: .init(
                sealNonce: try .init(
                    rawRepresentation: derivedBytes(0)
                ),
                sealAuxiliaryRandomness: try .init(
                    rawRepresentation: derivedBytes(1)
                ),
                wrapperSigningKey: try signingKey(
                    seed: 20_000 + ordinal
                ),
                wrapperNonce: try .init(
                    rawRepresentation: derivedBytes(2)
                ),
                wrapperAuxiliaryRandomness: try .init(
                    rawRepresentation: derivedBytes(3)
                )
            )
        )
        return try Nostr.EventCodec.encode(
            event,
            limits: (try Transport.codingLimits).event
        )
    }

    private func localSlotSecrets(
        contributorIndex: Int
    ) throws -> [Alpha.ComponentSlotSecrets] {
        var result: [Alpha.ComponentSlotSecrets] = []
        result.reserveCapacity(Alpha.componentCountPerContributor)
        for slot in 0 ..< Alpha.componentCountPerContributor {
            let recipientKey = try signingKey(
                seed: 3_000
                    + contributorIndex * Alpha.componentCountPerContributor
                    + slot
            )
            result.append(try Alpha.ComponentSlotSecrets(
                salt: Array(scalarBytes(100_000 + slot)),
                pedersenNonce: .init(
                    rawRepresentation: scalarBytes(110_000 + slot)
                ),
                communicationPrivateKey: .init(
                    rawRepresentation: scalarBytes(120_000 + slot)
                ),
                componentEnvelopePrivateKey: .init(
                    rawRepresentation: scalarBytes(130_000 + slot)
                ),
                bchSignatureEnvelopePrivateKey: .init(
                    rawRepresentation: scalarBytes(140_000 + slot)
                ),
                componentAuthorizationNonce:
                    Array(scalarBytes(150_000 + slot)),
                bchSignatureAuthorizationNonce:
                    Array(scalarBytes(160_000 + slot)),
                recipientEventIdentity: Array(
                    recipientKey.bip340VerificationKey.rawRepresentation
                )
            ))
        }
        return result
    }

    private func remoteSlotSecrets(
        contributorIndex: Int
    ) throws -> [Alpha.ComponentSlotSecrets] {
        try (0 ..< Alpha.componentCountPerContributor).map { slot in
            let ordinal = contributorIndex
                * Alpha.componentCountPerContributor + slot + 1
            return try Alpha.ComponentSlotSecrets(
                salt: MosaicUnsignedTransactionTranscriptFixtures
                    .indexedDigest(10_000 + ordinal),
                pedersenNonce: .init(
                    rawRepresentation: scalarBytes(ordinal)
                ),
                communicationPrivateKey: .init(
                    rawRepresentation: scalarBytes(1_000 + ordinal)
                ),
                componentEnvelopePrivateKey: .init(
                    rawRepresentation: scalarBytes(3_000 + ordinal)
                ),
                bchSignatureEnvelopePrivateKey: .init(
                    rawRepresentation: scalarBytes(4_000 + ordinal)
                ),
                componentAuthorizationNonce:
                    MosaicUnsignedTransactionTranscriptFixtures
                        .indexedDigest(20_000 + ordinal),
                bchSignatureAuthorizationNonce:
                    MosaicUnsignedTransactionTranscriptFixtures
                        .indexedDigest(30_000 + ordinal),
                recipientEventIdentity: Array(
                    try signingKey(seed: 2_000 + ordinal)
                        .bip340VerificationKey.rawRepresentation
                )
            )
        }
    }

    private func reservationLease(
        contributorIndex: Int,
        isLocal: Bool,
        manifest: Alpha.RoundManifest,
        signingKey: OpalCrypto.Secp256k1.SigningKey,
        outputSigningKey: OpalCrypto.Secp256k1.SigningKey,
        previousTransaction: Data,
        inputAmountSatoshis: UInt64,
        outputAmountSatoshis: UInt64
    ) throws -> Host.MosaicReservationLease {
        let reference: Host.MosaicReservationReference
        let expiresAt: Date
        if isLocal {
            reference = .init(
                identifier: UUID(
                    uuid: (
                        0x30, 0x71, 0, 0, 0, 0, 0, 0,
                        0, 0, 0, 0, 0, 0, 0, 0x71
                    )
                ),
                generation: 0x71
            )
            expiresAt = Date(
                timeIntervalSince1970:
                    TimeInterval(manifest.core.deadlines.walletReservation)
            )
        } else {
            reference = .init(
                identifier: UUID(
                    uuid: (
                        0, 0, 0, 0, 0, 0, 0, 0,
                        0, 0, 0, 0, 0, 0, 0,
                        UInt8(contributorIndex + 1)
                    )
                ),
                generation: 1
            )
            expiresAt = Date(timeIntervalSince1970: 1_900_000_000)
        }
        return try .init(
            reference: reference,
            expiresAt: expiresAt,
            participantReservation: .init(
                inputs: [
                    .init(
                        outpointTransactionHashBytes: Array(
                            OpalCrypto.Hashing.hash256(
                                previousTransaction
                            ).reversed()
                        ),
                        outpointIndex: 0,
                        amountSatoshis: inputAmountSatoshis,
                        lockingScriptBytes: lockingScript(signingKey),
                        publicKey: Array(
                            signingKey.publicKey.compressedRepresentation
                        )
                    ),
                ],
                outputs: [
                    .init(
                        lockingScriptBytes:
                            lockingScript(outputSigningKey),
                        amountSatoshis: outputAmountSatoshis
                    ),
                ]
            )
        )
    }

    private func previousTransaction(
        discriminator: Int,
        amountSatoshis: UInt64,
        lockingScript: [UInt8]
    ) throws -> Data {
        let transaction = OpalFusion.Execution.BCHTransaction(
            version: 2,
            inputs: [
                .init(
                    previousTransactionHashLittleEndian:
                        [UInt8](repeating: 0, count: 32),
                    previousOutputIndex: UInt32.max,
                    unlockingScript: Array(
                        scalarBytes(discriminator + 1).suffix(4)
                    ),
                    sequence: UInt32.max
                ),
            ],
            outputs: [
                .init(
                    amountSatoshis: amountSatoshis,
                    lockingScript: lockingScript
                ),
            ],
            lockTime: UInt32(discriminator)
        )
        return Data(try transaction.serialize())
    }

    private func walletSigningKey(
        usage: UInt32
    ) throws -> OpalCrypto.Secp256k1.SigningKey {
        let mnemonic = try OpalCrypto.Key.Mnemonic(
            phrase: "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about"
        )
        let root = try OpalCrypto.Key.ExtendedPrivate.root(
            seed: mnemonic.deriveSeed()
        )
        let hardened: UInt32 = 0x8000_0000
        return try root.derived(indices: [
            hardened | 44,
            hardened | 145,
            hardened,
            usage,
            0,
        ]).signingKey
    }

    private func lockingScript(
        _ key: OpalCrypto.Secp256k1.SigningKey
    ) -> [UInt8] {
        let publicKey = Array(key.publicKey.compressedRepresentation)
        return [0x76, 0xA9, 0x14]
            + OpalFusion.Execution.ProtocolPrimitives.hash160(publicKey)
            + [0x88, 0xAC]
    }

    private func deterministicFixtureRecoveryState(
        binding source: OpalCrypto.RSABSSA.BlindRequest.RecoveryState,
        discriminator: Int
    ) throws -> OpalCrypto.RSABSSA.BlindRequest.RecoveryState {
        // Preserve the version, verification-key identifier, and message digest
        // from the securely generated probe. Only this test target replaces the
        // randomized material, so production request construction stays random.
        var raw = Data(source.rawRepresentation.prefix(1 + 32 + 32))
        func derivedBytes(_ lane: UInt8) -> Data {
            var input = Data(
                "opal-wallet-g3-blind-request-\(discriminator)".utf8
            )
            input.append(lane)
            return OpalCrypto.Hashing.sha256(input)
        }
        raw.append(derivedBytes(0))
        let salt = derivedBytes(1) + derivedBytes(2)
        raw.append(contentsOf: salt.prefix(48))
        raw.append(Data(repeating: 0, count: 255))
        raw.append(1)
        return try .init(rawRepresentation: raw)
    }

    private func signingKey(
        seed: Int
    ) throws -> OpalCrypto.Secp256k1.SigningKey {
        try .init(rawRepresentation: scalarBytes(seed))
    }

    private func privateKey(
        seed: Int
    ) throws -> OpalCrypto.Secp256k1.PrivateKey {
        try .init(rawRepresentation: scalarBytes(seed))
    }

    private func scalarBytes(_ scalar: Int) -> Data {
        precondition(scalar > 0 && scalar <= Int(UInt32.max))
        var value = UInt32(scalar).bigEndian
        var result = Data(repeating: 0, count: 28)
        withUnsafeBytes(of: &value) { result.append(contentsOf: $0) }
        return result
    }

    private func scalar(
        for key: OpalCrypto.Secp256k1.SigningKey
    ) throws -> UInt8 {
        for scalar in UInt8(1) ... UInt8.max {
            if try signingKey(seed: Int(scalar)).bip340VerificationKey
                == key.bip340VerificationKey {
                return scalar
            }
        }
        throw GeneratorFailure.scalarUnavailable
    }

    private func makeSecondRSASigningKey()
        throws -> OpalCrypto.RSABSSA.SigningKey {
        guard let data = Data(
            base64Encoded: secondPrivateKeyDERBase64,
            options: .ignoreUnknownCharacters
        ) else {
            throw GeneratorFailure.keyImportFailed
        }
        let attributes: [CFString: Any] = [
            kSecAttrKeyType: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass: kSecAttrKeyClassPrivate,
            kSecAttrKeySizeInBits: 2_048,
        ]
        var error: Unmanaged<CFError>?
        guard let key = SecKeyCreateWithData(
            data as CFData,
            attributes as CFDictionary,
            &error
        ) else {
            if let error { throw error.takeRetainedValue() }
            throw GeneratorFailure.keyImportFailed
        }
        return try OpalCrypto.RSABSSA.SigningKey(
            appOwnedSecurityKey: key
        )
    }

    private func compress(_ data: Data) throws -> Data {
        let source = [UInt8](data)
        var destination = [UInt8](repeating: 0, count: source.count * 2)
        let destinationCount = destination.count
        let count = source.withUnsafeBytes { sourceBuffer in
            destination.withUnsafeMutableBytes { destinationBuffer in
                compression_encode_buffer(
                    destinationBuffer.bindMemory(to: UInt8.self).baseAddress!,
                    destinationCount,
                    sourceBuffer.bindMemory(to: UInt8.self).baseAddress!,
                    source.count,
                    nil,
                    COMPRESSION_LZFSE
                )
            }
        }
        guard count > 0 else { throw GeneratorFailure.compressionFailed }
        return Data(destination.prefix(count))
    }

    // Security.framework-generated, nonpersistent RSA-2048 key. Test-only and
    // intentionally committed solely to reproduce the second purpose lane.
    private let secondPrivateKeyDERBase64 = """
    MIIEowIBAAKCAQEAw/YKKZpNPju5U3rxupTwGb6SbRmKuDfFlIKrTOUHss7O8LOX
    DhQ/7fO9z8HOJ2bvXAc+i70GCrPAJnMufuHcdIou19Uiq9gOCfxlJjHEnxFs4ZvJ
    nLwAsD5kcfatkzmdrQVjSGXBHNvOWp5s1kA7iA70jjHSt4EpyuC5KnXYfGS4MS0a
    bFxGb1iPZ6lbvgQ0nQp0rVRGWDvP5ZJQ4XKGttRkfb5GAxTtR5S7iyYtAnxwvu4M
    Qc+1+FYzQOQZD6p9p0DN9TBbsRYKz9nrlYb7en52OwLr4vlwnOIAGzmWkt+OQVjC
    8ab0xtXa7uSe16hErUn4r64hTsZktc7nNh+VuQIDAQABAoIBACjPyCQL98RbSeih
    9VAnjq29697+784YB3U7lZOJK4ZI3f5xWKdc/kd/eOuY8GdyX61p8NPHhUebUgxv
    9qIERhabZNAcmoDxmVLpFuPSf6GlTmjaOi4DVZ1fESpO9q1v1W/gbGH6lzJ8cMic
    sAwbCor2mmY26CzBoMOY89ds/a5CKdeUNN6Eeni/AiGdvhZDj1ru4orBc0s5TvKV
    lTv+YTTsQZL6sxtYtfrW6GqEKCXjCdJ08ww2yXVoLBrvoP77GfwScZA08AIZAU/b
    JAKdiEt7IW25SQExPm3RQlD6BfCf0ZCjH7l6Wx2eGmFFB4nDDvMEW5sLITEZLiQV
    qAJpUGUCgYEA+wV7PYnbHiQs7KI35H2oSLe0O9VnoTWYRFX3gv67JOgyiWdcypdc
    FUjC3Ki2NZqjsC3zynMwGIOfg2W9zXPklkwY61gZqurCMlXXiPuYeMU6DIg7X3wJ
    psvkvLIXhSGYgG8IGik4n8koe3Dc16wgfRDBOcZRWB8eCL6cMKLoJxMCgYEAx9j/
    tdvbv7TLg4y1djNxXd3UdZ6WbErIt1uto3yA7gVfSBe1E2Y/rJVzcsk396rbs82Q
    RsY+ILTY3pM5ulA9strbZ7/76/fEmUWKWX2QAEKap4oaata3rXmXqOnZS+4fKBJC
    jEzT5zGu8tUDR7otTnJT15/YFUZYari5z4Ad7YMCgYBax7ezIKjatLB+f4gBHSR/
    79fBj8LjfTNs+z4A5MifZ03nfTcEmUqW8/JsxKLord0muOeivpeVNfy5E1FZ/OCd
    LjYQ3pKhyjai54KEKqEQhBsjLx1xwbTn2nMFfs6cufKh+AWRGHk+6Au44K8tXDV/
    pVCL6Vm/qbk95lksCa41ewKBgFRRjxooyB+rZU58mLdlXwiOpqx1m9vW9ba/HJTk
    2/URGTFupzynIGhtqgcdNNrvIMFNEvl5fQ8JnpLSJUIhxtZmlrnAe8cEg9NzTrsR
    SieB8oSLtTesnlS3/7AJ8l+h+U1L3v4ZEDL0eG8GRtsFh0YY4J0SWPYo9vcYN3WA
    BaCHAoGBAOxyIFVs+OiV3LFB05/XGvWRXku8lUq8ztGIWSkIdG9o9eEaNYGJkkRr
    jU4TGuQbE7FpjKwNhBPTkVzJjBkxJKGAnku/wOGnL6qLXszYM0FgZEYT7szjFUTu
    FOvKrMK8V1Jy7PjDyI0CnSLGU7S+xyYekMb41H8R3eVz3KvNzPyK
    """
}
#endif

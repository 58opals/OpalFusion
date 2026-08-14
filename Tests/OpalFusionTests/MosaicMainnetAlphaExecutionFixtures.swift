// MosaicMainnetAlphaExecutionFixtures.swift

import Foundation
import OpalCrypto
@testable import OpalFusion

enum MosaicMainnetAlphaExecutionFixtures {
    typealias Alpha = OpalFusion.Mosaic.OpalMainnetAlpha
    typealias Attempt = OpalFusion.Mosaic.Attempt
    typealias Fixture = MosaicMainnetAlphaAdmissionLedgerFixtures
    typealias Host = OpalFusion.Host
    typealias Session = Alpha.RuntimeSession

    struct Outpoint: Hashable, Sendable {
        let transactionHash: [UInt8]
        let outputIndex: UInt32

        init(transactionHash: [UInt8], outputIndex: UInt32) {
            self.transactionHash = transactionHash
            self.outputIndex = outputIndex
        }

        init(_ input: Host.ParticipantInput) {
            transactionHash = input.outpointTransactionHashBytes
            outputIndex = input.outpointIndex
        }
    }

    struct PreviousOutputSource: Host.MosaicPreviousOutputSource {
        enum SourceError: Error {
            case missingOutput
        }

        let inputsByOutpoint: [Outpoint: Host.ParticipantInput]

        func resolvePreviousOutputs(
            for requests: [Host.MosaicPreviousOutputRequest]
        ) async throws -> [Host.MosaicPreviousOutput] {
            try requests.map { request in
                guard let input = inputsByOutpoint[
                    Outpoint(
                        transactionHash: request.transactionHashBytes,
                        outputIndex: request.outputIndex
                    )
                ] else {
                    throw SourceError.missingOutput
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

    struct Prepared {
        let admission: Fixture.Harness
        let session: Session
        let materialized: MosaicMainnetAlphaFixtures.MaterializedPreparation
        let localMaterial: Alpha.LocalContributionMaterial
        let localAuthorizationResponseSet: Alpha.AuthorizationResponseSet
        let localAuthorizationValidation:
            Alpha.AuthorizationResponseSetMaterialValidation
        let acknowledgementSet: Alpha.PreSignAcknowledgementSet
        let previousOutputSource: PreviousOutputSource
        let previousOutputs: Alpha.PreviousOutputResolver.Validation
        let signingRequest: Host.MosaicTransactionSigningRequest
        let localFinalizedTransaction: Host.FinalizedTransaction
        let signatureSet: Alpha.BCHSignatureSet
        let completePayload: Alpha.CompleteTransactionPayload
    }

    struct Completion {
        let previousOutputSource: PreviousOutputSource
        let previousOutputs: Alpha.PreviousOutputResolver.Validation
        let signatureSet: Alpha.BCHSignatureSet
        let completePayload: Alpha.CompleteTransactionPayload
    }

    static func prepare() async throws -> Prepared {
        let componentEvaluator = try MosaicMainnetAlphaFixtures
            .authorizationEvaluator()
        let bchEvaluator = try MosaicMainnetAlphaFixtures
            .bchSignatureAuthorizationEvaluator()
        let componentVerificationKey = try require(
            componentEvaluator.verificationKey
        )
        let bchVerificationKey = try require(bchEvaluator.verificationKey)
        let admission = try Fixture.makeHarness(
            localRole: .contributor,
            verificationKey: componentVerificationKey,
            bchSignatureVerificationKey: bchVerificationKey
        )
        let session = try Session(
            validatedAttempt: Fixture.makeValidatedAttempt(
                election: admission.election
            ),
            attemptIdentifier: admission.attemptIdentifier,
            generationIdentifier: admission.generationIdentifier,
            materialIdentifier: admission.materialIdentifier,
            localControlIdentity: admission.localControlIdentity,
            proposalValidation: admission.proposalValidation
        )
        let materialized = try MosaicMainnetAlphaFixtures
            .makeMaterializedPreparation(
                election: admission.election,
                manifest: admission.manifest,
                attemptIdentifier: admission.attemptIdentifier,
                generationIdentifier: admission.generationIdentifier,
                localContributor: admission.localControlIdentity,
                localMaterialIdentifier: admission.materialIdentifier
            )
        let localMaterial = try require(
            materialized.materials[admission.localControlIdentity]
        )
        let localResponseSet = try authorizationResponseSet(
            material: localMaterial,
            componentEvaluator: componentEvaluator,
            bchEvaluator: bchEvaluator
        )
        let authorizationValidation = try Alpha
            .AuthorizationResponseSetMaterialValidation(
                validating: localResponseSet,
                material: localMaterial
            )
        let transcript = materialized.prepared.transcript
        let publication = try Session.ReservationPublicationValidation(
            validating: .init(
                attemptIdentifier: admission.attemptIdentifier,
                generationIdentifier: admission.generationIdentifier,
                materialIdentifier: admission.materialIdentifier,
                contributor: admission.localControlIdentity,
                manifest: admission.manifest,
                reservationLease: localMaterial.reservationLease,
                playerCommit: localMaterial.playerCommit
            ),
            using: localMaterial
        )
        let transcriptInclusion = try OpalFusion.Mosaic.LocalAttempt
            .TranscriptInclusionValidation(
                attemptIdentifier: admission.attemptIdentifier,
                generationIdentifier: admission.generationIdentifier,
                contributor: admission.localControlIdentity,
                materialIdentifier: admission.materialIdentifier,
                transcript: transcript,
                using: localMaterial
            )
        let acknowledgementSet = try makeAcknowledgementSet(
            admission: admission,
            transcript: transcript
        )
        let completion = try await makeCompletion(
            admission: admission,
            materialized: materialized
        )
        let signingRequest = try Alpha.SigningRequestBuilder.build(
            context: session.context,
            reservationPublication: publication,
            transcriptInclusion: transcriptInclusion,
            acknowledgements: acknowledgementSet.submissions.map(\.validation),
            previousOutputs: completion.previousOutputs
        )
        var locallySignedTransaction = transcript.transaction
        for inputIndex in signingRequest.localInputIndices {
            let entry = completion.signatureSet.entries[inputIndex]
            locallySignedTransaction = try locallySignedTransaction
                .settingUnlockingScript(unlockingScript(for: entry), at: inputIndex)
        }
        let localFinalizedTransaction = Host.FinalizedTransaction(
            signedFusionTransactionBytes: try locallySignedTransaction.serialize()
        )
        return .init(
            admission: admission,
            session: session,
            materialized: materialized,
            localMaterial: localMaterial,
            localAuthorizationResponseSet: localResponseSet,
            localAuthorizationValidation: authorizationValidation,
            acknowledgementSet: acknowledgementSet,
            previousOutputSource: completion.previousOutputSource,
            previousOutputs: completion.previousOutputs,
            signingRequest: signingRequest,
            localFinalizedTransaction: localFinalizedTransaction,
            signatureSet: completion.signatureSet,
            completePayload: completion.completePayload
        )
    }

    static func makeCompletion(
        admission: Fixture.Harness,
        materialized: MosaicMainnetAlphaFixtures.MaterializedPreparation
    ) async throws -> Completion {
        let transcript = materialized.prepared.transcript
        let source = PreviousOutputSource(
            inputsByOutpoint: Dictionary(
                uniqueKeysWithValues: materialized.materials.values.flatMap {
                    material in
                    material.reservationLease.participantReservation.inputs.map {
                        (Outpoint($0), $0)
                    }
                }
            )
        )
        let previousOutputs = try await Alpha.PreviousOutputResolver(
            source: source
        ).resolve(for: transcript)
        let signatureSet = try makeSignatureSet(
            admission: admission,
            materialized: materialized,
            previousOutputs: previousOutputs
        )
        let completeTransaction = try Alpha.CompleteTransactionAssembler
            .assemble(
                transcript: transcript,
                signatureSet: signatureSet,
                spentInputs: previousOutputs.spentInputs
            )
        let completePayload = try Alpha.CompleteTransactionPayload(
            roundIdentifier: admission.manifest.core.roundIdentifier,
            transcriptRoot: transcript.transcriptRoot.validatedBytes,
            completeTransaction: completeTransaction
        )
        return .init(
            previousOutputSource: source,
            previousOutputs: previousOutputs,
            signatureSet: signatureSet,
            completePayload: completePayload
        )
    }

    static func reservationRequest(
        for eligibility: Alpha.ReservationCoordinator.ReservationEligibility,
        expiresAt: Date
    ) throws -> Host.MosaicReservationRequest {
        let manifest = eligibility.manifest
        return try .init(
            attemptIdentifier: eligibility.context.attemptIdentifier.validatedBytes,
            networkGenesisHash: manifest.core.networkGenesisHash,
            roundIdentifier: manifest.core.roundIdentifier,
            expiresAt: expiresAt,
            componentCount: Int(manifest.core.componentCount),
            feeRateSatoshisPerByte: manifest.core.feeRateSatoshisPerByte,
            minimumExcessFeeSatoshis:
                manifest.core.minimumExcessFeeSatoshis,
            maximumExcessFeeSatoshis:
                manifest.core.maximumExcessFeeSatoshis,
            requiredExcessFeeSatoshis: try Alpha.ContributionFeePolicy
                .requiredExcessFeeSatoshis(
                    for: eligibility.context.localControlIdentity,
                    in: eligibility.context.roster
                ),
            transactionProfileIdentifier:
                manifest.core.transactionProfileIdentifier
        )
    }

    private static func authorizationResponseSet(
        material: Alpha.LocalContributionMaterial,
        componentEvaluator: OpalFusion.Mosaic.OpalV0.AuthorizationEvaluator,
        bchEvaluator: OpalFusion.Mosaic.OpalV0.AuthorizationEvaluator
    ) throws -> Alpha.AuthorizationResponseSet {
        try .init(
            roundIdentifier: material.manifest.core.roundIdentifier,
            contributor: material.contributor,
            playerCommitDigest: material.playerCommit.digest,
            componentAuthorizationResponses: try material.slots.map { slot in
                try .init(
                    slot: slot.slot,
                    blindSignature: componentEvaluator.evaluate(
                        slot.componentAuthorizationRequest.blindedMessage
                    )
                )
            },
            bchSignatureAuthorizationResponses: try material.slots.map { slot in
                try .init(
                    slot: slot.slot,
                    blindSignature: bchEvaluator.evaluate(
                        slot.bchSignatureAuthorizationRequest.blindedMessage
                    )
                )
            }
        )
    }

    private static func makeAcknowledgementSet(
        admission: Fixture.Harness,
        transcript: OpalFusion.Mosaic.OpalV0.UnsignedTransactionTranscript
    ) throws -> Alpha.PreSignAcknowledgementSet {
        let acknowledgements = MosaicManifestSignatureFixtures
            .transcriptAcknowledgements(
                for: admission.election.result.roster.contributors,
                binding: admission.manifest.binding,
                transcriptRoot: transcript.transcriptRoot,
                profile: .opalMainnetAlpha
            )
        let submissions = try acknowledgements.sorted {
            $0.contributor.validatedBytes.lexicographicallyPrecedes(
                $1.contributor.validatedBytes
            )
        }.map {
            try Alpha.PreSignAcknowledgementSubmission(
                contributor: $0.contributor,
                roundIdentifier: $0.roundIdentifier,
                transcriptRoot: $0.transcriptRoot,
                signature: $0.rawRepresentation
            )
        }
        return try .init(
            roundIdentifier: admission.manifest.core.roundIdentifier,
            transcriptRoot: transcript.transcriptRoot.validatedBytes,
            roster: admission.election.result.roster,
            submissions: submissions
        )
    }

    private static func makeSignatureSet(
        admission: Fixture.Harness,
        materialized: MosaicMainnetAlphaFixtures.MaterializedPreparation,
        previousOutputs: Alpha.PreviousOutputResolver.Validation
    ) throws -> Alpha.BCHSignatureSet {
        var signingKeysByOutpoint: [Outpoint: OpalCrypto.Secp256k1.SigningKey]
            = [:]
        for (contributorIndex, contributor) in admission.manifest.core
            .orderedContributors.enumerated() {
            let material = try require(materialized.materials[contributor])
            let key = try OpalCrypto.Secp256k1.SigningKey(
                rawRepresentation: scalarBytes(10_000 + contributorIndex)
            )
            for input in material.reservationLease.participantReservation.inputs {
                signingKeysByOutpoint[Outpoint(input)] = key
            }
        }
        let transcript = materialized.prepared.transcript
        let entries = try previousOutputs.spentInputs.enumerated().map {
            inputIndex, input in
            let key = try require(signingKeysByOutpoint[Outpoint(input)])
            let digest = try transcript.transaction.signatureHash(
                forInputAt: inputIndex,
                lockingScript: input.lockingScriptBytes,
                amountSatoshis: input.amountSatoshis,
                sighashType: 0x41
            )
            let signature = try key.signSchnorr(
                digest: .init(rawRepresentation: Data(digest))
            )
            return try Alpha.BCHSignatureEntry(
                inputIndex: UInt32(inputIndex),
                signature: [UInt8](signature.rawRepresentation),
                publicKey: [UInt8](key.publicKey.compressedRepresentation)
            )
        }
        return try .init(
            roundIdentifier: admission.manifest.core.roundIdentifier,
            transcriptRoot: transcript.transcriptRoot.validatedBytes,
            entries: entries,
            expectedInputCount: transcript.transaction.inputs.count
        )
    }

    static func unlockingScript(for entry: Alpha.BCHSignatureEntry) -> [UInt8] {
        [0x41] + entry.signature + [0x41, 0x21] + entry.publicKey
    }

    private static func scalarBytes(_ scalar: Int) -> Data {
        precondition(scalar > 0)
        var value = UInt32(scalar).bigEndian
        var result = Data(repeating: 0, count: 28)
        withUnsafeBytes(of: &value) { result.append(contentsOf: $0) }
        return result
    }

    private static func require<Value>(_ value: Value?) throws -> Value {
        guard let value else {
            throw FixtureError.missingValue
        }
        return value
    }

    private enum FixtureError: Error {
        case missingValue
    }
}

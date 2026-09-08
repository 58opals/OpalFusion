// MosaicMainnetAlphaExecutionFixtures~Preparation.swift

import OpalCrypto
@testable import OpalFusion

extension MosaicMainnetAlphaExecutionFixtures {
    private static let preparationRepository = MosaicFixtureRepository<
        MosaicMainnetAlphaExecutionPreparationData
    >()

    static func prepare() async throws -> Prepared {
        let data = try await preparationRepository.load {
            try await makePreparationData()
        }
        let admission = try Fixture.makeHarness(
            localRole: .contributor,
            verificationKey: require(
                MosaicMainnetAlphaFixtures.authorizationEvaluator()
                    .verificationKey
            ),
            bchSignatureVerificationKey: require(
                MosaicMainnetAlphaFixtures.bchSignatureAuthorizationEvaluator()
                    .verificationKey
            )
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
        return .init(
            admission: admission,
            session: session,
            materialized: data.materialized,
            localMaterial: data.localMaterial,
            localAuthorizationResponseSet: data.localAuthorizationResponseSet,
            localAuthorizationValidation: data.localAuthorizationValidation,
            acknowledgementSet: data.acknowledgementSet,
            previousOutputSource: data.previousOutputSource,
            previousOutputs: data.previousOutputs,
            signingRequest: data.signingRequest,
            localFinalizedTransaction: data.localFinalizedTransaction,
            signatureSet: data.signatureSet,
            completePayload: data.completePayload
        )
    }

    private static func makePreparationData() async throws
        -> MosaicMainnetAlphaExecutionPreparationData {
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

}

// MosaicMainnetAlphaFixtures~MaterialPreparation.swift

@testable import OpalFusion

extension MosaicMainnetAlphaFixtures {
    static func makeMaterializedPreparation(
        election: MosaicRoleElectionFixtures.Election,
        manifest: Alpha.RoundManifest,
        attemptIdentifier: OpalFusion.Mosaic.LocalAttempt.AttemptIdentifier,
        generationIdentifier: OpalFusion.Mosaic.LocalAttempt.GenerationIdentifier,
        localContributor: Attempt.ControlIdentity,
        localMaterialIdentifier:
            OpalFusion.Mosaic.LocalAttempt.MaterialIdentifier
    ) throws -> MaterializedPreparation {
        let key = MosaicMainnetAlphaMaterialKeyData(
            manifestBytes: manifest.canonicalBytes,
            attemptIdentifier: attemptIdentifier.validatedBytes,
            generationIdentifier: generationIdentifier.opaqueBytes,
            localContributor: localContributor.validatedBytes,
            localMaterialIdentifier: localMaterialIdentifier.opaqueBytes
        )
        return try MosaicMainnetAlphaMaterialRepository.load(for: key) {
            try makeFreshMaterializedPreparation(
                election: election,
                manifest: manifest,
                attemptIdentifier: attemptIdentifier,
                generationIdentifier: generationIdentifier,
                localContributor: localContributor,
                localMaterialIdentifier: localMaterialIdentifier
            )
        }
    }

    private static func makeFreshMaterializedPreparation(
        election: MosaicRoleElectionFixtures.Election,
        manifest: Alpha.RoundManifest,
        attemptIdentifier: OpalFusion.Mosaic.LocalAttempt.AttemptIdentifier,
        generationIdentifier: OpalFusion.Mosaic.LocalAttempt.GenerationIdentifier,
        localContributor: Attempt.ControlIdentity,
        localMaterialIdentifier:
            OpalFusion.Mosaic.LocalAttempt.MaterialIdentifier
    ) throws -> MaterializedPreparation {
        let contributors = manifest.core.orderedContributors
        let materials = try contributors.enumerated().map {
            contributorIndex, contributor in
            let materialIdentifier = contributor == localContributor
                ? localMaterialIdentifier
                : OpalFusion.Mosaic.LocalAttempt.MaterialIdentifier(
                    opaqueBytes: MosaicUnsignedTransactionTranscriptFixtures
                        .indexedDigest(52_000 + contributorIndex)
                )
            return try makeLocalContributionMaterial(
                manifest: manifest,
                contributor: contributor,
                contributorIndex: contributorIndex,
                attemptIdentifier: attemptIdentifier,
                generationIdentifier: generationIdentifier,
                materialIdentifier: materialIdentifier
            )
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
        return .init(
            prepared: .init(
                commitmentSet: commitmentSet,
                componentSet: componentSet,
                commitmentValidation: commitmentValidation,
                transcript: transcript
            ),
            materials: Dictionary(
                uniqueKeysWithValues: materials.map { ($0.contributor, $0) }
            )
        )
    }

}

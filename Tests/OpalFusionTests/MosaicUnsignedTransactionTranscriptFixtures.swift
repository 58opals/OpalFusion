// MosaicUnsignedTransactionTranscriptFixtures.swift

@testable import OpalFusion

enum MosaicUnsignedTransactionTranscriptFixtures {
    typealias Attempt = OpalFusion.Mosaic.Attempt
    typealias LocalAttempt = OpalFusion.Mosaic.LocalAttempt
    typealias OpalV0 = OpalFusion.Mosaic.OpalV0

    struct Prepared: Sendable, Equatable {
        let commitmentSet: OpalV0.CommitmentSet
        let componentSet: OpalV0.ComponentSet
        let commitmentValidation: Attempt.CommitmentSetValidation
        let transcript: OpalV0.UnsignedTransactionTranscript
    }

    static func prepare(
        roster: Attempt.Roster,
        manifest: Attempt.ManifestBinding,
        profile: OpalFusion.Mosaic.Profile = .opalV0,
        componentSaltOffset: Int = 0
    ) throws -> Prepared {
        let commitmentSet = try makeCommitmentSet(
            contributorCount: roster.contributors.count,
            profile: profile
        )
        let componentSet = try makeBalancedComponentSet(
            contributorCount: roster.contributors.count,
            profile: profile,
            saltOffset: componentSaltOffset
        )
        let commitmentValidation = try Attempt.CommitmentSetValidation(
            profile: profile,
            roster: roster,
            commitmentSet: commitmentSet
        )
        let transcript = try OpalV0.UnsignedTransactionTranscript(
            profile: profile,
            roster: roster,
            manifest: manifest,
            commitmentSet: commitmentValidation,
            componentSet: componentSet
        )
        return .init(
            commitmentSet: commitmentSet,
            componentSet: componentSet,
            commitmentValidation: commitmentValidation,
            transcript: transcript
        )
    }

    static func makeCommitmentSet(
        contributorCount: Int,
        profile: OpalFusion.Mosaic.Profile = .opalV0
    ) throws -> OpalV0.CommitmentSet {
        let memberCount = contributorCount
            * OpalV0.componentAuthorizationCountPerContributor
        return try .init(
            profile: profile,
            commitments: (0 ..< memberCount).map {
                try MosaicOpalV0WireContractValidator.makeCommitment(index: $0)
            }
        )
    }

    static func makeBalancedComponentSet(
        contributorCount: Int,
        profile: OpalFusion.Mosaic.Profile = .opalV0,
        saltOffset: Int = 0
    ) throws -> OpalV0.ComponentSet {
        let memberCount = contributorCount
            * OpalV0.componentAuthorizationCountPerContributor
        let outputAmount: UInt64 = 10_000
        let estimatedFinalSignedByteCount: UInt64 = 185
        var components: [OpalV0.Component] = [
            try .init(
                saltCommitment: indexedDigest(saltOffset),
                payload: .input(
                    try .init(
                        previousTransactionHash: indexedDigest(1_000),
                        outputIndex: 3,
                        amountSatoshis: outputAmount
                            + estimatedFinalSignedByteCount
                    )
                )
            ),
            try .init(
                saltCommitment: indexedDigest(saltOffset + 1),
                payload: .output(
                    try .init(
                        lockingScript: p2pkhLockingScript(fill: 0x66),
                        amountSatoshis: outputAmount
                    )
                )
            ),
        ]
        components.append(
            contentsOf: try (2 ..< memberCount).map { index in
                try OpalV0.Component(
                    saltCommitment: indexedDigest(saltOffset + index),
                    payload: .blank
                )
            }
        )
        return try .init(profile: profile, components: components)
    }

    static func indexedDigest(_ index: Int) -> [UInt8] {
        MosaicOpalV0WireContractValidator.indexedDigest(index)
    }

    static func p2pkhLockingScript(fill: UInt8) -> [UInt8] {
        MosaicOpalV0WireContractValidator.p2pkhLockingScript(fill: fill)
    }

    static func makeTranscriptInclusionValidation(
        attemptIdentifier: LocalAttempt.AttemptIdentifier,
        generationIdentifier: LocalAttempt.GenerationIdentifier,
        contributor: Attempt.ControlIdentity,
        materialIdentifier: LocalAttempt.MaterialIdentifier,
        transcript: OpalV0.UnsignedTransactionTranscript
    ) throws -> LocalAttempt.TranscriptInclusionValidation {
        try .init(
            attemptIdentifier: attemptIdentifier,
            generationIdentifier: generationIdentifier,
            contributor: contributor,
            materialIdentifier: materialIdentifier,
            transcript: transcript,
            using: ExactTranscriptInclusionValidator(
                attemptIdentifier: attemptIdentifier,
                generationIdentifier: generationIdentifier,
                contributor: contributor,
                materialIdentifier: materialIdentifier,
                transcript: transcript
            )
        )
    }

    private struct ExactTranscriptInclusionValidator:
        LocalAttempt.TranscriptInclusionValidating
    {
        struct Rejection: Error {}

        let attemptIdentifier: LocalAttempt.AttemptIdentifier
        let generationIdentifier: LocalAttempt.GenerationIdentifier
        let contributor: Attempt.ControlIdentity
        let materialIdentifier: LocalAttempt.MaterialIdentifier
        let transcript: OpalV0.UnsignedTransactionTranscript

        func validateCompleteInclusion(
            attemptIdentifier: LocalAttempt.AttemptIdentifier,
            generationIdentifier: LocalAttempt.GenerationIdentifier,
            contributor: Attempt.ControlIdentity,
            materialIdentifier: LocalAttempt.MaterialIdentifier,
            transcript: OpalV0.UnsignedTransactionTranscript
        ) throws {
            guard attemptIdentifier == self.attemptIdentifier,
                  generationIdentifier == self.generationIdentifier,
                  contributor == self.contributor,
                  materialIdentifier == self.materialIdentifier,
                  transcript == self.transcript else {
                throw Rejection()
            }
        }
    }
}

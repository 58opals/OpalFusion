// MosaicUnsignedTransactionTranscriptFixtures.swift

import Foundation
import OpalCrypto
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

    struct MainnetCommitmentGroup: Sendable, Equatable {
        let commitments: [OpalV0.ComponentCommitment]
        let excessFeeSatoshis: UInt64
        let pedersenTotalNonce: [UInt8]
    }

    private static let sixContributorMainnetCommitmentGroups = try!
        buildMainnetCommitmentGroups(contributorCount: 6)
    private static let sevenContributorMainnetCommitmentGroups = try!
        buildMainnetCommitmentGroups(contributorCount: 7)
    private static let eightContributorMainnetCommitmentGroups = try!
        buildMainnetCommitmentGroups(contributorCount: 8)

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
        if profile == .opalMainnetAlpha {
            return try .init(
                profile: profile,
                commitments: makeMainnetCommitmentGroups(
                    contributorCount: contributorCount
                ).flatMap(\.commitments)
            )
        }
        let memberCount = contributorCount
            * OpalV0.componentAuthorizationCountPerContributor
        return try .init(
            profile: profile,
            commitments: (0 ..< memberCount).map {
                try MosaicOpalV0WireContractValidator.makeCommitment(index: $0)
            }
        )
    }

    static func makeMainnetCommitmentGroups(
        contributorCount: Int
    ) throws -> [MainnetCommitmentGroup] {
        switch contributorCount {
        case 6:
            return sixContributorMainnetCommitmentGroups
        case 7:
            return sevenContributorMainnetCommitmentGroups
        case 8:
            return eightContributorMainnetCommitmentGroups
        default:
            return try buildMainnetCommitmentGroups(
                contributorCount: contributorCount
            )
        }
    }

    private static func buildMainnetCommitmentGroups(
        contributorCount: Int
    ) throws -> [MainnetCommitmentGroup] {
        let setup = try OpalCrypto.Pedersen.Setup()
        let slotCount = OpalV0.componentAuthorizationCountPerContributor
        let baseShare = OpalFusion.Mosaic.OpalMainnetAlpha
            .fixedTransactionOverheadByteCount / contributorCount
        let remainder = OpalFusion.Mosaic.OpalMainnetAlpha
            .fixedTransactionOverheadByteCount % contributorCount

        return try (0 ..< contributorCount).map { contributorIndex in
            let excessFeeSatoshis = UInt64(
                baseShare + (contributorIndex < remainder ? 1 : 0)
            )
            let pedersenCommitments = try (0 ..< slotCount).map { slot in
                let globalIndex = contributorIndex * slotCount + slot
                return try setup.commit(
                    amount: slot == 0 ? Int64(excessFeeSatoshis) : 0,
                    nonce: .init(
                        rawRepresentation: Data(
                            indexedDigest(40_000 + globalIndex)
                        )
                    )
                )
            }
            let combined = try setup.combine(pedersenCommitments)
            let commitments = try pedersenCommitments.enumerated().map {
                slot, pedersenCommitment in
                let globalIndex = contributorIndex * slotCount + slot
                return try OpalV0.ComponentCommitment(
                    saltedComponentDigest: indexedDigest(globalIndex),
                    amountCommitment: [UInt8](
                        pedersenCommitment.point.uncompressedRepresentation
                    ),
                    communicationPublicKey:
                        MosaicOpalV0WireContractValidator
                            .communicationKeys[globalIndex].compressed
                )
            }
            return .init(
                commitments: commitments,
                excessFeeSatoshis: excessFeeSatoshis,
                pedersenTotalNonce: [UInt8](combined.nonce.rawRepresentation)
            )
        }
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

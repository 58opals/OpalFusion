// MosaicMainnetAlphaExecutionFixtures~Authorization.swift

import OpalCrypto
@testable import OpalFusion

extension MosaicMainnetAlphaExecutionFixtures {
    static func authorizationResponseSet(
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

    static func makeAcknowledgementSet(
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

}

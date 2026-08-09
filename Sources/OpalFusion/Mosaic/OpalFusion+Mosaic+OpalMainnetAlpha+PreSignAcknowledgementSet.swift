// OpalFusion+Mosaic+OpalMainnetAlpha+PreSignAcknowledgementSet.swift

extension OpalFusion.Mosaic.OpalMainnetAlpha {
    /// The conductor-published, roster-complete contributor acknowledgement set.
    struct PreSignAcknowledgementSet: Sendable, Equatable {
        let roundIdentifier: [UInt8]
        let transcriptRoot: [UInt8]
        let submissions: [PreSignAcknowledgementSubmission]
        let canonicalBytes: [UInt8]
        let digest: [UInt8]

        init(
            roundIdentifier: [UInt8],
            transcriptRoot: [UInt8],
            roster: OpalFusion.Mosaic.Attempt.Roster,
            submissions: [PreSignAcknowledgementSubmission]
        ) throws {
            try RoleSeedValidator.validateFixed(
                roundIdentifier,
                field: .roundIdentifier
            )
            try RoleSeedValidator.validateFixed(
                transcriptRoot,
                field: .transcriptRoot
            )
            guard submissions.count == roster.contributors.count else {
                throw ContractError.invalidPreSignAcknowledgementCount(
                    expected: roster.contributors.count,
                    actual: submissions.count
                )
            }
            let expectedContributors = roster.contributors.sorted {
                $0.validatedBytes.lexicographicallyPrecedes($1.validatedBytes)
            }
            for (index, submission) in submissions.enumerated() {
                let acknowledgement = submission.acknowledgement
                guard acknowledgement.contributor == expectedContributors[index],
                      acknowledgement.contributor != roster.conductor else {
                    throw ContractError.invalidPreSignAcknowledgementContributor
                }
                guard acknowledgement.roundIdentifier == roundIdentifier,
                      acknowledgement.transcriptRoot == transcriptRoot,
                      submission.validation.profile == .opalMainnetAlpha else {
                    throw ContractError.aggregateTranscriptMismatch
                }
            }

            let canonicalBytes = try CanonicalWireCodec
                .encodePreSignAcknowledgementSet(
                    roundIdentifier: roundIdentifier,
                    transcriptRoot: transcriptRoot,
                    submissions: submissions
                )
            self.roundIdentifier = Array(roundIdentifier)
            self.transcriptRoot = Array(transcriptRoot)
            self.submissions = submissions
            self.canonicalBytes = canonicalBytes
            self.digest = RoleSeedValidator.hash(
                domainSuffix: "pre-sign-acknowledgement-set",
                fields: [canonicalBytes]
            )
        }
    }
}

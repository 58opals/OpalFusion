// OpalFusion+Mosaic+Attempt+CommitmentSetValidation.swift

extension OpalFusion.Mosaic.Attempt {
    /// One profile- and roster-bound canonical commitment set with exact aggregate cardinality.
    struct CommitmentSetValidation: Sendable, Equatable {
        enum ValidationError: Error, Sendable, Equatable {
            case unsupportedProfile(OpalFusion.Mosaic.Profile)
            case profileMismatch(
                expected: OpalFusion.Mosaic.Profile,
                actual: OpalFusion.Mosaic.Profile
            )
            case invalidMemberCount(expected: Int, actual: Int)
        }

        let contributors: [ControlIdentity]
        let commitmentSet: OpalFusion.Mosaic.OpalV0.CommitmentSet

        var digest: [UInt8] {
            commitmentSet.digest
        }

        init(
            profile: OpalFusion.Mosaic.Profile,
            roster: Roster,
            commitmentSet: OpalFusion.Mosaic.OpalV0.CommitmentSet
        ) throws(ValidationError) {
            guard profile.supportsExecutableCore else {
                throw .unsupportedProfile(profile)
            }
            guard commitmentSet.profile == profile else {
                throw .profileMismatch(
                    expected: profile,
                    actual: commitmentSet.profile
                )
            }

            let contributorCount = roster.contributors.count
            let expectedMemberCount = contributorCount
                * OpalFusion.Mosaic.OpalV0.componentAuthorizationCountPerContributor
            guard commitmentSet.commitments.count == expectedMemberCount else {
                throw .invalidMemberCount(
                    expected: expectedMemberCount,
                    actual: commitmentSet.commitments.count
                )
            }

            self.contributors = roster.contributors
            self.commitmentSet = commitmentSet
        }
    }
}

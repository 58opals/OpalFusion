// OpalFusion+Mosaic+RosterPolicy.swift

public extension OpalFusion.Mosaic {
    /// Fixed roster invariants for one Mosaic protocol profile.
    ///
    /// These values are protocol constants rather than wallet-tunable preferences.
    struct RosterPolicy: Sendable, Equatable {
        public let minimumContributorCount: Int
        public let targetContributorCount: Int
        public let conductorCount: Int
        public let maximumCandidateCount: Int
        public let componentCountPerContributor: Int

        public var minimumCandidateCount: Int {
            minimumContributorCount + conductorCount
        }

        public var targetCandidateCount: Int {
            targetContributorCount + conductorCount
        }

        /// The constants currently proposed by `Mosaic/1-draft.1`.
        public static let draft1 = Self(
            minimumContributorCount: 6,
            targetContributorCount: 8,
            conductorCount: 1,
            maximumCandidateCount: 9,
            componentCountPerContributor: 23
        )

        /// The fixed roster constants for `Mosaic/0-opal.1`.
        public static let opalV0 = Self(
            minimumContributorCount: 6,
            targetContributorCount: 8,
            conductorCount: 1,
            maximumCandidateCount: 9,
            componentCountPerContributor: 23
        )

        /// The fixed roster constants for `Mosaic/0-opal-mainnet-alpha.2`.
        public static let opalMainnetAlpha = Self(
            minimumContributorCount: 6,
            targetContributorCount: 8,
            conductorCount: 1,
            maximumCandidateCount: 9,
            componentCountPerContributor: 23
        )

        private init(
            minimumContributorCount: Int,
            targetContributorCount: Int,
            conductorCount: Int,
            maximumCandidateCount: Int,
            componentCountPerContributor: Int
        ) {
            self.minimumContributorCount = minimumContributorCount
            self.targetContributorCount = targetContributorCount
            self.conductorCount = conductorCount
            self.maximumCandidateCount = maximumCandidateCount
            self.componentCountPerContributor = componentCountPerContributor
        }
    }
}

// OpalFusion+Mosaic+OpalV0+CommitmentSet.swift

extension OpalFusion.Mosaic.OpalV0 {
    struct CommitmentSet: Sendable, Equatable {
        let profile: OpalFusion.Mosaic.Profile
        let commitments: [ComponentCommitment]
        let canonicalBytes: [UInt8]
        let digest: [UInt8]

        init(
            profile: OpalFusion.Mosaic.Profile = .opalV0,
            commitments: [ComponentCommitment]
        ) throws {
            guard profile.supportsExecutableCore else {
                throw WireContractError.unsupportedProfile(profile)
            }
            guard OpalFusion.Mosaic.OpalV0.isValidAggregateMemberCount(
                commitments.count
            ) else {
                throw WireContractError.invalidCommitmentSetCount(
                    actual: commitments.count
                )
            }

            let encodedMembers = try commitments.map {
                (
                    value: $0,
                    bytes: try CanonicalWireCodec.encodeComponentCommitment($0)
                )
            }.sorted { lhs, rhs in
                lhs.bytes.lexicographicallyPrecedes(rhs.bytes)
            }
            for index in encodedMembers.indices.dropFirst() {
                guard encodedMembers[index - 1].bytes != encodedMembers[index].bytes else {
                    throw WireContractError.duplicateCommitmentSetMember
                }
            }
            try OpalFusion.Mosaic.OpalV0.validateCommitmentFieldUniqueness(
                commitments
            )
            if profile == .opalMainnetAlpha {
                try OpalFusion.Mosaic.OpalV0
                    .validateMainnetCommunicationEventIdentityUniqueness(
                        commitments
                    )
            }

            let sortedCommitments = encodedMembers.map(\.value)
            var encoder = OpalFusion.Mosaic.CanonicalEncoder()
            try encoder.writeSortedSet(sortedCommitments) { encoder, commitment in
                try CanonicalWireCodec.writeComponentCommitment(
                    commitment,
                    to: &encoder
                )
            }
            let canonicalBytes = encoder.encodedBytes

            self.profile = profile
            self.commitments = sortedCommitments
            self.canonicalBytes = canonicalBytes
            self.digest = OpalFusion.Mosaic.OpalV0.aggregateDigest(
                profile: profile,
                domainSuffix: "commitment-set",
                canonicalBytes: canonicalBytes
            )
        }
    }
}

// MosaicOpalV0WireContractValidator+AggregateFragments.swift

@testable import OpalFusion
import Testing

extension MosaicOpalV0WireContractValidator {
    @Test("Aggregate fragments pin one deterministic envelope-sized partition")
    func validateAggregateFragmentGoldenVectors() throws {
        #expect(OpalV0.aggregateFragmentHeaderByteCount == 75)
        #expect(OpalV0.maximumAggregateFragmentBodyByteCount == 4_017)
        #expect(OpalV0.maximumAggregateDocumentByteCount == 23_924)
        #expect(OpalV0.maximumAggregateFragmentCount == 6)

        let commitmentSet = try Self.makeCommitmentSet()
        let commitmentFragments = try OpalV0.AggregateFragmenter.fragments(
            for: commitmentSet,
            roundIdentifier: Self.aggregateFragmentRoundIdentifier
        )
        let commitmentEncoded = try commitmentFragments.map(
            Codec.encodeAggregateFragment
        )

        #expect(commitmentFragments.count == 5)
        #expect(commitmentFragments.map(\.body.count) == [4_017, 4_017, 4_017, 4_017, 1_876])
        #expect(commitmentEncoded.map(\.count) == [4_092, 4_092, 4_092, 4_092, 1_951])
        #expect(commitmentFragments.flatMap(\.body) == commitmentSet.canonicalBytes)
        let repeatedCommitmentFragments = try OpalV0.AggregateFragmenter.fragments(
            for: commitmentSet,
            roundIdentifier: Self.aggregateFragmentRoundIdentifier
        )
        #expect(commitmentFragments == repeatedCommitmentFragments)

        let expectedFirstCommitmentFragment =
            Self.aggregateFragmentRoundIdentifier
            + [OpalV0.AggregateFragment.Kind.commitmentSet.rawValue]
            + commitmentSet.digest
            + Self.uint32Bytes(UInt32(commitmentSet.canonicalBytes.count))
            + [0x00, 0x05]
            + Self.uint32Bytes(4_017)
            + Array(commitmentSet.canonicalBytes.prefix(4_017))
        #expect(commitmentEncoded[0] == expectedFirstCommitmentFragment)
        #expect(
            Self.sha256Hexadecimal(commitmentEncoded[0])
                == "83cd6b90c0dac572e3f4c59e7b7281acc9a237644c79071b072d18003954eb35"
        )

        let componentSet = try Self.makeBlankComponentSet()
        let componentFragments = try OpalV0.AggregateFragmenter.fragments(
            for: componentSet,
            roundIdentifier: Self.aggregateFragmentRoundIdentifier
        )
        let componentEncoded = try componentFragments.map(
            Codec.encodeAggregateFragment
        )

        #expect(componentFragments.count == 2)
        #expect(componentFragments.map(\.body.count) == [4_017, 541])
        #expect(componentEncoded.map(\.count) == [4_092, 616])
        #expect(componentFragments.flatMap(\.body) == componentSet.canonicalBytes)
        #expect(
            Self.sha256Hexadecimal(componentEncoded[1])
                == "54e43e1bad3451c0e8d394e900fbc7035d091e29a819b5a111b7b44d8c6e468c"
        )
    }

    @Test(
        "Fragment every valid aggregate member count",
        arguments: [138, 161, 184]
    )
    func fragmentEveryAggregateMemberCount(memberCount: Int) throws {
        let commitmentSet = try Self.makeCommitmentSet(
            memberCount: memberCount
        )
        let componentSet = try Self.makeBlankComponentSet(
            memberCount: memberCount
        )

        for fragments in [
            try OpalV0.AggregateFragmenter.fragments(
                for: commitmentSet,
                roundIdentifier: Self.aggregateFragmentRoundIdentifier
            ),
            try OpalV0.AggregateFragmenter.fragments(
                for: componentSet,
                roundIdentifier: Self.aggregateFragmentRoundIdentifier
            )
        ] {
            #expect(fragments.count <= OpalV0.maximumAggregateFragmentCount)
            #expect(fragments.dropLast().allSatisfy {
                $0.body.count == OpalV0.maximumAggregateFragmentBodyByteCount
            })
            #expect(fragments.last?.body.isEmpty == false)
            for fragment in fragments {
                let encoded = try Codec.encodeAggregateFragment(fragment)
                #expect(encoded.count <= OpalV0.maximumInnerPayloadByteCount)
                #expect(try Codec.decodeAggregateFragment(from: encoded) == fragment)
            }
        }
    }

    @Test("Bound component fragmentation at every structural width")
    func boundComponentFragmentationAtEveryStructuralWidth() throws {
        let componentSets = try [
            Self.makeBlankComponentSet(memberCount: 184),
            Self.makeOutputComponentSet(memberCount: 184),
            Self.makeInputComponentSet(memberCount: 184)
        ]
        #expect(componentSets.map(\.canonicalBytes.count) == [6_076, 12_148, 14_172])

        let fragmentCounts = try componentSets.map { componentSet in
            try OpalV0.AggregateFragmenter.fragments(
                for: componentSet,
                roundIdentifier: Self.aggregateFragmentRoundIdentifier
            ).count
        }
        #expect(fragmentCounts == [2, 4, 4])
    }

    @Test("Reject invalid aggregate fragment model values")
    func rejectInvalidAggregateFragmentModels() throws {
        #expect(
            throws: OpalV0.AggregateFragment.Failure
                .invalidRoundIdentifierLength(actual: 31)
        ) {
            _ = try OpalV0.AggregateFragment.Descriptor(
                roundIdentifier: Array(repeating: 0, count: 31),
                aggregateKind: .commitmentSet,
                aggregateDigest: Array(repeating: 0, count: 32),
                declaredAggregateByteCount: 17_944
            )
        }
        #expect(
            throws: OpalV0.AggregateFragment.Failure
                .invalidAggregateDigestLength(actual: 31)
        ) {
            _ = try OpalV0.AggregateFragment.Descriptor(
                roundIdentifier: Self.aggregateFragmentRoundIdentifier,
                aggregateKind: .commitmentSet,
                aggregateDigest: Array(repeating: 0, count: 31),
                declaredAggregateByteCount: 17_944
            )
        }
        for invalidByteCount in [17_943, 17_945, 23_925] {
            #expect(
                throws: OpalV0.AggregateFragment.Failure
                    .invalidDeclaredAggregateByteCount(
                        kind: .commitmentSet,
                        actual: invalidByteCount
                    )
            ) {
                _ = try OpalV0.AggregateFragment.Descriptor(
                    roundIdentifier: Self.aggregateFragmentRoundIdentifier,
                    aggregateKind: .commitmentSet,
                    aggregateDigest: Array(repeating: 0, count: 32),
                    declaredAggregateByteCount: invalidByteCount
                )
            }
        }
        for invalidByteCount in [4_557, 14_173] {
            #expect(
                throws: OpalV0.AggregateFragment.Failure
                    .invalidDeclaredAggregateByteCount(
                        kind: .componentSet,
                        actual: invalidByteCount
                    )
            ) {
                _ = try OpalV0.AggregateFragment.Descriptor(
                    roundIdentifier: Self.aggregateFragmentRoundIdentifier,
                    aggregateKind: .componentSet,
                    aggregateDigest: Array(repeating: 0, count: 32),
                    declaredAggregateByteCount: invalidByteCount
                )
            }
        }

        let descriptor = try OpalV0.AggregateFragment.Descriptor(
            roundIdentifier: Self.aggregateFragmentRoundIdentifier,
            aggregateKind: .commitmentSet,
            aggregateDigest: Array(repeating: 0, count: 32),
            declaredAggregateByteCount: 17_944
        )
        #expect(
            throws: OpalV0.AggregateFragment.Failure
                .invalidFragmentIndex(index: 5, count: 5)
        ) {
            _ = try OpalV0.AggregateFragment(
                descriptor: descriptor,
                fragmentIndex: 5,
                body: []
            )
        }
        #expect(
            throws: OpalV0.AggregateFragment.Failure
                .invalidFragmentBodyByteCount(
                    index: 0,
                    expected: 4_017,
                    actual: 4_016
                )
        ) {
            _ = try OpalV0.AggregateFragment(
                descriptor: descriptor,
                fragmentIndex: 0,
                body: Array(repeating: 0, count: 4_016)
            )
        }
        #expect(
            throws: OpalV0.AggregateFragment.Failure
                .invalidFragmentBodyByteCount(
                    index: 4,
                    expected: 1_876,
                    actual: 1_875
                )
        ) {
            _ = try OpalV0.AggregateFragment(
                descriptor: descriptor,
                fragmentIndex: 4,
                body: Array(repeating: 0, count: 1_875)
            )
        }
    }

    @Test("Reject malformed canonical aggregate fragment bytes")
    func rejectMalformedAggregateFragmentBytes() throws {
        let fragment = try #require(
            OpalV0.AggregateFragmenter.fragments(
                for: Self.makeCommitmentSet(),
                roundIdentifier: Self.aggregateFragmentRoundIdentifier
            ).first
        )
        let validBytes = try Codec.encodeAggregateFragment(fragment)

        #expect(
            throws: OpalFusion.Mosaic.CanonicalCodingError.truncatedInput(
                expectedByteCount: 32,
                remainingByteCount: 1
            )
        ) {
            _ = try Codec.decodeAggregateFragment(from: [0])
        }

        var unknownKind = validBytes
        unknownKind[32] = 0xFF
        #expect(
            throws: OpalV0.AggregateFragment.Failure
                .unknownAggregateKind(0xFF)
        ) {
            _ = try Codec.decodeAggregateFragment(from: unknownKind)
        }

        var wrongCount = validBytes
        wrongCount[70] = 4
        #expect(
            throws: OpalV0.AggregateFragment.Failure
                .invalidFragmentCount(expected: 5, actual: 4)
        ) {
            _ = try Codec.decodeAggregateFragment(from: wrongCount)
        }

        var outOfRangeIndex = validBytes
        outOfRangeIndex[69] = 5
        #expect(
            throws: OpalV0.AggregateFragment.Failure
                .invalidFragmentIndex(index: 5, count: 5)
        ) {
            _ = try Codec.decodeAggregateFragment(from: outOfRangeIndex)
        }

        var shortBody = validBytes
        shortBody.removeLast()
        shortBody.replaceSubrange(71 ..< 75, with: Self.uint32Bytes(4_016))
        #expect(
            throws: OpalV0.AggregateFragment.Failure
                .invalidFragmentBodyByteCount(
                    index: 0,
                    expected: 4_017,
                    actual: 4_016
                )
        ) {
            _ = try Codec.decodeAggregateFragment(from: shortBody)
        }

        #expect(
            throws: OpalV0.AggregateFragment.Failure
                .encodedFragmentTooLarge(maximum: 4_092, actual: 4_093)
        ) {
            _ = try Codec.decodeAggregateFragment(
                from: Array(repeating: 0, count: 4_093)
            )
        }

        let lastFragment = try #require(
            OpalV0.AggregateFragmenter.fragments(
                for: Self.makeCommitmentSet(),
                roundIdentifier: Self.aggregateFragmentRoundIdentifier
            ).last
        )
        let trailingBytes = try Codec.encodeAggregateFragment(lastFragment) + [0]
        #expect(
            throws: OpalFusion.Mosaic.CanonicalCodingError.trailingBytes(1)
        ) {
            _ = try Codec.decodeAggregateFragment(from: trailingBytes)
        }
    }

    @Test("Every canonical aggregate fragment fits the padded envelope")
    func roundTripAggregateFragmentsThroughPaddedEnvelope() throws {
        let fragments = try OpalV0.AggregateFragmenter.fragments(
            for: Self.makeCommitmentSet(memberCount: 184),
            roundIdentifier: Self.aggregateFragmentRoundIdentifier
        )
        #expect(fragments.count == OpalV0.maximumAggregateFragmentCount)

        for fragment in fragments {
            let fragmentBytes = try Codec.encodeAggregateFragment(fragment)
            let padded = try OpalV0.PaddedEnvelopeCodec.encode(fragmentBytes)
            let unpadded = try OpalV0.PaddedEnvelopeCodec.decode(padded)

            #expect(padded.utf8.count == OpalV0.paddedInnerPlaintextByteCount)
            #expect(unpadded == fragmentBytes)
            #expect(try Codec.decodeAggregateFragment(from: unpadded) == fragment)
        }
    }
}

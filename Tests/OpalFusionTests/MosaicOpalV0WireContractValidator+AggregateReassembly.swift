// MosaicOpalV0WireContractValidator+AggregateReassembly.swift

@testable import OpalFusion
import Testing

extension MosaicOpalV0WireContractValidator {
    @Test("Reject an invalid reassembly context before accepting fragments")
    func rejectInvalidReassemblyContext() {
        #expect(
            throws: OpalV0.AggregateFragment.Failure
                .invalidRoundIdentifierLength(actual: 31)
        ) {
            _ = try OpalV0.AggregateReassembler(
                roundIdentifier: Array(repeating: 0, count: 31),
                aggregateKind: .commitmentSet
            )
        }
    }

    @Test("Reassemble typed aggregates after reverse-order delivery")
    func reassembleTypedAggregatesAfterReverseOrderDelivery() throws {
        let commitmentSet = try Self.makeCommitmentSet(memberCount: 184)
        let commitmentFragments = try OpalV0.AggregateFragmenter.fragments(
            for: commitmentSet,
            roundIdentifier: Self.aggregateFragmentRoundIdentifier
        )
        var commitmentReassembler = try OpalV0.AggregateReassembler(
            roundIdentifier: Self.aggregateFragmentRoundIdentifier,
            aggregateKind: .commitmentSet
        )
        for (deliveryIndex, fragment) in commitmentFragments.reversed().enumerated() {
            let decision = commitmentReassembler.receive(fragment)
            if deliveryIndex == commitmentFragments.count - 1 {
                #expect(decision == .completedCommitmentSet(commitmentSet))
            } else {
                #expect(
                    decision == .accepted(
                        receivedFragmentCount: deliveryIndex + 1,
                        expectedFragmentCount: commitmentFragments.count
                    )
                )
            }
        }

        let componentSet = try Self.makeInputComponentSet(memberCount: 184)
        let componentFragments = try OpalV0.AggregateFragmenter.fragments(
            for: componentSet,
            roundIdentifier: Self.aggregateFragmentRoundIdentifier
        )
        var componentReassembler = try OpalV0.AggregateReassembler(
            roundIdentifier: Self.aggregateFragmentRoundIdentifier,
            aggregateKind: .componentSet
        )
        for (deliveryIndex, fragment) in componentFragments.reversed().enumerated() {
            let decision = componentReassembler.receive(fragment)
            if deliveryIndex == componentFragments.count - 1 {
                #expect(decision == .completedComponentSet(componentSet))
            } else {
                #expect(
                    decision == .accepted(
                        receivedFragmentCount: deliveryIndex + 1,
                        expectedFragmentCount: componentFragments.count
                    )
                )
            }
        }
    }

    @Test("Accept exact fragment duplicates without completing an omission")
    func acceptExactDuplicatesWithoutCompletingAnOmission() throws {
        let commitmentSet = try Self.makeCommitmentSet()
        let fragments = try OpalV0.AggregateFragmenter.fragments(
            for: commitmentSet,
            roundIdentifier: Self.aggregateFragmentRoundIdentifier
        )
        var reassembler = try OpalV0.AggregateReassembler(
            roundIdentifier: Self.aggregateFragmentRoundIdentifier,
            aggregateKind: .commitmentSet
        )

        #expect(
            reassembler.receive(fragments[2])
                == .accepted(
                    receivedFragmentCount: 1,
                    expectedFragmentCount: 5
                )
        )
        #expect(
            reassembler.receive(fragments[2])
                == .exactDuplicate(fragmentIndex: 2)
        )
        #expect(
            reassembler.receive(fragments[0])
                == .accepted(
                    receivedFragmentCount: 2,
                    expectedFragmentCount: 5
                )
        )
    }

    @Test(
        "Do not complete with a missing first, middle, or final fragment",
        arguments: [0, 2, 4]
    )
    func doNotCompleteWithMissingFragment(omittedIndex: Int) throws {
        let fragments = try OpalV0.AggregateFragmenter.fragments(
            for: Self.makeCommitmentSet(),
            roundIdentifier: Self.aggregateFragmentRoundIdentifier
        )
        var reassembler = try OpalV0.AggregateReassembler(
            roundIdentifier: Self.aggregateFragmentRoundIdentifier,
            aggregateKind: .commitmentSet
        )
        var decision: OpalV0.AggregateReassembler.Decision?

        for fragmentIndex in fragments.indices where fragmentIndex != omittedIndex {
            decision = reassembler.receive(fragments[fragmentIndex])
        }

        #expect(
            decision == .accepted(
                receivedFragmentCount: 4,
                expectedFragmentCount: 5
            )
        )
    }

    @Test("Terminate on same-index fragment substitution")
    func terminateOnSameIndexFragmentSubstitution() throws {
        let fragments = try OpalV0.AggregateFragmenter.fragments(
            for: Self.makeCommitmentSet(),
            roundIdentifier: Self.aggregateFragmentRoundIdentifier
        )
        var substitutedBody = fragments[0].body
        substitutedBody[0] ^= 0x01
        let substitution = try OpalV0.AggregateFragment(
            descriptor: fragments[0].descriptor,
            fragmentIndex: 0,
            body: substitutedBody
        )
        var reassembler = try OpalV0.AggregateReassembler(
            roundIdentifier: Self.aggregateFragmentRoundIdentifier,
            aggregateKind: .commitmentSet
        )

        _ = reassembler.receive(fragments[0])
        #expect(
            reassembler.receive(substitution)
                == .terminated(.conflictingFragment(index: 0))
        )
        #expect(
            reassembler.receive(fragments[1])
                == .rejected(.inputAfterTermination)
        )
    }

    @Test("Terminate before indexing cross-round and cross-kind fragments")
    func terminateCrossContextFragments() throws {
        let commitmentFragment = try #require(
            OpalV0.AggregateFragmenter.fragments(
                for: Self.makeCommitmentSet(),
                roundIdentifier: Array(repeating: 0xB2, count: 32)
            ).first
        )
        var roundReassembler = try OpalV0.AggregateReassembler(
            roundIdentifier: Self.aggregateFragmentRoundIdentifier,
            aggregateKind: .commitmentSet
        )
        #expect(
            roundReassembler.receive(commitmentFragment)
                == .terminated(.roundIdentifierMismatch)
        )

        let componentFragment = try #require(
            OpalV0.AggregateFragmenter.fragments(
                for: Self.makeBlankComponentSet(),
                roundIdentifier: Self.aggregateFragmentRoundIdentifier
            ).first
        )
        var kindReassembler = try OpalV0.AggregateReassembler(
            roundIdentifier: Self.aggregateFragmentRoundIdentifier,
            aggregateKind: .commitmentSet
        )
        #expect(
            kindReassembler.receive(componentFragment)
                == .terminated(.aggregateKindMismatch)
        )
    }

    @Test("Terminate on aggregate descriptor conflicts")
    func terminateOnAggregateDescriptorConflicts() throws {
        let fragments = try OpalV0.AggregateFragmenter.fragments(
            for: Self.makeCommitmentSet(),
            roundIdentifier: Self.aggregateFragmentRoundIdentifier
        )

        var conflictingDigest = fragments[1].descriptor.aggregateDigest
        conflictingDigest[0] ^= 0x01
        let digestDescriptor = try OpalV0.AggregateFragment.Descriptor(
            roundIdentifier: Self.aggregateFragmentRoundIdentifier,
            aggregateKind: .commitmentSet,
            aggregateDigest: conflictingDigest,
            declaredAggregateByteCount: 17_944
        )
        let digestConflict = try OpalV0.AggregateFragment(
            descriptor: digestDescriptor,
            fragmentIndex: 1,
            body: fragments[1].body
        )
        var digestReassembler = try OpalV0.AggregateReassembler(
            roundIdentifier: Self.aggregateFragmentRoundIdentifier,
            aggregateKind: .commitmentSet
        )
        _ = digestReassembler.receive(fragments[0])
        #expect(
            digestReassembler.receive(digestConflict)
                == .terminated(.aggregateDigestConflict)
        )

        let totalDescriptor = try OpalV0.AggregateFragment.Descriptor(
            roundIdentifier: Self.aggregateFragmentRoundIdentifier,
            aggregateKind: .commitmentSet,
            aggregateDigest: fragments[0].descriptor.aggregateDigest,
            declaredAggregateByteCount: 20_934
        )
        let totalConflict = try OpalV0.AggregateFragment(
            descriptor: totalDescriptor,
            fragmentIndex: 1,
            body: fragments[1].body
        )
        var totalReassembler = try OpalV0.AggregateReassembler(
            roundIdentifier: Self.aggregateFragmentRoundIdentifier,
            aggregateKind: .commitmentSet
        )
        _ = totalReassembler.receive(fragments[0])
        #expect(
            totalReassembler.receive(totalConflict)
                == .terminated(
                    .declaredAggregateByteCountConflict(
                        expected: 17_944,
                        actual: 20_934
                    )
                )
        )
    }

    @Test("Terminate when complete fragment bytes fail the aggregate digest")
    func terminateOnAggregateDigestMismatch() throws {
        var fragments = try OpalV0.AggregateFragmenter.fragments(
            for: Self.makeCommitmentSet(),
            roundIdentifier: Self.aggregateFragmentRoundIdentifier
        )
        var mutatedBody = fragments[3].body
        mutatedBody[100] ^= 0x01
        fragments[3] = try .init(
            descriptor: fragments[3].descriptor,
            fragmentIndex: 3,
            body: mutatedBody
        )
        var reassembler = try OpalV0.AggregateReassembler(
            roundIdentifier: Self.aggregateFragmentRoundIdentifier,
            aggregateKind: .commitmentSet
        )

        for fragment in fragments.dropLast() {
            _ = reassembler.receive(fragment)
        }
        #expect(
            reassembler.receive(try #require(fragments.last))
                == .terminated(.aggregateDigestMismatch)
        )
    }

    @Test("Require strict canonical aggregate decoding after digest agreement")
    func requireCanonicalAggregateAfterDigestAgreement() throws {
        let commitmentSet = try Self.makeCommitmentSet()
        var descendingBytes = commitmentSet.canonicalBytes
        let firstMember = Array(descendingBytes[4 ..< 134])
        let secondMember = Array(descendingBytes[134 ..< 264])
        descendingBytes.replaceSubrange(4 ..< 134, with: secondMember)
        descendingBytes.replaceSubrange(134 ..< 264, with: firstMember)
        let fragments = try Self.makeRawAggregateFragments(
            aggregateKind: .commitmentSet,
            canonicalBytes: descendingBytes
        )
        var reassembler = try OpalV0.AggregateReassembler(
            roundIdentifier: Self.aggregateFragmentRoundIdentifier,
            aggregateKind: .commitmentSet
        )

        for fragment in fragments.dropLast() {
            _ = reassembler.receive(fragment)
        }
        #expect(
            reassembler.receive(try #require(fragments.last))
                == .terminated(
                    .invalidCanonicalAggregate(.nonCanonicalSetOrdering)
                )
        )
    }

    @Test("Require aggregate wire validation after digest agreement")
    func requireAggregateWireContractAfterDigestAgreement() throws {
        let invalidComponentBytes = [UInt8](repeating: 0, count: 4_558)
        let fragments = try Self.makeRawAggregateFragments(
            aggregateKind: .componentSet,
            canonicalBytes: invalidComponentBytes
        )
        var reassembler = try OpalV0.AggregateReassembler(
            roundIdentifier: Self.aggregateFragmentRoundIdentifier,
            aggregateKind: .componentSet
        )

        _ = reassembler.receive(fragments[0])
        #expect(
            reassembler.receive(fragments[1])
                == .terminated(
                    .invalidAggregateWireContract(
                        .invalidComponentSetCount(actual: 0)
                    )
                )
        )
    }

    @Test("Reject every fragment after successful reassembly")
    func rejectFragmentsAfterSuccessfulReassembly() throws {
        let fragments = try OpalV0.AggregateFragmenter.fragments(
            for: Self.makeBlankComponentSet(),
            roundIdentifier: Self.aggregateFragmentRoundIdentifier
        )
        var reassembler = try OpalV0.AggregateReassembler(
            roundIdentifier: Self.aggregateFragmentRoundIdentifier,
            aggregateKind: .componentSet
        )

        _ = reassembler.receive(fragments[0])
        _ = reassembler.receive(fragments[1])
        #expect(
            reassembler.receive(fragments[0])
                == .rejected(.inputAfterTermination)
        )
    }
}

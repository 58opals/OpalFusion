// OpalFusion+Mosaic+OpalV0+AggregateFragment.swift

extension OpalFusion.Mosaic.OpalV0 {
    /// One bounded piece of an existing canonical aggregate document.
    struct AggregateFragment: Sendable, Equatable {
        enum Kind: UInt8, CaseIterable, Sendable {
            case commitmentSet = 0
            case componentSet = 1

            var digestDomainSuffix: String {
                switch self {
                case .commitmentSet:
                    "commitment-set"
                case .componentSet:
                    "component-set"
                }
            }

            func accepts(declaredAggregateByteCount: Int) -> Bool {
                switch self {
                case .commitmentSet:
                    let roster = OpalFusion.Mosaic.RosterPolicy.opalV0
                    return (roster.minimumContributorCount ...
                        (roster.maximumCandidateCount - roster.conductorCount))
                        .contains { contributorCount in
                            declaredAggregateByteCount == 4
                                + contributorCount
                                * OpalFusion.Mosaic.OpalV0
                                    .componentAuthorizationCountPerContributor
                                * OpalFusion.Mosaic.OpalV0.componentCommitmentByteCount
                        }
                case .componentSet:
                    let roster = OpalFusion.Mosaic.RosterPolicy.opalV0
                    let minimumMemberCount = roster.minimumContributorCount
                        * OpalFusion.Mosaic.OpalV0
                            .componentAuthorizationCountPerContributor
                    let maximumMemberCount = (roster.maximumCandidateCount
                        - roster.conductorCount)
                        * OpalFusion.Mosaic.OpalV0
                            .componentAuthorizationCountPerContributor
                    let minimum = 4 + minimumMemberCount * 33
                    let maximum = 4 + maximumMemberCount * 77
                    return (minimum ... maximum).contains(
                        declaredAggregateByteCount
                    )
                }
            }
        }

        enum Failure: Error, Sendable, Equatable {
            case unknownAggregateKind(UInt8)
            case invalidRoundIdentifierLength(actual: Int)
            case invalidAggregateDigestLength(actual: Int)
            case invalidDeclaredAggregateByteCount(kind: Kind, actual: Int)
            case invalidFragmentCount(expected: Int, actual: Int)
            case invalidFragmentIndex(index: Int, count: Int)
            case invalidFragmentBodyByteCount(
                index: Int,
                expected: Int,
                actual: Int
            )
            case encodedFragmentTooLarge(maximum: Int, actual: Int)
            case roundIdentifierMismatch
            case aggregateKindMismatch
            case aggregateDigestConflict
            case declaredAggregateByteCountConflict(expected: Int, actual: Int)
            case conflictingFragment(index: Int)
            case aggregateDigestMismatch
            case invalidCanonicalAggregate(
                OpalFusion.Mosaic.CanonicalCodingError
            )
            case invalidAggregateWireContract(
                OpalFusion.Mosaic.OpalV0.WireContractError
            )
            case invalidReassembledAggregate(kind: Kind)
            case inputAfterTermination
        }

        struct Descriptor: Sendable, Equatable {
            let roundIdentifier: [UInt8]
            let aggregateKind: Kind
            let aggregateDigest: [UInt8]
            let declaredAggregateByteCount: Int
            let fragmentCount: Int

            init(
                roundIdentifier: [UInt8],
                aggregateKind: Kind,
                aggregateDigest: [UInt8],
                declaredAggregateByteCount: Int
            ) throws {
                guard roundIdentifier.count
                    == OpalFusion.Mosaic.OpalV0.digestByteCount else {
                    throw Failure.invalidRoundIdentifierLength(
                        actual: roundIdentifier.count
                    )
                }
                guard aggregateDigest.count
                    == OpalFusion.Mosaic.OpalV0.digestByteCount else {
                    throw Failure.invalidAggregateDigestLength(
                        actual: aggregateDigest.count
                    )
                }
                guard aggregateKind.accepts(
                    declaredAggregateByteCount: declaredAggregateByteCount
                ) else {
                    throw Failure.invalidDeclaredAggregateByteCount(
                        kind: aggregateKind,
                        actual: declaredAggregateByteCount
                    )
                }

                let bodyCapacity = OpalFusion.Mosaic.OpalV0
                    .maximumAggregateFragmentBodyByteCount
                let fragmentCount = (declaredAggregateByteCount
                    + bodyCapacity - 1) / bodyCapacity
                guard (1 ... OpalFusion.Mosaic.OpalV0.maximumAggregateFragmentCount)
                    .contains(fragmentCount) else {
                    throw Failure.invalidFragmentCount(
                        expected: OpalFusion.Mosaic.OpalV0
                            .maximumAggregateFragmentCount,
                        actual: fragmentCount
                    )
                }

                self.roundIdentifier = Array(roundIdentifier)
                self.aggregateKind = aggregateKind
                self.aggregateDigest = Array(aggregateDigest)
                self.declaredAggregateByteCount = declaredAggregateByteCount
                self.fragmentCount = fragmentCount
            }

            func expectedBodyByteCount(fragmentIndex: Int) -> Int? {
                guard (0 ..< fragmentCount).contains(fragmentIndex) else {
                    return nil
                }
                let bodyCapacity = OpalFusion.Mosaic.OpalV0
                    .maximumAggregateFragmentBodyByteCount
                guard fragmentIndex == fragmentCount - 1 else {
                    return bodyCapacity
                }
                return declaredAggregateByteCount
                    - bodyCapacity * (fragmentCount - 1)
            }
        }

        let descriptor: Descriptor
        let fragmentIndex: Int
        let body: [UInt8]

        init(
            descriptor: Descriptor,
            fragmentIndex: Int,
            body: [UInt8]
        ) throws {
            guard let expectedBodyByteCount = descriptor.expectedBodyByteCount(
                fragmentIndex: fragmentIndex
            ) else {
                throw Failure.invalidFragmentIndex(
                    index: fragmentIndex,
                    count: descriptor.fragmentCount
                )
            }
            guard body.count == expectedBodyByteCount else {
                throw Failure.invalidFragmentBodyByteCount(
                    index: fragmentIndex,
                    expected: expectedBodyByteCount,
                    actual: body.count
                )
            }
            self.descriptor = descriptor
            self.fragmentIndex = fragmentIndex
            self.body = Array(body)
        }
    }
}

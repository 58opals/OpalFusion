// OpalFusion+Mosaic+OpalV0+AggregateReassembler.swift

extension OpalFusion.Mosaic.OpalV0 {
    struct AggregateReassembler: Sendable {
        enum Decision: Sendable, Equatable {
            case accepted(
                receivedFragmentCount: Int,
                expectedFragmentCount: Int
            )
            case exactDuplicate(fragmentIndex: Int)
            case completedCommitmentSet(CommitmentSet)
            case completedComponentSet(ComponentSet)
            case terminated(AggregateFragment.Failure)
            case rejected(AggregateFragment.Failure)
        }

        private let expectedRoundIdentifier: [UInt8]
        private let expectedAggregateKind: AggregateFragment.Kind
        private var descriptor: AggregateFragment.Descriptor?
        private var bodiesByFragmentIndex: [Int: [UInt8]] = [:]
        private var isTerminal = false

        init(
            roundIdentifier: [UInt8],
            aggregateKind: AggregateFragment.Kind
        ) throws {
            guard roundIdentifier.count
                == OpalFusion.Mosaic.OpalV0.digestByteCount else {
                throw AggregateFragment.Failure.invalidRoundIdentifierLength(
                    actual: roundIdentifier.count
                )
            }
            self.expectedRoundIdentifier = Array(roundIdentifier)
            self.expectedAggregateKind = aggregateKind
        }

        mutating func receive(_ fragment: AggregateFragment) -> Decision {
            guard isTerminal == false else {
                return .rejected(.inputAfterTermination)
            }
            guard fragment.descriptor.roundIdentifier
                == expectedRoundIdentifier else {
                return terminate(with: .roundIdentifierMismatch)
            }
            guard fragment.descriptor.aggregateKind
                == expectedAggregateKind else {
                return terminate(with: .aggregateKindMismatch)
            }

            if let descriptor {
                guard fragment.descriptor.aggregateDigest
                    == descriptor.aggregateDigest else {
                    return terminate(with: .aggregateDigestConflict)
                }
                guard fragment.descriptor.declaredAggregateByteCount
                    == descriptor.declaredAggregateByteCount else {
                    return terminate(
                        with: .declaredAggregateByteCountConflict(
                            expected: descriptor.declaredAggregateByteCount,
                            actual: fragment.descriptor.declaredAggregateByteCount
                        )
                    )
                }
            } else {
                self.descriptor = fragment.descriptor
                bodiesByFragmentIndex.reserveCapacity(
                    fragment.descriptor.fragmentCount
                )
            }

            if let existingBody = bodiesByFragmentIndex[fragment.fragmentIndex] {
                guard existingBody == fragment.body else {
                    return terminate(
                        with: .conflictingFragment(
                            index: fragment.fragmentIndex
                        )
                    )
                }
                return .exactDuplicate(fragmentIndex: fragment.fragmentIndex)
            }
            bodiesByFragmentIndex[fragment.fragmentIndex] = fragment.body

            guard let descriptor else {
                return terminate(
                    with: .invalidReassembledAggregate(
                        kind: expectedAggregateKind
                    )
                )
            }
            guard bodiesByFragmentIndex.count == descriptor.fragmentCount else {
                return .accepted(
                    receivedFragmentCount: bodiesByFragmentIndex.count,
                    expectedFragmentCount: descriptor.fragmentCount
                )
            }
            return complete(descriptor: descriptor)
        }

        private mutating func complete(
            descriptor: AggregateFragment.Descriptor
        ) -> Decision {
            var canonicalBytes: [UInt8] = []
            canonicalBytes.reserveCapacity(
                descriptor.declaredAggregateByteCount
            )
            for fragmentIndex in 0 ..< descriptor.fragmentCount {
                guard let body = bodiesByFragmentIndex[fragmentIndex] else {
                    return .accepted(
                        receivedFragmentCount: bodiesByFragmentIndex.count,
                        expectedFragmentCount: descriptor.fragmentCount
                    )
                }
                canonicalBytes.append(contentsOf: body)
            }

            let recomputedDigest = OpalFusion.Mosaic.OpalV0.aggregateDigest(
                domainSuffix: descriptor.aggregateKind.digestDomainSuffix,
                canonicalBytes: canonicalBytes
            )
            guard recomputedDigest == descriptor.aggregateDigest else {
                return terminate(with: .aggregateDigestMismatch)
            }

            do {
                switch descriptor.aggregateKind {
                case .commitmentSet:
                    let commitmentSet = try CanonicalWireCodec
                        .decodeCommitmentSet(from: canonicalBytes)
                    finish()
                    return .completedCommitmentSet(commitmentSet)
                case .componentSet:
                    let componentSet = try CanonicalWireCodec
                        .decodeComponentSet(from: canonicalBytes)
                    finish()
                    return .completedComponentSet(componentSet)
                }
            } catch let error as OpalFusion.Mosaic.CanonicalCodingError {
                return terminate(with: .invalidCanonicalAggregate(error))
            } catch let error as WireContractError {
                return terminate(with: .invalidAggregateWireContract(error))
            } catch {
                return terminate(
                    with: .invalidReassembledAggregate(
                        kind: descriptor.aggregateKind
                    )
                )
            }
        }

        private mutating func terminate(
            with failure: AggregateFragment.Failure
        ) -> Decision {
            finish()
            return .terminated(failure)
        }

        private mutating func finish() {
            isTerminal = true
            descriptor = nil
            bodiesByFragmentIndex.removeAll(keepingCapacity: false)
        }
    }
}

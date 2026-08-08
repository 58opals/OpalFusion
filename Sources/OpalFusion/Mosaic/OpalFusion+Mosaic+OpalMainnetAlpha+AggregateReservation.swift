// OpalFusion+Mosaic+OpalMainnetAlpha+AggregateReservation.swift

extension OpalFusion.Mosaic.OpalMainnetAlpha {
    enum AggregateKind: UInt8, CaseIterable, Sendable, Equatable {
        case commitmentSet = 0
        case componentSet = 1
        case playerCommit = 2
        case completeManifest = 4
        case bchSignatureSet = 6
        case completeTransaction = 7

        var digestDomainSuffix: String {
            switch self {
            case .commitmentSet: "commitment-set"
            case .componentSet: "component-set"
            case .playerCommit: "player-commit"
            case .completeManifest: "complete-manifest"
            case .bchSignatureSet: "bch-signature-set"
            case .completeTransaction: "complete-transaction"
            }
        }

        func accepts(declaredCanonicalByteCount byteCount: Int) -> Bool {
            switch self {
            case .commitmentSet:
                return OpalFusion.Mosaic.OpalV0.AggregateFragment.Kind.commitmentSet
                    .accepts(declaredAggregateByteCount: byteCount)
            case .componentSet:
                return OpalFusion.Mosaic.OpalV0.AggregateFragment.Kind.componentSet
                    .accepts(declaredAggregateByteCount: byteCount)
            case .playerCommit:
                return byteCount == OpalFusion.Mosaic.OpalMainnetAlpha
                    .playerCommitCanonicalByteCount
            case .completeManifest:
                return (7 ... 9).contains {
                    byteCount == OpalFusion.Mosaic.OpalMainnetAlpha
                        .completeManifestCanonicalByteCount(candidateCount: $0)
                }
            case .bchSignatureSet:
                let fixedByteCount = 68
                let entryByteCount = 101
                let variableByteCount = byteCount - fixedByteCount
                return variableByteCount > 0
                    && variableByteCount.isMultiple(of: entryByteCount)
                    && (1 ... OpalFusion.Mosaic.OpalMainnetAlpha
                        .maximumTransactionInputCount).contains(
                            variableByteCount / entryByteCount
                        )
            case .completeTransaction:
                return (OpalFusion.Mosaic.OpalMainnetAlpha
                    .minimumCompleteTransactionPayloadByteCount ...
                    OpalFusion.Mosaic.OpalMainnetAlpha
                    .maximumCompleteTransactionPayloadByteCount)
                    .contains(byteCount)
            }
        }
    }

    enum AggregateDocument: Sendable, Equatable {
        case commitmentSet(OpalFusion.Mosaic.OpalV0.CommitmentSet)
        case componentSet(OpalFusion.Mosaic.OpalV0.ComponentSet)
        case playerCommit(PlayerCommit)
        case completeManifest(RoundManifest)
        case bchSignatureSet(BCHSignatureSet)
        case completeTransaction(CompleteTransactionPayload)
    }

    enum AggregateDecodingContext: Sendable, Equatable {
        case profileOnly
        case manifest(ManifestProposalContext)
        case bchSignatureSet(expectedInputCount: Int)
        case completeTransaction(
            expectedTranscript: OpalFusion.Mosaic.OpalV0
                .UnsignedTransactionTranscript
        )

        func accepts(_ kind: AggregateKind) -> Bool {
            switch (self, kind) {
            case (.profileOnly, .commitmentSet),
                 (.profileOnly, .componentSet),
                 (.profileOnly, .playerCommit),
                 (.manifest, .completeManifest),
                 (.bchSignatureSet, .bchSignatureSet),
                 (.completeTransaction, .completeTransaction):
                true
            default:
                false
            }
        }

        func decode(
            _ bytes: [UInt8],
            kind: AggregateKind
        ) throws -> AggregateDocument {
            guard accepts(kind) else {
                throw ContractError.aggregateDecodingContextMismatch(kind)
            }
            switch (self, kind) {
            case (.profileOnly, .commitmentSet):
                return .commitmentSet(
                    try OpalFusion.Mosaic.OpalV0.CanonicalWireCodec
                        .decodeCommitmentSet(
                            from: bytes,
                            profile: .opalMainnetAlpha
                        )
                )
            case (.profileOnly, .componentSet):
                return .componentSet(
                    try OpalFusion.Mosaic.OpalV0.CanonicalWireCodec
                        .decodeComponentSet(
                            from: bytes,
                            profile: .opalMainnetAlpha
                        )
                )
            case (.profileOnly, .playerCommit):
                return .playerCommit(
                    try CanonicalWireCodec.decodePlayerCommit(from: bytes)
                )
            case let (.manifest(context), .completeManifest):
                return .completeManifest(
                    try CanonicalWireCodec.decodeManifest(
                        from: bytes,
                        expectedContext: context
                    )
                )
            case let (.bchSignatureSet(expectedInputCount), .bchSignatureSet):
                return .bchSignatureSet(
                    try CanonicalWireCodec.decodeBCHSignatureSet(
                        from: bytes,
                        expectedInputCount: expectedInputCount
                    )
                )
            case let (
                .completeTransaction(expectedTranscript),
                .completeTransaction
            ):
                let payload = try CanonicalWireCodec
                    .decodeCompleteTransactionPayload(from: bytes)
                guard payload.matches(transcript: expectedTranscript) else {
                    throw ContractError.transactionMismatch
                }
                return .completeTransaction(payload)
            default:
                throw ContractError.aggregateDecodingContextMismatch(kind)
            }
        }
    }

    /// A control-sequence reservation for one immediately following fragment run.
    struct AggregateReservation: Sendable, Equatable {
        let aggregateKind: AggregateKind
        let aggregateDigest: [UInt8]
        let declaredCanonicalByteCount: Int
        let fragmentCount: Int

        init(
            aggregateKind: AggregateKind,
            aggregateDigest: [UInt8],
            declaredCanonicalByteCount: Int
        ) throws {
            try RoleSeedValidator.validateFixed(
                aggregateDigest,
                field: .aggregateDigest
            )
            guard declaredCanonicalByteCount > 0,
                  UInt32(exactly: declaredCanonicalByteCount) != nil,
                  aggregateKind.accepts(
                    declaredCanonicalByteCount: declaredCanonicalByteCount
                  ) else {
                throw ContractError.invalidAggregateByteCount(
                    actual: declaredCanonicalByteCount
                )
            }
            let capacity = OpalFusion.Mosaic.OpalMainnetAlpha
                .maximumAggregateFragmentBodyByteCount
            let fragmentCount = (declaredCanonicalByteCount + capacity - 1)
                / capacity
            guard (1 ... Int(UInt8.max)).contains(fragmentCount) else {
                throw ContractError.invalidAggregateFragmentCount(
                    expected: Int(UInt8.max),
                    actual: fragmentCount
                )
            }
            self.aggregateKind = aggregateKind
            self.aggregateDigest = Array(aggregateDigest)
            self.declaredCanonicalByteCount = declaredCanonicalByteCount
            self.fragmentCount = fragmentCount
        }

        func expectedBodyByteCount(at fragmentIndex: Int) -> Int? {
            guard (0 ..< fragmentCount).contains(fragmentIndex) else {
                return nil
            }
            let capacity = OpalFusion.Mosaic.OpalMainnetAlpha
                .maximumAggregateFragmentBodyByteCount
            if fragmentIndex < fragmentCount - 1 {
                return capacity
            }
            return declaredCanonicalByteCount - capacity * (fragmentCount - 1)
        }
    }

    struct AggregateFragment: Sendable, Equatable {
        let reservationSequence: UInt64
        let fragmentIndex: Int
        let body: [UInt8]

        init(
            reservationSequence: UInt64,
            fragmentIndex: Int,
            body: [UInt8],
            reservation: AggregateReservation
        ) throws {
            guard let expectedBodyCount = reservation.expectedBodyByteCount(
                at: fragmentIndex
            ) else {
                throw ContractError.invalidAggregateFragmentIndex(
                    index: fragmentIndex,
                    count: reservation.fragmentCount
                )
            }
            guard body.count == expectedBodyCount else {
                throw ContractError.invalidAggregateFragmentBodyCount(
                    expected: expectedBodyCount,
                    actual: body.count
                )
            }
            guard reservationSequence.addingReportingOverflow(
                UInt64(reservation.fragmentCount)
            ).overflow == false else {
                throw ContractError.sequenceOverflow
            }
            self.reservationSequence = reservationSequence
            self.fragmentIndex = fragmentIndex
            self.body = Array(body)
        }
    }

    struct AggregateReassembler: Sendable {
        enum Decision: Sendable, Equatable {
            case accepted(received: Int, expected: Int)
            case exactDuplicate(fragmentIndex: Int)
            case completed(AggregateDocument)
            case terminated(ContractError)
            case inputAfterTermination
        }

        let reservationSequence: UInt64
        let reservation: AggregateReservation
        private let decodingContext: AggregateDecodingContext
        private var fragmentsByIndex: [Int: AggregateFragment] = [:]
        private var isTerminal = false

        init(
            reservationSequence: UInt64,
            reservation: AggregateReservation,
            decodingContext: AggregateDecodingContext
        ) throws {
            guard reservationSequence.addingReportingOverflow(
                UInt64(reservation.fragmentCount)
            ).overflow == false else {
                throw ContractError.sequenceOverflow
            }
            guard decodingContext.accepts(reservation.aggregateKind) else {
                throw ContractError.aggregateDecodingContextMismatch(
                    reservation.aggregateKind
                )
            }
            self.reservationSequence = reservationSequence
            self.reservation = reservation
            self.decodingContext = decodingContext
        }

        mutating func receive(
            _ fragment: AggregateFragment,
            at controlSequence: UInt64
        ) -> Decision {
            guard !isTerminal else {
                return .inputAfterTermination
            }
            let expectedSequence = reservationSequence
                + UInt64(fragment.fragmentIndex) + 1
            guard fragment.reservationSequence == reservationSequence,
                  controlSequence == expectedSequence else {
                return terminate(.invalidAggregateFragmentIndex(
                    index: fragment.fragmentIndex,
                    count: reservation.fragmentCount
                ))
            }
            if let existing = fragmentsByIndex[fragment.fragmentIndex] {
                guard existing == fragment else {
                    return terminate(.payloadDigestMismatch)
                }
                return .exactDuplicate(fragmentIndex: fragment.fragmentIndex)
            }
            guard fragment.fragmentIndex == fragmentsByIndex.count else {
                return terminate(.invalidAggregateFragmentIndex(
                    index: fragment.fragmentIndex,
                    count: reservation.fragmentCount
                ))
            }
            fragmentsByIndex[fragment.fragmentIndex] = fragment
            guard fragmentsByIndex.count == reservation.fragmentCount else {
                return .accepted(
                    received: fragmentsByIndex.count,
                    expected: reservation.fragmentCount
                )
            }

            let bytes = (0 ..< reservation.fragmentCount).flatMap {
                fragmentsByIndex[$0]!.body
            }
            let digest = RoleSeedValidator.hash(
                domainSuffix: reservation.aggregateKind.digestDomainSuffix,
                fields: [bytes]
            )
            guard digest == reservation.aggregateDigest else {
                return terminate(.payloadDigestMismatch)
            }
            let document: AggregateDocument
            do {
                document = try decodingContext.decode(
                    bytes,
                    kind: reservation.aggregateKind
                )
            } catch let error as ContractError {
                return terminate(error)
            } catch {
                return terminate(
                    .invalidCanonicalAggregate(reservation.aggregateKind)
                )
            }
            isTerminal = true
            fragmentsByIndex.removeAll(keepingCapacity: false)
            return .completed(document)
        }

        private mutating func terminate(_ error: ContractError) -> Decision {
            isTerminal = true
            fragmentsByIndex.removeAll(keepingCapacity: false)
            return .terminated(error)
        }
    }
}

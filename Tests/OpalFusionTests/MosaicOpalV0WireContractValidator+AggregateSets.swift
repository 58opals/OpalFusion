// MosaicOpalV0WireContractValidator+AggregateSets.swift

@testable import OpalFusion
import Testing

extension MosaicOpalV0WireContractValidator {
    @Test("Commitment sets sort 138 members and match the pinned digest")
    func validateCommitmentSetGoldenVector() throws {
        let commitments = try (0 ..< 138).reversed().map(Self.makeCommitment)
        let commitmentSet = try OpalV0.CommitmentSet(commitments: commitments)
        let encoded = Codec.encodeCommitmentSet(commitmentSet)
        let expected = Self.uint32Bytes(138)
            + (0 ..< 138).flatMap(Self.rawCommitmentBytes)

        #expect(encoded == expected)
        #expect(encoded.count == 17_944)
        #expect(
            Self.hexadecimal(commitmentSet.digest)
                == "3c0adbafb3a391fecf54a7bef2ebe0e683ff0b2e00525aa4a4c267c2f999f794"
        )
        #expect(try Codec.decodeCommitmentSet(from: encoded) == commitmentSet)
    }

    @Test("Component sets sort 138 members and match the pinned digest")
    func validateComponentSetGoldenVector() throws {
        let components = try (0 ..< 138).reversed().map(Self.makeBlankComponent)
        let componentSet = try OpalV0.ComponentSet(components: components)
        let encoded = Codec.encodeComponentSet(componentSet)
        let expected = Self.uint32Bytes(138)
            + (0 ..< 138).flatMap { Self.indexedDigest($0) + [0x02] }

        #expect(encoded == expected)
        #expect(encoded.count == 4_558)
        #expect(
            Self.hexadecimal(componentSet.digest)
                == "0686bc91051422c3558b4455e8807c92433ca8a3f4abc6fde15cbd1351db795f"
        )
        #expect(try Codec.decodeComponentSet(from: encoded) == componentSet)
    }

    @Test(
        "Aggregate sets accept every Opal v0 contributor count",
        arguments: [138, 161, 184]
    )
    func acceptEveryAggregateSetCount(memberCount: Int) throws {
        let commitments = try (0 ..< memberCount).map(Self.makeCommitment)
        let components = try (0 ..< memberCount).map(Self.makeBlankComponent)

        #expect(try OpalV0.CommitmentSet(commitments: commitments).commitments.count == memberCount)
        #expect(try OpalV0.ComponentSet(components: components).components.count == memberCount)
    }

    @Test("Aggregate sets reject invalid counts and duplicate members")
    func rejectInvalidAggregateSetMembership() throws {
        let commitments = try (0 ..< 138).map(Self.makeCommitment)
        #expect(throws: WireContractError.invalidCommitmentSetCount(actual: 137)) {
            _ = try OpalV0.CommitmentSet(
                commitments: Array(commitments.dropLast())
            )
        }
        var duplicateCommitments = commitments
        duplicateCommitments[137] = commitments[0]
        #expect(throws: WireContractError.duplicateCommitmentSetMember) {
            _ = try OpalV0.CommitmentSet(commitments: duplicateCommitments)
        }
        #expect(throws: WireContractError.invalidCommitmentSetCount(actual: 185)) {
            _ = try OpalV0.CommitmentSet(
                commitments: (0 ..< 185).map(Self.makeCommitment)
            )
        }

        let components = try (0 ..< 138).map(Self.makeBlankComponent)
        #expect(throws: WireContractError.invalidComponentSetCount(actual: 137)) {
            _ = try OpalV0.ComponentSet(components: Array(components.dropLast()))
        }
        var duplicateComponents = components
        duplicateComponents[137] = components[0]
        #expect(throws: WireContractError.duplicateComponentSetMember) {
            _ = try OpalV0.ComponentSet(components: duplicateComponents)
        }
        var duplicateSaltCommitments = components
        duplicateSaltCommitments[137] = try .init(
            saltCommitment: components[0].saltCommitment,
            payload: .input(
                try .init(
                    previousTransactionHash: Self.indexedDigest(500),
                    outputIndex: 0,
                    amountSatoshis: 1
                )
            )
        )
        #expect(throws: WireContractError.duplicateSaltCommitment) {
            _ = try OpalV0.ComponentSet(components: duplicateSaltCommitments)
        }
        #expect(throws: WireContractError.invalidComponentSetCount(actual: 185)) {
            _ = try OpalV0.ComponentSet(
                components: (0 ..< 185).map(Self.makeBlankComponent)
            )
        }
    }

    @Test("Component sets reject duplicate input outpoints across distinct members")
    func rejectDuplicateInputOutpoints() throws {
        var components = try (0 ..< 136).map(Self.makeBlankComponent)
        components.append(
            try Self.makeInputComponent(
                saltIndex: 1_000,
                transactionIndex: 77,
                outputIndex: 8,
                amountSatoshis: 9
            )
        )
        components.append(
            try Self.makeInputComponent(
                saltIndex: 1_001,
                transactionIndex: 77,
                outputIndex: 8,
                amountSatoshis: 10
            )
        )

        #expect(throws: WireContractError.duplicateInputOutpoint) {
            _ = try OpalV0.ComponentSet(components: components)
        }
    }

    @Test("Aggregate set decoders reject duplicate and descending canonical members")
    func rejectNoncanonicalAggregateSetBytes() throws {
        let ascending = (0 ..< 138).map(Self.rawCommitmentBytes)
        let duplicateBytes = Self.uint32Bytes(138)
            + ([ascending[0], ascending[0]] + Array(ascending.dropFirst(2)))
                .flatMap { $0 }
        #expect(
            throws: OpalFusion.Mosaic.CanonicalCodingError.duplicateSetMember
        ) {
            _ = try Codec.decodeCommitmentSet(from: duplicateBytes)
        }

        let descendingBytes = Self.uint32Bytes(138)
            + ascending.reversed().flatMap { $0 }
        #expect(
            throws: OpalFusion.Mosaic.CanonicalCodingError.nonCanonicalSetOrdering
        ) {
            _ = try Codec.decodeCommitmentSet(from: descendingBytes)
        }
    }

    @Test("Named payloads fit one inner envelope while aggregate sets require a later transport contract")
    func preserveTransportIndependentSizeBoundary() throws {
        let groupedBytes = try Codec.encodeGroupedCommitment(
            Self.makeGroupedCommitment()
        )
        let authorizationBytes = try Codec.encodeAuthorizationRequest(
            .init(
                slot: 0,
                blindedMessage: .init(
                    rawRepresentation: .init(repeating: 0xAA, count: 256)
                )
            )
        )
        let anonymousBytes = try Codec.encodeAnonymousComponent(
            .init(
                roundIdentifier: [UInt8](repeating: 0x11, count: 32),
                authorizationToken: Self.makeAuthorizationToken(),
                component: Self.makeBlankComponent(index: 0)
            )
        )
        let acknowledgementBytes = try Codec.encodePreSignAcknowledgement(
            .init(
                roundIdentifier: [UInt8](repeating: 0x11, count: 32),
                transcriptRoot: [UInt8](repeating: 0x22, count: 32)
            )
        )
        let commitmentSetBytes = Codec.encodeCommitmentSet(
            try .init(commitments: (0 ..< 138).map(Self.makeCommitment))
        )
        let componentSetBytes = Codec.encodeComponentSet(
            try .init(components: (0 ..< 138).map(Self.makeBlankComponent))
        )

        for bytes in [
            groupedBytes,
            authorizationBytes,
            anonymousBytes,
            acknowledgementBytes
        ] {
            #expect(bytes.count <= OpalV0.maximumInnerPayloadByteCount)
        }
        #expect(commitmentSetBytes.count > OpalV0.maximumInnerPayloadByteCount)
        #expect(componentSetBytes.count > OpalV0.maximumInnerPayloadByteCount)
    }

    @Test("Canonical set digests feed the existing transcript and pre-sign gate unchanged")
    func bindCanonicalSetsToHostTranscript() throws {
        let commitmentSet = try OpalV0.CommitmentSet(
            commitments: (0 ..< 138).map(Self.makeCommitment)
        )
        let componentSet = try OpalV0.ComponentSet(
            components: (0 ..< 138).map(Self.makeBlankComponent)
        )
        let manifestDigest = [UInt8](repeating: 0x41, count: 32)
        let unsignedTransactionBytes: [UInt8] = [0x02, 0x00]
        let transcriptRoot = try OpalFusion.Host.MosaicTranscriptBinding.transcriptRoot(
            profile: .opalV0,
            manifestDigest: manifestDigest,
            commitmentSetDigest: commitmentSet.digest,
            componentSetDigest: componentSet.digest,
            unsignedTransactionBytes: unsignedTransactionBytes
        )
        let binding = try OpalFusion.Host.MosaicTranscriptBinding(
            profile: .opalV0,
            manifestDigest: manifestDigest,
            commitmentSetDigest: commitmentSet.digest,
            componentSetDigest: componentSet.digest,
            unsignedTransactionBytes: unsignedTransactionBytes,
            acknowledgedTranscriptRoot: transcriptRoot
        )
        let acknowledgement = try OpalV0.PreSignAcknowledgementPayload(
            roundIdentifier: [UInt8](repeating: 0x33, count: 32),
            transcriptRoot: transcriptRoot
        )

        #expect(binding.commitmentSetDigest == commitmentSet.digest)
        #expect(binding.componentSetDigest == componentSet.digest)
        #expect(acknowledgement.transcriptRoot == binding.transcriptRoot)
    }
}

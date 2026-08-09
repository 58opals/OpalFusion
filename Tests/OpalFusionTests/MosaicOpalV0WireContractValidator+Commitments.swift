// MosaicOpalV0WireContractValidator+Commitments.swift

import Foundation
@testable import OpalFusion
import Testing

extension MosaicOpalV0WireContractValidator {
    @Test("Component commitments normalize keys and match the pinned byte vector")
    func validateComponentCommitmentGoldenVector() throws {
        let commitment = try Self.makeCommitment(index: 9)
        let encoded = try Codec.encodeComponentCommitment(commitment)

        #expect(
            commitment.amountCommitment
                == Self.amountCommitmentKeys[9].uncompressed
        )
        #expect(
            commitment.communicationPublicKey
                == Self.communicationKeys[9].compressed
        )
        #expect(encoded == Self.rawCommitmentBytes(index: 9))
        #expect(try Codec.decodeComponentCommitment(from: encoded) == commitment)
    }

    @Test("Grouped commitments preserve all 23 slots in their pinned field order")
    func validateGroupedCommitmentGoldenVector() throws {
        let payload = try Self.makeGroupedCommitment()
        let encoded = try Codec.encodeGroupedCommitment(payload)
        let expected = Self.uint32Bytes(23)
            + (0 ..< 23).flatMap(Self.rawCommitmentBytes)
            + [UInt8](repeating: 0, count: 8)
            + [UInt8](repeating: 0, count: 31)
            + [0x01]

        #expect(encoded == expected)
        #expect(encoded.count == 3_034)
        #expect(
            Self.sha256Hexadecimal(encoded)
                == "2e7ae6caeb62ba93c2d9d61010bbe33a747f134c69d408e1029022c9a38e995b"
        )
        #expect(try Codec.decodeGroupedCommitment(from: encoded) == payload)
    }

    @Test("Fixed canonical fields reject the wrong byte count and truncated input")
    func rejectMalformedFixedCanonicalFields() {
        var encoder = OpalFusion.Mosaic.CanonicalEncoder()
        #expect(
            throws: OpalFusion.Mosaic.CanonicalCodingError
                .invalidFixedByteCount(expected: 2, actual: 1)
        ) {
            try encoder.writeFixedBytes([0x01], byteCount: 2)
        }
        #expect(
            throws: OpalFusion.Mosaic.CanonicalCodingError
                .truncatedInput(expectedByteCount: 2, remainingByteCount: 1)
        ) {
            _ = try OpalFusion.Mosaic.CanonicalDecoder.decode(from: [0x01]) {
                try $0.readFixedBytes(byteCount: 2)
            }
        }
    }

    @Test("Component commitments reject malformed digests and curve points")
    func rejectMalformedComponentCommitments() {
        #expect(
            throws: WireContractError.invalidSaltedComponentDigestLength(actual: 31)
        ) {
            _ = try OpalV0.ComponentCommitment(
                saltedComponentDigest: [UInt8](repeating: 0, count: 31),
                amountCommitment: Self.compressedGenerator,
                communicationPublicKey: Self.compressedGenerator
            )
        }
        #expect(throws: WireContractError.invalidAmountCommitment) {
            _ = try OpalV0.ComponentCommitment(
                saltedComponentDigest: Self.indexedDigest(0),
                amountCommitment: [UInt8](repeating: 0, count: 65),
                communicationPublicKey: Self.compressedGenerator
            )
        }
        #expect(throws: WireContractError.invalidCommunicationPublicKey) {
            _ = try OpalV0.ComponentCommitment(
                saltedComponentDigest: Self.indexedDigest(0),
                amountCommitment: Self.compressedGenerator,
                communicationPublicKey: [UInt8](repeating: 0, count: 33)
            )
        }
    }

    @Test("Grouped commitments reject count, duplicate, fee, and nonce violations")
    func rejectMalformedGroupedCommitments() throws {
        let commitments = try (0 ..< 23).map(Self.makeCommitment)
        let nonce = [UInt8](repeating: 0, count: 31) + [0x01]

        #expect(throws: WireContractError.invalidGroupedCommitmentCount(actual: 22)) {
            _ = try OpalV0.GroupedCommitmentPayload(
                commitments: Array(commitments.dropLast()),
                excessFeeSatoshis: 0,
                pedersenTotalNonce: nonce
            )
        }

        var duplicated = commitments
        duplicated[22] = commitments[0]
        #expect(throws: WireContractError.duplicateGroupedCommitment) {
            _ = try OpalV0.GroupedCommitmentPayload(
                commitments: duplicated,
                excessFeeSatoshis: 0,
                pedersenTotalNonce: nonce
            )
        }

        var duplicateSaltedDigest = commitments
        duplicateSaltedDigest[22] = try .init(
            saltedComponentDigest: commitments[0].saltedComponentDigest,
            amountCommitment: commitments[22].amountCommitment,
            communicationPublicKey: commitments[22].communicationPublicKey
        )
        #expect(throws: WireContractError.duplicateSaltedComponentDigest) {
            _ = try OpalV0.GroupedCommitmentPayload(
                commitments: duplicateSaltedDigest,
                excessFeeSatoshis: 0,
                pedersenTotalNonce: nonce
            )
        }

        var duplicateAmountCommitment = commitments
        duplicateAmountCommitment[22] = try .init(
            saltedComponentDigest: commitments[22].saltedComponentDigest,
            amountCommitment: commitments[0].amountCommitment,
            communicationPublicKey: commitments[22].communicationPublicKey
        )
        #expect(throws: WireContractError.duplicateAmountCommitment) {
            _ = try OpalV0.GroupedCommitmentPayload(
                commitments: duplicateAmountCommitment,
                excessFeeSatoshis: 0,
                pedersenTotalNonce: nonce
            )
        }

        var duplicateCommunicationKey = commitments
        duplicateCommunicationKey[22] = try .init(
            saltedComponentDigest: commitments[22].saltedComponentDigest,
            amountCommitment: commitments[22].amountCommitment,
            communicationPublicKey: commitments[0].communicationPublicKey
        )
        #expect(throws: WireContractError.duplicateCommunicationPublicKey) {
            _ = try OpalV0.GroupedCommitmentPayload(
                commitments: duplicateCommunicationKey,
                excessFeeSatoshis: 0,
                pedersenTotalNonce: nonce
            )
        }

        #expect(throws: WireContractError.nonzeroExcessFee(actual: 1)) {
            _ = try OpalV0.GroupedCommitmentPayload(
                commitments: commitments,
                excessFeeSatoshis: 1,
                pedersenTotalNonce: nonce
            )
        }

        #expect(throws: WireContractError.invalidPedersenTotalNonce) {
            _ = try OpalV0.GroupedCommitmentPayload(
                commitments: commitments,
                excessFeeSatoshis: 0,
                pedersenTotalNonce: [UInt8](repeating: 0xFF, count: 32)
            )
        }

        let mainnetPayload = try OpalV0.GroupedCommitmentPayload(
            profile: .opalMainnetAlpha,
            commitments: commitments,
            excessFeeSatoshis: 1,
            pedersenTotalNonce: nonce
        )
        #expect(throws: WireContractError.unsupportedProfile(.opalMainnetAlpha)) {
            _ = try Codec.encodeGroupedCommitment(mainnetPayload)
        }
    }
}

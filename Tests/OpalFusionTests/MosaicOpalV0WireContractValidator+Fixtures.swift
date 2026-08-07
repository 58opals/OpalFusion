// MosaicOpalV0WireContractValidator+Fixtures.swift

import Foundation
import OpalCrypto
@testable import OpalFusion

extension MosaicOpalV0WireContractValidator {
    struct PublicKeyFixture: Sendable {
        let compressed: [UInt8]
        let uncompressed: [UInt8]
    }

    typealias OpalV0 = OpalFusion.Mosaic.OpalV0
    typealias Codec = OpalFusion.Mosaic.OpalV0.CanonicalWireCodec
    typealias WireContractError = OpalFusion.Mosaic.OpalV0.WireContractError

    static let generatorX = bytes(
        hexadecimal: "79be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798"
    )
    static let generatorY = bytes(
        hexadecimal: "483ada7726a3c4655da4fbfc0e1108a8fd17b448a68554199c47d08ffb10d4b8"
    )
    static let compressedGenerator = [UInt8(0x02)] + generatorX
    static let uncompressedGenerator = [UInt8(0x04)] + generatorX + generatorY
    static let amountCommitmentKeys = try! (0 ..< 185).map { index in
        try publicKeyFixture(scalar: index + 1)
    }
    static let communicationKeys = try! (0 ..< 185).map { index in
        try publicKeyFixture(scalar: index + 1_000)
    }

    static func bytes(hexadecimal: String) -> [UInt8] {
        let utf8 = Array(hexadecimal.utf8)
        precondition(utf8.count.isMultiple(of: 2))
        return stride(from: 0, to: utf8.count, by: 2).map { index in
            let pair = String(decoding: utf8[index ..< index + 2], as: UTF8.self)
            return UInt8(pair, radix: 16)!
        }
    }

    static func hexadecimal(_ bytes: [UInt8]) -> String {
        let digits = Array("0123456789abcdef".utf8)
        return String(
            decoding: bytes.flatMap { byte in
                [digits[Int(byte >> 4)], digits[Int(byte & 0x0F)]]
            },
            as: UTF8.self
        )
    }

    static func sha256Hexadecimal(_ bytes: [UInt8]) -> String {
        hexadecimal([UInt8](OpalCrypto.Hashing.sha256(Data(bytes))))
    }

    static func indexedDigest(_ index: Int) -> [UInt8] {
        precondition((0 ... Int(UInt16.max)).contains(index))
        return [UInt8](repeating: 0, count: 30) + [
            UInt8(truncatingIfNeeded: index >> 8),
            UInt8(truncatingIfNeeded: index)
        ]
    }

    static func rawCommitmentBytes(index: Int) -> [UInt8] {
        indexedDigest(index)
            + amountCommitmentKeys[index].uncompressed
            + communicationKeys[index].compressed
    }

    static func makeCommitment(
        index: Int
    ) throws -> OpalV0.ComponentCommitment {
        try .init(
            saltedComponentDigest: indexedDigest(index),
            amountCommitment: amountCommitmentKeys[index].compressed,
            communicationPublicKey: communicationKeys[index].uncompressed
        )
    }

    static func publicKeyFixture(scalar: Int) throws -> PublicKeyFixture {
        let publicKey = try OpalCrypto.Secp256k1.derivePublicKey(
            from: OpalCrypto.Secp256k1.PrivateKey(
                rawRepresentation: Data(indexedDigest(scalar))
            )
        )
        return .init(
            compressed: [UInt8](publicKey.compressedRepresentation),
            uncompressed: [UInt8](publicKey.uncompressedRepresentation)
        )
    }

    static func makeGroupedCommitment() throws -> OpalV0.GroupedCommitmentPayload {
        try .init(
            commitments: (0 ..< OpalV0.componentAuthorizationCountPerContributor)
                .map(makeCommitment),
            excessFeeSatoshis: 0,
            pedersenTotalNonce: [UInt8](repeating: 0, count: 31) + [0x01]
        )
    }

    static func makeAuthorizationToken(
        roundIdentifier: [UInt8] = [UInt8](repeating: 0x11, count: 32)
    ) throws -> OpalV0.AuthorizationToken {
        .init(
            input: try .init(
                roundIdentifier: roundIdentifier,
                keyIdentifier: [UInt8](repeating: 0x22, count: 32),
                nonce: [UInt8](repeating: 0x33, count: 32)
            ),
            messageRandomizer: try .init(
                rawRepresentation: Data(repeating: 0x44, count: 32)
            ),
            signature: try .init(
                rawRepresentation: Data(repeating: 0x55, count: 256)
            )
        )
    }

    static func rawAuthorizationTokenBytes(
        roundIdentifier: [UInt8] = [UInt8](repeating: 0x11, count: 32)
    ) -> [UInt8] {
        roundIdentifier
            + [UInt8](repeating: 0x22, count: 32)
            + [UInt8](repeating: 0x33, count: 32)
            + [UInt8](repeating: 0x44, count: 32)
            + [UInt8](repeating: 0x55, count: 256)
    }

    static func p2pkhLockingScript(fill: UInt8 = 0x66) -> [UInt8] {
        [0x76, 0xA9, 0x14]
            + [UInt8](repeating: fill, count: 20)
            + [0x88, 0xAC]
    }

    static func makeBlankComponent(index: Int) throws -> OpalV0.Component {
        try .init(
            saltCommitment: indexedDigest(index),
            payload: .blank
        )
    }

    static func makeInputComponent(
        saltIndex: Int = 1,
        transactionIndex: Int = 2,
        outputIndex: UInt32 = 3,
        amountSatoshis: UInt64 = 4
    ) throws -> OpalV0.Component {
        try .init(
            saltCommitment: indexedDigest(saltIndex),
            payload: .input(
                try .init(
                    previousTransactionHash: indexedDigest(transactionIndex),
                    outputIndex: outputIndex,
                    amountSatoshis: amountSatoshis
                )
            )
        )
    }

    static func makeOutputComponent(
        saltIndex: Int = 5,
        fill: UInt8 = 0x66,
        amountSatoshis: UInt64 = 7
    ) throws -> OpalV0.Component {
        try .init(
            saltCommitment: indexedDigest(saltIndex),
            payload: .output(
                try .init(
                    lockingScript: p2pkhLockingScript(fill: fill),
                    amountSatoshis: amountSatoshis
                )
            )
        )
    }

    static func uint32Bytes(_ value: UInt32) -> [UInt8] {
        [
            UInt8(truncatingIfNeeded: value >> 24),
            UInt8(truncatingIfNeeded: value >> 16),
            UInt8(truncatingIfNeeded: value >> 8),
            UInt8(truncatingIfNeeded: value)
        ]
    }

    static func uint64Bytes(_ value: UInt64) -> [UInt8] {
        [
            UInt8(truncatingIfNeeded: value >> 56),
            UInt8(truncatingIfNeeded: value >> 48),
            UInt8(truncatingIfNeeded: value >> 40),
            UInt8(truncatingIfNeeded: value >> 32),
            UInt8(truncatingIfNeeded: value >> 24),
            UInt8(truncatingIfNeeded: value >> 16),
            UInt8(truncatingIfNeeded: value >> 8),
            UInt8(truncatingIfNeeded: value)
        ]
    }
}

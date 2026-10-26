// MosaicMainnetAlphaSlotRecipientValidator.swift

import Foundation
import OpalCrypto
import Testing
@testable import MosaicEngine
@testable import OpalFusionCore

@Suite("Mosaic slot-recipient x-only validation")
struct MosaicMainnetAlphaSlotRecipientValidator {
    typealias Alpha = OpalFusion.Mosaic.OpalMainnetAlpha

    struct RecipientCase: Sendable {
        let identity: [UInt8]
        let accepted: Bool
    }

    @Test(
        "Slot recipients retain the BIP340 acceptance domain and exact bytes",
        arguments: [
            RecipientCase(identity: [], accepted: false),
            RecipientCase(identity: [UInt8](repeating: 0, count: 31), accepted: false),
            RecipientCase(identity: [UInt8](repeating: 0, count: 33), accepted: false),
            // Zero and p-1 produce non-residues; neither lifts to a curve point.
            RecipientCase(identity: [UInt8](repeating: 0, count: 32), accepted: false),
            RecipientCase(identity: scalarBytes(1), accepted: true),
            RecipientCase(
                identity: bytes("79be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798"),
                accepted: true
            ),
            // Official BIP340 vector 0's x-only public key.
            RecipientCase(
                identity: bytes("f9308a019258c31049344f85f89d5229b531c845836f99b08601f113bce036f9"),
                accepted: true
            ),
            RecipientCase(
                identity: bytes("fffffffffffffffffffffffffffffffffffffffffffffffffffffffefffffc2e"),
                accepted: false
            ),
            // Canonical field boundary p, p+1, and the largest 256-bit value.
            RecipientCase(
                identity: bytes("fffffffffffffffffffffffffffffffffffffffffffffffffffffffefffffc2f"),
                accepted: false
            ),
            RecipientCase(
                identity: bytes("fffffffffffffffffffffffffffffffffffffffffffffffffffffffefffffc30"),
                accepted: false
            ),
            RecipientCase(identity: [UInt8](repeating: 0xff, count: 32), accepted: false),
            // A complete SEC1 encoding is not a 32-byte x-only identity.
            RecipientCase(
                identity: [0x02] + bytes("79be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798"),
                accepted: false
            )
        ]
    )
    func preserveRecipientAcceptanceAndBytes(sample: RecipientCase) throws {
        let originalAccepts = (try? OpalCrypto.Signature.BIP340.VerificationKey(
            rawRepresentation: Data(sample.identity)
        )) != nil
        #expect(originalAccepts == sample.accepted)

        if sample.accepted {
            let secrets = try Self.makeSecrets(recipient: sample.identity)
            #expect(secrets.recipientEventIdentity == sample.identity)
        } else {
            #expect(throws: Alpha.ComponentSlotSecrets.ValidationError.invalidRecipientEventIdentity) {
                _ = try Self.makeSecrets(recipient: sample.identity)
            }
        }
    }

    @Test("Salt and authorization-nonce failures precede recipient validation")
    func preserveMalformedFieldPrecedence() throws {
        let invalidRecipient = [UInt8](repeating: 0, count: 32)
        #expect(throws: Alpha.ComponentSlotSecrets.ValidationError.invalidSaltLength(actual: 31)) {
            _ = try Self.makeSecrets(
                recipient: invalidRecipient,
                saltCount: 31,
                componentNonceCount: 31,
                bchNonceCount: 31
            )
        }
        #expect(throws: Alpha.ComponentSlotSecrets.ValidationError.invalidComponentAuthorizationNonceLength(actual: 31)) {
            _ = try Self.makeSecrets(
                recipient: invalidRecipient,
                componentNonceCount: 31,
                bchNonceCount: 31
            )
        }
        #expect(throws: Alpha.ComponentSlotSecrets.ValidationError.invalidBCHSignatureAuthorizationNonceLength(actual: 31)) {
            _ = try Self.makeSecrets(
                recipient: invalidRecipient,
                bchNonceCount: 31
            )
        }
    }

    private static func makeSecrets(
        recipient: [UInt8],
        saltCount: Int = 32,
        componentNonceCount: Int = 32,
        bchNonceCount: Int = 32
    ) throws -> Alpha.ComponentSlotSecrets {
        try .init(
            salt: [UInt8](repeating: 0xa1, count: saltCount),
            pedersenNonce: .init(rawRepresentation: Data(scalarBytes(1))),
            communicationPrivateKey: .init(rawRepresentation: Data(scalarBytes(2))),
            componentEnvelopePrivateKey: .init(rawRepresentation: Data(scalarBytes(3))),
            bchSignatureEnvelopePrivateKey: .init(rawRepresentation: Data(scalarBytes(4))),
            componentAuthorizationNonce: [UInt8](repeating: 0xb1, count: componentNonceCount),
            bchSignatureAuthorizationNonce: [UInt8](repeating: 0xc1, count: bchNonceCount),
            recipientEventIdentity: recipient
        )
    }

    private static func scalarBytes(_ value: UInt8) -> [UInt8] {
        [UInt8](repeating: 0, count: 31) + [value]
    }

    private static func bytes(_ hexadecimal: String) -> [UInt8] {
        MosaicOpalV0WireContractValidator.bytes(hexadecimal: hexadecimal)
    }
}

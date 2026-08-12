// MosaicMainnetAlphaPostManifestTransportIngressValidator.swift

import Foundation
import OpalCrypto
import Testing
@testable import OpalFusion

@Suite("Mosaic mainnet-alpha post-manifest transport ingress model")
struct MosaicMainnetAlphaPostManifestTransportIngressValidator {
    typealias Alpha = OpalFusion.Mosaic.OpalMainnetAlpha
    typealias Ingress = Alpha.PostManifestTransportIngress
    typealias Nostr = OpalFusion.Mosaic.NostrNamespace

    @Test("Require distinct recipient identities and exact lookup")
    func validateRecipientSet() throws {
        #expect(throws: Ingress.RecipientSet.ValidationError.empty) {
            _ = try Ingress.RecipientSet([])
        }

        let recipient = try signingKey(20)
        #expect(
            throws: Ingress.RecipientSet.ValidationError
                .duplicateRecipientIdentity
        ) {
            _ = try Ingress.RecipientSet([
                .init(channel: .control, signingKey: recipient),
                .init(channel: .anonymous, signingKey: recipient),
            ])
        }

        let positiveScalar = try OpalCrypto.Secp256k1.SigningKey(
            rawRepresentation: try Nostr.EventCodec.decodeHexadecimal(
                String(repeating: "00", count: 31) + "01",
                field: "positiveScalar"
            )
        )
        let negativeScalar = try OpalCrypto.Secp256k1.SigningKey(
            rawRepresentation: try Nostr.EventCodec.decodeHexadecimal(
                "fffffffffffffffffffffffffffffffebaaedce6af48a03bbfd25e8cd0364140",
                field: "negativeScalar"
            )
        )
        #expect(
            positiveScalar.verificationKey.rawRepresentation
                != negativeScalar.verificationKey.rawRepresentation
        )
        #expect(
            positiveScalar.bip340VerificationKey
                == negativeScalar.bip340VerificationKey
        )
        #expect(
            throws: Ingress.RecipientSet.ValidationError
                .duplicateRecipientIdentity
        ) {
            _ = try Ingress.RecipientSet([
                .init(channel: .control, signingKey: positiveScalar),
                .init(channel: .anonymous, signingKey: negativeScalar),
            ])
        }

        let anonymous = try signingKey(21)
        let recipients = try Ingress.RecipientSet([
            .init(channel: .control, signingKey: recipient),
            .init(channel: .anonymous, signingKey: anonymous),
        ])
        #expect(
            recipients.capability(
                for: recipient.bip340VerificationKey.rawRepresentation
            )?.channel == .control
        )
        #expect(
            recipients.capability(
                for: anonymous.bip340VerificationKey.rawRepresentation
            )?.channel == .anonymous
        )
        #expect(
            recipients.capability(
                for: Data(repeating: 0xFF, count: 32)
            ) == nil
        )
    }

    private func signingKey(
        _ scalarByte: UInt8
    ) throws -> OpalCrypto.Secp256k1.SigningKey {
        try .init(
            rawRepresentation: Data(repeating: 0, count: 31)
                + Data([scalarByte])
        )
    }
}

// OpalFusion+Mosaic+OpalMainnetAlpha+CanonicalWireCodec~Authorization.swift

import Foundation
import OpalCrypto

extension OpalFusion.Mosaic.OpalMainnetAlpha.CanonicalWireCodec {
    static func encodeAuthorizationToken(
        _ token: OpalFusion.Mosaic.OpalMainnetAlpha.AuthorizationToken
    ) throws -> [UInt8] {
        var encoder = OpalFusion.Mosaic.CanonicalEncoder()
        try writeAuthorizationToken(token, to: &encoder)
        return encoder.encodedBytes
    }

    static func decodeAuthorizationToken(
        from encodedBytes: [UInt8]
    ) throws -> OpalFusion.Mosaic.OpalMainnetAlpha.AuthorizationToken {
        try OpalFusion.Mosaic.CanonicalDecoder.decode(from: encodedBytes) { decoder in
            try readAuthorizationToken(from: &decoder)
        }
    }

    static func writeAuthorizationToken(
        _ token: OpalFusion.Mosaic.OpalMainnetAlpha.AuthorizationToken,
        to encoder: inout OpalFusion.Mosaic.CanonicalEncoder
    ) throws {
        try encoder.writeFixedBytes(token.input.roundIdentifier, byteCount: 32)
        try encoder.writeFixedBytes(token.input.keyIdentifier, byteCount: 32)
        encoder.writeUInt8(token.input.purpose.rawValue)
        try encoder.writeFixedBytes(token.input.nonce, byteCount: 32)
        try encoder.writeFixedBytes(token.input.binding, byteCount: 32)
        try encoder.writeFixedBytes(
            [UInt8](token.messageRandomizer.rawRepresentation),
            byteCount: 32
        )
        try encoder.writeFixedBytes(
            [UInt8](token.signature.rawRepresentation),
            byteCount: OpalFusion.Mosaic.OpalV0.authorizationMaterialByteCount
        )
    }

    static func readAuthorizationToken(
        from decoder: inout OpalFusion.Mosaic.CanonicalDecoder
    ) throws -> OpalFusion.Mosaic.OpalMainnetAlpha.AuthorizationToken {
        let roundIdentifier = try decoder.readFixedBytes(byteCount: 32)
        let keyIdentifier = try decoder.readFixedBytes(byteCount: 32)
        let rawPurpose = try decoder.readUInt8()
        guard let purpose = OpalFusion.Mosaic.OpalMainnetAlpha
            .AuthorizationPurpose(rawValue: rawPurpose) else {
            throw OpalFusion.Mosaic.OpalMainnetAlpha.ContractError
                .invalidAuthorizationPurpose(rawPurpose)
        }
        let input = try OpalFusion.Mosaic.OpalMainnetAlpha.AuthorizationTokenInput(
            roundIdentifier: roundIdentifier,
            keyIdentifier: keyIdentifier,
            purpose: purpose,
            nonce: decoder.readFixedBytes(byteCount: 32),
            binding: decoder.readFixedBytes(byteCount: 32)
        )
        return .init(
            input: input,
            messageRandomizer: try OpalCrypto.RSABSSA.MessageRandomizer(
                rawRepresentation: Data(try decoder.readFixedBytes(byteCount: 32))
            ),
            signature: try OpalCrypto.RSABSSA.Signature(
                rawRepresentation: Data(
                    try decoder.readFixedBytes(
                        byteCount: OpalFusion.Mosaic.OpalV0.authorizationMaterialByteCount
                    )
                )
            )
        )
    }
}

// OpalFusion+Mosaic+OpalV0+CanonicalWireCodec~Authorization.swift

import Foundation
import OpalCrypto

extension OpalFusion.Mosaic.OpalV0.CanonicalWireCodec {
    static func encodeAuthorizationRequest(
        _ payload: OpalFusion.Mosaic.OpalV0.AuthorizationRequestPayload
    ) throws -> [UInt8] {
        var encoder = OpalFusion.Mosaic.CanonicalEncoder()
        encoder.writeUInt8(UInt8(payload.slot))
        try encoder.writeFixedBytes(
            [UInt8](payload.blindedMessage.rawRepresentation),
            byteCount: OpalFusion.Mosaic.OpalV0.authorizationMaterialByteCount
        )
        return encoder.encodedBytes
    }

    static func decodeAuthorizationRequest(
        from encodedBytes: [UInt8]
    ) throws -> OpalFusion.Mosaic.OpalV0.AuthorizationRequestPayload {
        try OpalFusion.Mosaic.CanonicalDecoder.decode(from: encodedBytes) { decoder in
            try .init(
                slot: Int(decoder.readUInt8()),
                blindedMessage: OpalCrypto.RSABSSA.BlindedMessage(
                    rawRepresentation: Data(
                        try decoder.readFixedBytes(
                            byteCount: OpalFusion.Mosaic.OpalV0.authorizationMaterialByteCount
                        )
                    )
                )
            )
        }
    }

    static func encodeAuthorizationResponse(
        _ payload: OpalFusion.Mosaic.OpalV0.AuthorizationResponsePayload
    ) throws -> [UInt8] {
        var encoder = OpalFusion.Mosaic.CanonicalEncoder()
        encoder.writeUInt8(UInt8(payload.slot))
        try encoder.writeFixedBytes(
            [UInt8](payload.blindSignature.rawRepresentation),
            byteCount: OpalFusion.Mosaic.OpalV0.authorizationMaterialByteCount
        )
        return encoder.encodedBytes
    }

    static func decodeAuthorizationResponse(
        from encodedBytes: [UInt8]
    ) throws -> OpalFusion.Mosaic.OpalV0.AuthorizationResponsePayload {
        try OpalFusion.Mosaic.CanonicalDecoder.decode(from: encodedBytes) { decoder in
            try .init(
                slot: Int(decoder.readUInt8()),
                blindSignature: OpalCrypto.RSABSSA.BlindSignature(
                    rawRepresentation: Data(
                        try decoder.readFixedBytes(
                            byteCount: OpalFusion.Mosaic.OpalV0.authorizationMaterialByteCount
                        )
                    )
                )
            )
        }
    }

    static func encodeAuthorizationToken(
        _ token: OpalFusion.Mosaic.OpalV0.AuthorizationToken
    ) throws -> [UInt8] {
        var encoder = OpalFusion.Mosaic.CanonicalEncoder()
        try writeAuthorizationToken(token, to: &encoder)
        return encoder.encodedBytes
    }

    static func decodeAuthorizationToken(
        from encodedBytes: [UInt8],
        profile: OpalFusion.Mosaic.Profile = .opalV0
    ) throws -> OpalFusion.Mosaic.OpalV0.AuthorizationToken {
        try OpalFusion.Mosaic.CanonicalDecoder.decode(from: encodedBytes) { decoder in
            try readAuthorizationToken(from: &decoder, profile: profile)
        }
    }

    static func writeAuthorizationToken(
        _ token: OpalFusion.Mosaic.OpalV0.AuthorizationToken,
        to encoder: inout OpalFusion.Mosaic.CanonicalEncoder
    ) throws {
        try encoder.writeFixedBytes(
            token.input.roundIdentifier,
            byteCount: OpalFusion.Mosaic.OpalV0.digestByteCount
        )
        try encoder.writeFixedBytes(
            token.input.keyIdentifier,
            byteCount: OpalFusion.Mosaic.OpalV0.digestByteCount
        )
        try encoder.writeFixedBytes(
            token.input.nonce,
            byteCount: OpalFusion.Mosaic.OpalV0.digestByteCount
        )
        try encoder.writeFixedBytes(
            [UInt8](token.messageRandomizer.rawRepresentation),
            byteCount: OpalFusion.Mosaic.OpalV0.digestByteCount
        )
        try encoder.writeFixedBytes(
            [UInt8](token.signature.rawRepresentation),
            byteCount: OpalFusion.Mosaic.OpalV0.authorizationMaterialByteCount
        )
    }

    static func readAuthorizationToken(
        from decoder: inout OpalFusion.Mosaic.CanonicalDecoder,
        profile: OpalFusion.Mosaic.Profile = .opalV0
    ) throws -> OpalFusion.Mosaic.OpalV0.AuthorizationToken {
        let input = try OpalFusion.Mosaic.OpalV0.AuthorizationTokenInput(
            profile: profile,
            roundIdentifier: decoder.readFixedBytes(
                byteCount: OpalFusion.Mosaic.OpalV0.digestByteCount
            ),
            keyIdentifier: decoder.readFixedBytes(
                byteCount: OpalFusion.Mosaic.OpalV0.digestByteCount
            ),
            nonce: decoder.readFixedBytes(
                byteCount: OpalFusion.Mosaic.OpalV0.digestByteCount
            )
        )
        return .init(
            input: input,
            messageRandomizer: try OpalCrypto.RSABSSA.MessageRandomizer(
                rawRepresentation: Data(
                    try decoder.readFixedBytes(
                        byteCount: OpalFusion.Mosaic.OpalV0.digestByteCount
                    )
                )
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

// OpalFusion+Mosaic+OpalMainnetAlpha+CanonicalWireCodec~AuthorizationResponseSet.swift

import Foundation
import OpalCrypto

extension OpalFusion.Mosaic.OpalMainnetAlpha.CanonicalWireCodec {
    static func encodeAuthorizationResponseSet(
        _ responseSet: OpalFusion.Mosaic.OpalMainnetAlpha
            .AuthorizationResponseSet
    ) -> [UInt8] {
        responseSet.canonicalBytes
    }

    static func encodeAuthorizationResponseSet(
        roundIdentifier: [UInt8],
        contributor: OpalFusion.Mosaic.Attempt.ControlIdentity,
        playerCommitDigest: [UInt8],
        componentAuthorizationResponses: [
            OpalFusion.Mosaic.OpalV0.AuthorizationResponsePayload
        ],
        bchSignatureAuthorizationResponses: [
            OpalFusion.Mosaic.OpalV0.AuthorizationResponsePayload
        ]
    ) throws -> [UInt8] {
        var encoder = OpalFusion.Mosaic.CanonicalEncoder()
        try encoder.writeFixedBytes(roundIdentifier, byteCount: 32)
        try encoder.writeFixedBytes(contributor.validatedBytes, byteCount: 32)
        try encoder.writeFixedBytes(playerCommitDigest, byteCount: 32)
        try writeAuthorizationResponses(
            componentAuthorizationResponses,
            to: &encoder
        )
        try writeAuthorizationResponses(
            bchSignatureAuthorizationResponses,
            to: &encoder
        )
        return encoder.encodedBytes
    }

    private static func writeAuthorizationResponses(
        _ responses: [OpalFusion.Mosaic.OpalV0.AuthorizationResponsePayload],
        to encoder: inout OpalFusion.Mosaic.CanonicalEncoder
    ) throws {
        try encoder.writeVector(responses) { encoder, response in
            encoder.writeUInt8(UInt8(response.slot))
            try encoder.writeFixedBytes(
                [UInt8](response.blindSignature.rawRepresentation),
                byteCount: OpalFusion.Mosaic.OpalV0.authorizationMaterialByteCount
            )
        }
    }

    static func decodeAuthorizationResponseSet(
        from encodedBytes: [UInt8]
    ) throws -> OpalFusion.Mosaic.OpalMainnetAlpha.AuthorizationResponseSet {
        try OpalFusion.Mosaic.CanonicalDecoder.decode(from: encodedBytes) { decoder in
            let roundIdentifier = try decoder.readFixedBytes(byteCount: 32)
            let contributor = OpalFusion.Mosaic.Attempt.ControlIdentity(
                validatedBytes: try decoder.readFixedBytes(byteCount: 32)
            )
            let playerCommitDigest = try decoder.readFixedBytes(byteCount: 32)
            let componentAuthorizationResponses = try readAuthorizationResponses(
                from: &decoder
            )
            let bchSignatureAuthorizationResponses = try readAuthorizationResponses(
                from: &decoder
            )
            return try .init(
                roundIdentifier: roundIdentifier,
                contributor: contributor,
                playerCommitDigest: playerCommitDigest,
                componentAuthorizationResponses:
                    componentAuthorizationResponses,
                bchSignatureAuthorizationResponses:
                    bchSignatureAuthorizationResponses
            )
        }
    }

    private static func readAuthorizationResponses(
        from decoder: inout OpalFusion.Mosaic.CanonicalDecoder
    ) throws -> [OpalFusion.Mosaic.OpalV0.AuthorizationResponsePayload] {
        try decoder.readVector { decoder in
                try OpalFusion.Mosaic.OpalV0.AuthorizationResponsePayload(
                    slot: Int(decoder.readUInt8()),
                    blindSignature: OpalCrypto.RSABSSA.BlindSignature(
                        rawRepresentation: Data(
                            try decoder.readFixedBytes(
                                byteCount: OpalFusion.Mosaic.OpalV0
                                    .authorizationMaterialByteCount
                            )
                        )
                    )
                )
            }
    }
}

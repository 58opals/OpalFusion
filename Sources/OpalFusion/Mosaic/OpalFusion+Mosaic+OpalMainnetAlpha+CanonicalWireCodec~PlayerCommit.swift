// OpalFusion+Mosaic+OpalMainnetAlpha+CanonicalWireCodec~PlayerCommit.swift

import Foundation
import OpalCrypto

extension OpalFusion.Mosaic.OpalMainnetAlpha.CanonicalWireCodec {
    static func encodePlayerCommit(
        _ playerCommit: OpalFusion.Mosaic.OpalMainnetAlpha.PlayerCommit
    ) -> [UInt8] {
        playerCommit.canonicalBytes
    }

    static func decodePlayerCommit(
        from encodedBytes: [UInt8]
    ) throws -> OpalFusion.Mosaic.OpalMainnetAlpha.PlayerCommit {
        try OpalFusion.Mosaic.CanonicalDecoder.decode(from: encodedBytes) { decoder in
            let roundIdentifier = try decoder.readFixedBytes(byteCount: 32)
            let contributor = OpalFusion.Mosaic.Attempt.ControlIdentity(
                validatedBytes: try decoder.readFixedBytes(byteCount: 32)
            )
            let groupedCommitment = try OpalFusion.Mosaic.OpalV0
                .GroupedCommitmentPayload(
                    profile: .opalMainnetAlpha,
                    commitments: decoder.readVector(
                        readingValueWith: OpalFusion.Mosaic.OpalV0
                            .CanonicalWireCodec.readComponentCommitment
                    ),
                    excessFeeSatoshis: decoder.readUInt64(),
                    pedersenTotalNonce: decoder.readFixedBytes(byteCount: 32)
                )
            let componentAuthorizationRequests = try decoder.readVector { decoder in
                try OpalFusion.Mosaic.OpalV0.AuthorizationRequestPayload(
                    slot: Int(decoder.readUInt8()),
                    blindedMessage: OpalCrypto.RSABSSA.BlindedMessage(
                        rawRepresentation: Data(
                            try decoder.readFixedBytes(
                                byteCount: OpalFusion.Mosaic.OpalV0
                                    .authorizationMaterialByteCount
                            )
                        )
                    )
                )
            }
            let bchSignatureAuthorizationRequests = try decoder.readVector { decoder in
                try OpalFusion.Mosaic.OpalV0.AuthorizationRequestPayload(
                    slot: Int(decoder.readUInt8()),
                    blindedMessage: OpalCrypto.RSABSSA.BlindedMessage(
                        rawRepresentation: Data(
                            try decoder.readFixedBytes(
                                byteCount: OpalFusion.Mosaic.OpalV0
                                    .authorizationMaterialByteCount
                            )
                        )
                    )
                )
            }
            return try .init(
                roundIdentifier: roundIdentifier,
                contributor: contributor,
                groupedCommitment: groupedCommitment,
                componentAuthorizationRequests: componentAuthorizationRequests,
                bchSignatureAuthorizationRequests:
                    bchSignatureAuthorizationRequests
            )
        }
    }

    static func encodePlayerCommit(
        roundIdentifier: [UInt8],
        contributor: OpalFusion.Mosaic.Attempt.ControlIdentity,
        groupedCommitment: OpalFusion.Mosaic.OpalV0.GroupedCommitmentPayload,
        componentAuthorizationRequests: [
            OpalFusion.Mosaic.OpalV0.AuthorizationRequestPayload
        ],
        bchSignatureAuthorizationRequests: [
            OpalFusion.Mosaic.OpalV0.AuthorizationRequestPayload
        ]
    ) throws -> [UInt8] {
        var encoder = OpalFusion.Mosaic.CanonicalEncoder()
        try encoder.writeFixedBytes(roundIdentifier, byteCount: 32)
        try encoder.writeFixedBytes(contributor.validatedBytes, byteCount: 32)
        try encoder.writeVector(groupedCommitment.commitments) {
            encoder, commitment in
            try OpalFusion.Mosaic.OpalV0.CanonicalWireCodec
                .writeComponentCommitment(commitment, to: &encoder)
        }
        encoder.writeUInt64(groupedCommitment.excessFeeSatoshis)
        try encoder.writeFixedBytes(
            groupedCommitment.pedersenTotalNonce,
            byteCount: 32
        )
        try encoder.writeVector(componentAuthorizationRequests) { encoder, request in
            encoder.writeUInt8(UInt8(request.slot))
            try encoder.writeFixedBytes(
                [UInt8](request.blindedMessage.rawRepresentation),
                byteCount: OpalFusion.Mosaic.OpalV0.authorizationMaterialByteCount
            )
        }
        try encoder.writeVector(bchSignatureAuthorizationRequests) {
            encoder, request in
            encoder.writeUInt8(UInt8(request.slot))
            try encoder.writeFixedBytes(
                [UInt8](request.blindedMessage.rawRepresentation),
                byteCount: OpalFusion.Mosaic.OpalV0
                    .authorizationMaterialByteCount
            )
        }
        return encoder.encodedBytes
    }
}

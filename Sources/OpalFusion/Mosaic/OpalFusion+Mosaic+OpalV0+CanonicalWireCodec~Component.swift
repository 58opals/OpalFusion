// OpalFusion+Mosaic+OpalV0+CanonicalWireCodec~Component.swift

extension OpalFusion.Mosaic.OpalV0.CanonicalWireCodec {
    private enum ComponentKind: UInt8 {
        case input = 0
        case output = 1
        case blank = 2
    }

    static func encodeComponent(
        _ component: OpalFusion.Mosaic.OpalV0.Component
    ) throws -> [UInt8] {
        var encoder = OpalFusion.Mosaic.CanonicalEncoder()
        try writeComponent(component, to: &encoder)
        return encoder.encodedBytes
    }

    static func encodeComponentPayload(
        _ payload: OpalFusion.Mosaic.OpalV0.ComponentPayload
    ) throws -> [UInt8] {
        var encoder = OpalFusion.Mosaic.CanonicalEncoder()
        try writeComponentPayload(payload, to: &encoder)
        return encoder.encodedBytes
    }

    static func decodeComponent(
        from encodedBytes: [UInt8]
    ) throws -> OpalFusion.Mosaic.OpalV0.Component {
        try OpalFusion.Mosaic.CanonicalDecoder.decode(
            from: encodedBytes,
            readingValueWith: readComponent
        )
    }

    static func writeComponent(
        _ component: OpalFusion.Mosaic.OpalV0.Component,
        to encoder: inout OpalFusion.Mosaic.CanonicalEncoder
    ) throws {
        try encoder.writeFixedBytes(
            component.saltCommitment,
            byteCount: OpalFusion.Mosaic.OpalV0.digestByteCount
        )
        try writeComponentPayload(component.payload, to: &encoder)
    }

    static func writeComponentPayload(
        _ payload: OpalFusion.Mosaic.OpalV0.ComponentPayload,
        to encoder: inout OpalFusion.Mosaic.CanonicalEncoder
    ) throws {
        switch payload {
        case let .input(input):
            encoder.writeUInt8(ComponentKind.input.rawValue)
            try encoder.writeFixedBytes(
                input.previousTransactionHash,
                byteCount: OpalFusion.Mosaic.OpalV0.digestByteCount
            )
            encoder.writeUInt32(input.outputIndex)
            encoder.writeUInt64(input.amountSatoshis)
        case let .output(output):
            encoder.writeUInt8(ComponentKind.output.rawValue)
            try encoder.writeFixedBytes(
                output.lockingScript,
                byteCount: OpalFusion.Mosaic.OpalV0.p2pkhLockingScriptByteCount
            )
            encoder.writeUInt64(output.amountSatoshis)
        case .blank:
            encoder.writeUInt8(ComponentKind.blank.rawValue)
        }
    }

    static func readComponent(
        from decoder: inout OpalFusion.Mosaic.CanonicalDecoder
    ) throws -> OpalFusion.Mosaic.OpalV0.Component {
        let saltCommitment = try decoder.readFixedBytes(
            byteCount: OpalFusion.Mosaic.OpalV0.digestByteCount
        )
        let rawKind = try decoder.readUInt8()
        guard let kind = ComponentKind(rawValue: rawKind) else {
            throw OpalFusion.Mosaic.OpalV0.WireContractError
                .unknownComponentKind(rawKind)
        }

        let payload: OpalFusion.Mosaic.OpalV0.ComponentPayload
        switch kind {
        case .input:
            payload = try .input(
                .init(
                    previousTransactionHash: decoder.readFixedBytes(
                        byteCount: OpalFusion.Mosaic.OpalV0.digestByteCount
                    ),
                    outputIndex: decoder.readUInt32(),
                    amountSatoshis: decoder.readUInt64()
                )
            )
        case .output:
            payload = try .output(
                .init(
                    lockingScript: decoder.readFixedBytes(
                        byteCount: OpalFusion.Mosaic.OpalV0.p2pkhLockingScriptByteCount
                    ),
                    amountSatoshis: decoder.readUInt64()
                )
            )
        case .blank:
            payload = .blank
        }
        return try .init(
            saltCommitment: saltCommitment,
            payload: payload
        )
    }
}

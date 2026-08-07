// OpalFusion+Mosaic+OpalV0+CanonicalWireCodec~AggregateFragment.swift

extension OpalFusion.Mosaic.OpalV0.CanonicalWireCodec {
    static func encodeAggregateFragment(
        _ fragment: OpalFusion.Mosaic.OpalV0.AggregateFragment
    ) throws -> [UInt8] {
        var encoder = OpalFusion.Mosaic.CanonicalEncoder()
        try encoder.writeFixedBytes(
            fragment.descriptor.roundIdentifier,
            byteCount: OpalFusion.Mosaic.OpalV0.digestByteCount
        )
        encoder.writeUInt8(fragment.descriptor.aggregateKind.rawValue)
        try encoder.writeFixedBytes(
            fragment.descriptor.aggregateDigest,
            byteCount: OpalFusion.Mosaic.OpalV0.digestByteCount
        )
        encoder.writeUInt32(
            UInt32(fragment.descriptor.declaredAggregateByteCount)
        )
        encoder.writeUInt8(UInt8(fragment.fragmentIndex))
        encoder.writeUInt8(UInt8(fragment.descriptor.fragmentCount))
        try encoder.writeBytes(fragment.body)

        let encodedBytes = encoder.encodedBytes
        guard encodedBytes.count
            <= OpalFusion.Mosaic.OpalV0.maximumInnerPayloadByteCount else {
            throw OpalFusion.Mosaic.OpalV0.AggregateFragment.Failure
                .encodedFragmentTooLarge(
                    maximum: OpalFusion.Mosaic.OpalV0.maximumInnerPayloadByteCount,
                    actual: encodedBytes.count
                )
        }
        return encodedBytes
    }

    static func decodeAggregateFragment(
        from encodedBytes: [UInt8]
    ) throws -> OpalFusion.Mosaic.OpalV0.AggregateFragment {
        guard encodedBytes.count
            <= OpalFusion.Mosaic.OpalV0.maximumInnerPayloadByteCount else {
            throw OpalFusion.Mosaic.OpalV0.AggregateFragment.Failure
                .encodedFragmentTooLarge(
                    maximum: OpalFusion.Mosaic.OpalV0.maximumInnerPayloadByteCount,
                    actual: encodedBytes.count
                )
        }

        return try OpalFusion.Mosaic.CanonicalDecoder.decode(
            from: encodedBytes
        ) { decoder in
            let roundIdentifier = try decoder.readFixedBytes(
                byteCount: OpalFusion.Mosaic.OpalV0.digestByteCount
            )
            let rawAggregateKind = try decoder.readUInt8()
            guard let aggregateKind = OpalFusion.Mosaic.OpalV0
                .AggregateFragment.Kind(rawValue: rawAggregateKind) else {
                throw OpalFusion.Mosaic.OpalV0.AggregateFragment.Failure
                    .unknownAggregateKind(rawAggregateKind)
            }
            let aggregateDigest = try decoder.readFixedBytes(
                byteCount: OpalFusion.Mosaic.OpalV0.digestByteCount
            )
            let declaredAggregateByteCount = Int(try decoder.readUInt32())
            let fragmentIndex = Int(try decoder.readUInt8())
            let declaredFragmentCount = Int(try decoder.readUInt8())
            let body = try decoder.readBytes()
            let descriptor = try OpalFusion.Mosaic.OpalV0.AggregateFragment
                .Descriptor(
                    roundIdentifier: roundIdentifier,
                    aggregateKind: aggregateKind,
                    aggregateDigest: aggregateDigest,
                    declaredAggregateByteCount: declaredAggregateByteCount
                )
            guard declaredFragmentCount == descriptor.fragmentCount else {
                throw OpalFusion.Mosaic.OpalV0.AggregateFragment.Failure
                    .invalidFragmentCount(
                        expected: descriptor.fragmentCount,
                        actual: declaredFragmentCount
                    )
            }
            return try .init(
                descriptor: descriptor,
                fragmentIndex: fragmentIndex,
                body: body
            )
        }
    }
}

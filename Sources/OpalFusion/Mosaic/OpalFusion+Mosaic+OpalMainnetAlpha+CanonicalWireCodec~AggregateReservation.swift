// OpalFusion+Mosaic+OpalMainnetAlpha+CanonicalWireCodec~AggregateReservation.swift

extension OpalFusion.Mosaic.OpalMainnetAlpha.CanonicalWireCodec {
    static func encodeAggregateReservation(
        _ reservation: OpalFusion.Mosaic.OpalMainnetAlpha.AggregateReservation
    ) throws -> [UInt8] {
        var encoder = OpalFusion.Mosaic.CanonicalEncoder()
        encoder.writeUInt8(reservation.aggregateKind.rawValue)
        try encoder.writeFixedBytes(
            reservation.aggregateDigest,
            byteCount: 32
        )
        encoder.writeUInt32(UInt32(reservation.declaredCanonicalByteCount))
        encoder.writeUInt8(UInt8(reservation.fragmentCount))
        return encoder.encodedBytes
    }

    static func decodeAggregateReservation(
        from encodedBytes: [UInt8]
    ) throws -> OpalFusion.Mosaic.OpalMainnetAlpha.AggregateReservation {
        try OpalFusion.Mosaic.CanonicalDecoder.decode(from: encodedBytes) { decoder in
            let rawKind = try decoder.readUInt8()
            guard let kind = OpalFusion.Mosaic.OpalMainnetAlpha.AggregateKind(
                rawValue: rawKind
            ) else {
                throw OpalFusion.Mosaic.OpalMainnetAlpha.ContractError
                    .invalidPayloadPhase
            }
            let digest = try decoder.readFixedBytes(byteCount: 32)
            let byteCount = Int(try decoder.readUInt32())
            let declaredFragmentCount = Int(try decoder.readUInt8())
            let reservation = try OpalFusion.Mosaic.OpalMainnetAlpha
                .AggregateReservation(
                    aggregateKind: kind,
                    aggregateDigest: digest,
                    declaredCanonicalByteCount: byteCount
                )
            guard reservation.fragmentCount == declaredFragmentCount else {
                throw OpalFusion.Mosaic.OpalMainnetAlpha.ContractError
                    .invalidAggregateFragmentCount(
                        expected: reservation.fragmentCount,
                        actual: declaredFragmentCount
                    )
            }
            return reservation
        }
    }

    static func encodeAggregateFragment(
        _ fragment: OpalFusion.Mosaic.OpalMainnetAlpha.AggregateFragment
    ) throws -> [UInt8] {
        var encoder = OpalFusion.Mosaic.CanonicalEncoder()
        encoder.writeUInt64(fragment.reservationSequence)
        encoder.writeUInt8(UInt8(fragment.fragmentIndex))
        try encoder.writeBytes(fragment.body)
        return encoder.encodedBytes
    }

    static func decodeAggregateFragment(
        from encodedBytes: [UInt8],
        reservation: OpalFusion.Mosaic.OpalMainnetAlpha.AggregateReservation
    ) throws -> OpalFusion.Mosaic.OpalMainnetAlpha.AggregateFragment {
        try OpalFusion.Mosaic.CanonicalDecoder.decode(from: encodedBytes) { decoder in
            try .init(
                reservationSequence: decoder.readUInt64(),
                fragmentIndex: Int(decoder.readUInt8()),
                body: decoder.readBytes(),
                reservation: reservation
            )
        }
    }
}

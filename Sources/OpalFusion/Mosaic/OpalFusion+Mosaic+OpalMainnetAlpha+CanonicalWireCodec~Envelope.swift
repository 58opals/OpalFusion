// OpalFusion+Mosaic+OpalMainnetAlpha+CanonicalWireCodec~Envelope.swift

extension OpalFusion.Mosaic.OpalMainnetAlpha.CanonicalWireCodec {
    static func encodeControlEnvelopeBody(
        roundIdentifier: [UInt8],
        phase: OpalFusion.Mosaic.Attempt.Phase,
        senderControlIdentity: OpalFusion.Mosaic.Attempt.ControlIdentity,
        senderEventIdentity: [UInt8],
        sequence: UInt64,
        payloadType: OpalFusion.Mosaic.OpalMainnetAlpha.ControlPayloadType,
        payloadDigest: [UInt8],
        expiryUnixSeconds: UInt64
    ) throws -> [UInt8] {
        var encoder = OpalFusion.Mosaic.CanonicalEncoder()
        try encoder.writeText(
            OpalFusion.Mosaic.Profile.opalMainnetAlpha.rawValue
        )
        try encoder.writeFixedBytes(
            OpalFusion.Mosaic.OpalMainnetAlpha.mainnetGenesisHash,
            byteCount: 32
        )
        try encoder.writeFixedBytes(roundIdentifier, byteCount: 32)
        encoder.writeUInt8(UInt8(phase.rawValue))
        try encoder.writeFixedBytes(
            senderControlIdentity.validatedBytes,
            byteCount: 32
        )
        try encoder.writeFixedBytes(senderEventIdentity, byteCount: 32)
        encoder.writeUInt64(sequence)
        encoder.writeUInt16(payloadType.rawValue)
        try encoder.writeFixedBytes(payloadDigest, byteCount: 32)
        encoder.writeUInt64(expiryUnixSeconds)
        return encoder.encodedBytes
    }

    static func encodeControlEnvelope(
        _ envelope: OpalFusion.Mosaic.OpalMainnetAlpha.ControlEnvelope
    ) throws -> [UInt8] {
        var encoder = OpalFusion.Mosaic.CanonicalEncoder()
        try writeControlEnvelopeBody(envelope, to: &encoder)
        try encoder.writeFixedBytes(envelope.controlSignature, byteCount: 64)
        try encoder.writeBytes(envelope.payload)
        return encoder.encodedBytes
    }

    static func decodeControlEnvelope(
        from encodedBytes: [UInt8]
    ) throws -> OpalFusion.Mosaic.OpalMainnetAlpha.ControlEnvelope {
        try OpalFusion.Mosaic.CanonicalDecoder.decode(from: encodedBytes) { decoder in
            try requireProfileAndNetwork(from: &decoder)
            let roundIdentifier = try decoder.readFixedBytes(byteCount: 32)
            let rawPhase = try decoder.readUInt8()
            guard let phase = OpalFusion.Mosaic.Attempt.Phase(
                rawValue: Int(rawPhase)
            ) else {
                throw OpalFusion.Mosaic.OpalMainnetAlpha.ContractError
                    .invalidPhase(rawPhase)
            }
            let sender = OpalFusion.Mosaic.Attempt.ControlIdentity(
                validatedBytes: try decoder.readFixedBytes(byteCount: 32)
            )
            let eventIdentity = try decoder.readFixedBytes(byteCount: 32)
            let sequence = try decoder.readUInt64()
            let rawPayloadType = try decoder.readUInt16()
            guard let payloadType = OpalFusion.Mosaic.OpalMainnetAlpha
                .ControlPayloadType(rawValue: rawPayloadType) else {
                throw OpalFusion.Mosaic.OpalMainnetAlpha.ContractError
                    .invalidPayloadPhase
            }
            let declaredPayloadDigest = try decoder.readFixedBytes(byteCount: 32)
            let expiry = try decoder.readUInt64()
            let signature = try decoder.readFixedBytes(byteCount: 64)
            let payload = try decoder.readBytes()
            let envelope = try OpalFusion.Mosaic.OpalMainnetAlpha.ControlEnvelope(
                roundIdentifier: roundIdentifier,
                phase: phase,
                senderControlIdentity: sender,
                senderEventIdentity: eventIdentity,
                sequence: sequence,
                payloadType: payloadType,
                expiryUnixSeconds: expiry,
                controlSignature: signature,
                payload: payload
            )
            guard envelope.payloadDigest == declaredPayloadDigest else {
                throw OpalFusion.Mosaic.OpalMainnetAlpha.ContractError
                    .payloadDigestMismatch
            }
            return envelope
        }
    }

    static func encodeAnonymousEnvelope(
        _ envelope: OpalFusion.Mosaic.OpalMainnetAlpha.AnonymousEnvelope
    ) throws -> [UInt8] {
        var encoder = OpalFusion.Mosaic.CanonicalEncoder()
        try encoder.writeText(
            OpalFusion.Mosaic.Profile.opalMainnetAlpha.rawValue
        )
        try encoder.writeFixedBytes(
            OpalFusion.Mosaic.OpalMainnetAlpha.mainnetGenesisHash,
            byteCount: 32
        )
        try encoder.writeFixedBytes(envelope.roundIdentifier, byteCount: 32)
        encoder.writeUInt8(UInt8(envelope.phase.rawValue))
        try encoder.writeFixedBytes(
            envelope.senderCommunicationPublicKey,
            byteCount: 33
        )
        try encoder.writeFixedBytes(
            envelope.recipientEventIdentity,
            byteCount: 32
        )
        encoder.writeUInt64(envelope.sequence)
        encoder.writeUInt16(envelope.payloadType.rawValue)
        try encoder.writeFixedBytes(envelope.payloadDigest, byteCount: 32)
        encoder.writeUInt64(envelope.expiryUnixSeconds)
        try encoder.writeBytes(envelope.payload)
        return encoder.encodedBytes
    }

    static func decodeAnonymousEnvelope(
        from encodedBytes: [UInt8]
    ) throws -> OpalFusion.Mosaic.OpalMainnetAlpha.AnonymousEnvelope {
        try OpalFusion.Mosaic.CanonicalDecoder.decode(from: encodedBytes) { decoder in
            try requireProfileAndNetwork(from: &decoder)
            let roundIdentifier = try decoder.readFixedBytes(byteCount: 32)
            let rawPhase = try decoder.readUInt8()
            guard let phase = OpalFusion.Mosaic.Attempt.Phase(
                rawValue: Int(rawPhase)
            ) else {
                throw OpalFusion.Mosaic.OpalMainnetAlpha.ContractError
                    .invalidPhase(rawPhase)
            }
            let senderKey = try decoder.readFixedBytes(byteCount: 33)
            let recipient = try decoder.readFixedBytes(byteCount: 32)
            let sequence = try decoder.readUInt64()
            let rawPayloadType = try decoder.readUInt16()
            guard let payloadType = OpalFusion.Mosaic.OpalMainnetAlpha
                .AnonymousPayloadType(rawValue: rawPayloadType) else {
                throw OpalFusion.Mosaic.OpalMainnetAlpha.ContractError
                    .invalidPayloadPhase
            }
            let declaredPayloadDigest = try decoder.readFixedBytes(byteCount: 32)
            let expiry = try decoder.readUInt64()
            let payload = try decoder.readBytes()
            let envelope = try OpalFusion.Mosaic.OpalMainnetAlpha
                .AnonymousEnvelope(
                    roundIdentifier: roundIdentifier,
                    phase: phase,
                    senderCommunicationPublicKey: senderKey,
                    recipientEventIdentity: recipient,
                    sequence: sequence,
                    payloadType: payloadType,
                    expiryUnixSeconds: expiry,
                    payload: payload
                )
            guard envelope.payloadDigest == declaredPayloadDigest else {
                throw OpalFusion.Mosaic.OpalMainnetAlpha.ContractError
                    .payloadDigestMismatch
            }
            return envelope
        }
    }

    private static func writeControlEnvelopeBody(
        _ envelope: OpalFusion.Mosaic.OpalMainnetAlpha.ControlEnvelope,
        to encoder: inout OpalFusion.Mosaic.CanonicalEncoder
    ) throws {
        try encoder.writeText(
            OpalFusion.Mosaic.Profile.opalMainnetAlpha.rawValue
        )
        try encoder.writeFixedBytes(
            OpalFusion.Mosaic.OpalMainnetAlpha.mainnetGenesisHash,
            byteCount: 32
        )
        try encoder.writeFixedBytes(envelope.roundIdentifier, byteCount: 32)
        encoder.writeUInt8(UInt8(envelope.phase.rawValue))
        try encoder.writeFixedBytes(
            envelope.senderControlIdentity.validatedBytes,
            byteCount: 32
        )
        try encoder.writeFixedBytes(envelope.senderEventIdentity, byteCount: 32)
        encoder.writeUInt64(envelope.sequence)
        encoder.writeUInt16(envelope.payloadType.rawValue)
        try encoder.writeFixedBytes(envelope.payloadDigest, byteCount: 32)
        encoder.writeUInt64(envelope.expiryUnixSeconds)
    }

    private static func requireProfileAndNetwork(
        from decoder: inout OpalFusion.Mosaic.CanonicalDecoder
    ) throws {
        guard try decoder.readText()
            == OpalFusion.Mosaic.Profile.opalMainnetAlpha.rawValue else {
            throw OpalFusion.Mosaic.OpalMainnetAlpha.ContractError.profileMismatch
        }
        guard try decoder.readFixedBytes(byteCount: 32)
            == OpalFusion.Mosaic.OpalMainnetAlpha.mainnetGenesisHash else {
            throw OpalFusion.Mosaic.OpalMainnetAlpha.ContractError.networkMismatch
        }
    }
}

// OpalFusion+Mosaic+OpalMainnetAlpha+PostManifestRelayPublicationJournal+CanonicalCoding.swift

import Foundation

extension OpalFusion.Mosaic.OpalMainnetAlpha
    .PostManifestRelayPublicationJournal {
    private static var recoveryMagic: [UInt8] { [0x4F, 0x46, 0x50, 0x4A] }
    private static var recoveryVersion: UInt16 { 1 }
    private static var maximumRecoveryEndpointCount: Int {
        OpalFusion.Mosaic.OpalMainnetAlpha.relayCount
    }
    private static var maximumRecoveryEndpointByteCount: Int { 2_048 }
    private static var maximumRecoveryPublicationCount: Int {
        8 * OpalFusion.Mosaic.OpalMainnetAlpha
            .componentCountPerContributor
    }
    private static var maximumRecoveryRecordCount: Int {
        3 * (1 + 8 * maximumRecoveryPublicationCount)
    }
    static var maximumRecoverySnapshotByteCount: Int { 16_000_000 }

    static func initializeRecoverySnapshot(
        binding: OpalFusion.MosaicPrivateAlphaRuntime.Binding,
        persistence: OpalFusion.MosaicPrivateAlphaRuntime
            .PostManifestPublicationPersistence,
        context: Context,
        requireExisting: Bool,
        requireEmpty: Bool = false
    ) throws {
        guard matches(binding, context: context) else {
            throw RecoveryCodingError.contextMismatch
        }
        if let existing = try persistence.load(binding) {
            let snapshot = try decodeRecoverySnapshot(
                existing,
                expectedContext: context
            )
            guard !requireEmpty || snapshot.records.isEmpty else {
                throw RecoveryCodingError.staleSnapshot
            }
            return
        }
        guard !requireExisting else {
            throw RecoveryCodingError.missingSnapshot
        }
        let replacement = try encodeRecoverySnapshot(.init(
            context: context,
            records: []
        ))
        let readback = try persistence.compareAndSwap(
            binding,
            nil,
            replacement
        )
        guard readback == replacement else {
            throw RecoveryCodingError.readbackMismatch
        }
        _ = try decodeRecoverySnapshot(
            readback,
            expectedContext: context
        )
    }

    static func recoveryPersistence(
        binding: OpalFusion.MosaicPrivateAlphaRuntime.Binding,
        persistence: OpalFusion.MosaicPrivateAlphaRuntime
            .PostManifestPublicationPersistence
    ) -> Persistence {
        .init(
            loadSnapshot: { context in
                guard Self.matches(binding, context: context) else {
                    return nil
                }
                guard let bytes = try persistence.load(binding) else {
                    throw RecoveryCodingError.missingSnapshot
                }
                return try decodeRecoverySnapshot(
                    bytes,
                    expectedContext: context
                )
            },
            appendRecord: { context, expectedCount, record in
                guard Self.matches(binding, context: context) else {
                    throw RecoveryCodingError.contextMismatch
                }
                let priorBytes = try persistence.load(binding)
                guard let priorBytes else {
                    throw RecoveryCodingError.missingSnapshot
                }
                let prior = try decodeRecoverySnapshot(
                    priorBytes,
                    expectedContext: context
                )
                guard prior.records.count == expectedCount else {
                    throw RecoveryCodingError.staleSnapshot
                }
                guard prior.records.count < maximumRecoveryRecordCount else {
                    throw RecoveryCodingError.resourceLimitExceeded
                }
                let replacement = Snapshot(
                    context: context,
                    records: prior.records + [record]
                )
                let replacementBytes = try encodeRecoverySnapshot(replacement)
                let readback = try persistence.compareAndSwap(
                    binding,
                    priorBytes,
                    replacementBytes
                )
                guard readback == replacementBytes else {
                    throw RecoveryCodingError.readbackMismatch
                }
                _ = try decodeRecoverySnapshot(
                    readback,
                    expectedContext: context
                )
            }
        )
    }

    static func validateDrainedRecoveryReadback(
        _ bytes: Data,
        expectedContext: Context
    ) throws -> Bool {
        let snapshot = try decodeRecoverySnapshot(
            bytes,
            expectedContext: expectedContext
        )
        let restored = try Self(
            context: expectedContext,
            persistence: .init(
                loadSnapshot: { _ in snapshot },
                appendRecord: { _, _, _ in
                    throw RecoveryCodingError.staleSnapshot
                }
            )
        )
        return restored.isDrained
    }

    private static func matches(
        _ binding: OpalFusion.MosaicPrivateAlphaRuntime.Binding,
        context: Context
    ) -> Bool {
        Data(context.attemptIdentifier.validatedBytes)
                == binding.attemptIdentifier
            && Data(context.generationIdentifier.opaqueBytes)
                == binding.generationIdentifier
            && Data(context.materialIdentifier.opaqueBytes)
                == binding.materialIdentifier
    }

    private static func encodeRecoverySnapshot(
        _ snapshot: Snapshot
    ) throws -> Data {
        var encoder = OpalFusion.Mosaic.CanonicalEncoder()
        try encoder.writeFixedBytes(recoveryMagic, byteCount: recoveryMagic.count)
        encoder.writeUInt16(recoveryVersion)
        try encode(snapshot.context, to: &encoder)
        try encoder.writeVector(snapshot.records) { encoder, record in
            try encode(record, to: &encoder)
        }
        return Data(encoder.encodedBytes)
    }

    private static func decodeRecoverySnapshot(
        _ bytes: Data,
        expectedContext: Context
    ) throws -> Snapshot {
        guard bytes.count <= maximumRecoverySnapshotByteCount else {
            throw RecoveryCodingError.resourceLimitExceeded
        }
        let snapshot = try OpalFusion.Mosaic.CanonicalDecoder.decode(
            from: Array(bytes)
        ) { decoder in
            guard try decoder.readFixedBytes(byteCount: recoveryMagic.count)
                    == recoveryMagic,
                  try decoder.readUInt16() == recoveryVersion else {
                throw RecoveryCodingError.unsupportedVersion
            }
            try decodeAndValidateContext(
                from: &decoder,
                expected: expectedContext
            )
            return Snapshot(
                context: expectedContext,
                records: try decoder.readVector(
                    maximumCount: maximumRecoveryRecordCount
                ) { decoder in
                    try decodeRecord(from: &decoder)
                }
            )
        }
        guard try encodeRecoverySnapshot(snapshot) == bytes else {
            throw RecoveryCodingError.nonCanonical
        }
        return snapshot
    }

    private static func encode(
        _ context: Context,
        to encoder: inout OpalFusion.Mosaic.CanonicalEncoder
    ) throws {
        try encoder.writeFixedBytes(
            context.attemptIdentifier.validatedBytes,
            byteCount: 32
        )
        try encoder.writeFixedBytes(
            context.generationIdentifier.opaqueBytes,
            byteCount: 32
        )
        try encoder.writeFixedBytes(
            context.materialIdentifier.opaqueBytes,
            byteCount: 32
        )
        try encoder.writeFixedBytes(
            context.localControlIdentity.validatedBytes,
            byteCount: 32
        )
        try encoder.writeFixedBytes(Array(context.roundIdentifier), byteCount: 32)
        try encoder.writeFixedBytes(
            Array(context.manifestRelaySetDigest),
            byteCount: 32
        )
        try encoder.writeVector(context.endpoints) { encoder, endpoint in
            try encoder.writeText(endpoint.validatedIdentifier)
        }
    }

    private static func decodeAndValidateContext(
        from decoder: inout OpalFusion.Mosaic.CanonicalDecoder,
        expected: Context
    ) throws {
        let attempt = try decoder.readFixedBytes(byteCount: 32)
        let generation = try decoder.readFixedBytes(byteCount: 32)
        let material = try decoder.readFixedBytes(byteCount: 32)
        let local = try decoder.readFixedBytes(byteCount: 32)
        let round = try decoder.readFixedBytes(byteCount: 32)
        let relayDigest = try decoder.readFixedBytes(byteCount: 32)
        let endpoints: [Endpoint] = try decoder.readVector(
            maximumCount: maximumRecoveryEndpointCount
        ) { decoder in
            .init(validatedIdentifier: try decoder.readText(
                maximumByteCount: maximumRecoveryEndpointByteCount
            ))
        }
        guard attempt == expected.attemptIdentifier.validatedBytes,
              generation == expected.generationIdentifier.opaqueBytes,
              material == expected.materialIdentifier.opaqueBytes,
              local == expected.localControlIdentity.validatedBytes,
              round == Array(expected.roundIdentifier),
              relayDigest == Array(expected.manifestRelaySetDigest),
              endpoints == expected.endpoints else {
            throw RecoveryCodingError.contextMismatch
        }
    }

    private static func encode(
        _ record: Record,
        to encoder: inout OpalFusion.Mosaic.CanonicalEncoder
    ) throws {
        switch record {
        case let .prepared(batch):
            encoder.writeUInt8(0)
            try encode(batch, to: &encoder)
        case let .publicationPermitted(identifier):
            encoder.writeUInt8(1)
            try encoder.writeFixedBytes(Array(identifier), byteCount: 32)
        case let .attempted(identifier, endpoint):
            encoder.writeUInt8(2)
            try encoder.writeFixedBytes(Array(identifier), byteCount: 32)
            try encoder.writeText(endpoint.validatedIdentifier)
        case let .acknowledged(identifier, endpoint, acknowledgement):
            encoder.writeUInt8(3)
            try encoder.writeFixedBytes(Array(identifier), byteCount: 32)
            try encoder.writeText(endpoint.validatedIdentifier)
            encoder.writeUInt8(acknowledgement == .accepted ? 0 : 1)
        case let .completed(identifier, completion):
            encoder.writeUInt8(4)
            try encoder.writeFixedBytes(Array(identifier), byteCount: 32)
            switch completion {
            case .transportAccepted: encoder.writeUInt8(0)
            case .transportRejected: encoder.writeUInt8(1)
            case .cancelled: encoder.writeUInt8(2)
            }
        }
    }

    private static func encode(
        _ batch: PublicationBatch,
        to encoder: inout OpalFusion.Mosaic.CanonicalEncoder
    ) throws {
        encoder.writeUInt8(tag(for: batch.channelPurpose))
        try encoder.writeVector(batch.publications) { encoder, publication in
            encoder.writeUInt8(tag(for: publication.binding.channelPurpose))
            try encoder.writeFixedBytes(
                Array(publication.binding.recipientEventIdentity),
                byteCount: 32
            )
            encoder.writeUInt64(publication.binding.expiryUnixSeconds)
            try encoder.writeFixedBytes(
                Array(publication.eventIdentifier),
                byteCount: 32
            )
            try encoder.writeBytes(Array(publication.canonicalEventBytes))
            try encoder.writeVector(publication.endpoints) { encoder, endpoint in
                try encoder.writeText(endpoint.validatedIdentifier)
            }
        }
    }

    private static func decodeRecord(
        from decoder: inout OpalFusion.Mosaic.CanonicalDecoder
    ) throws -> Record {
        switch try decoder.readUInt8() {
        case 0:
            return .prepared(try decodeBatch(from: &decoder))
        case 1:
            return .publicationPermitted(
                eventIdentifier: Data(
                    try decoder.readFixedBytes(byteCount: 32)
                )
            )
        case 2:
            return .attempted(
                eventIdentifier: Data(
                    try decoder.readFixedBytes(byteCount: 32)
                ),
                endpoint: .init(validatedIdentifier: try decoder.readText(
                    maximumByteCount: maximumRecoveryEndpointByteCount
                ))
            )
        case 3:
            let identifier = Data(
                try decoder.readFixedBytes(byteCount: 32)
            )
            let endpoint = Endpoint(
                validatedIdentifier: try decoder.readText(
                    maximumByteCount: maximumRecoveryEndpointByteCount
                )
            )
            let acknowledgement: RelayAcknowledgement
            switch try decoder.readUInt8() {
            case 0: acknowledgement = .accepted
            case 1: acknowledgement = .rejected
            default: throw RecoveryCodingError.malformed
            }
            return .acknowledged(
                eventIdentifier: identifier,
                endpoint: endpoint,
                acknowledgement
            )
        case 4:
            let identifier = Data(
                try decoder.readFixedBytes(byteCount: 32)
            )
            let completion: Completion
            switch try decoder.readUInt8() {
            case 0: completion = .transportAccepted
            case 1: completion = .transportRejected
            case 2: completion = .cancelled
            default: throw RecoveryCodingError.malformed
            }
            return .completed(
                eventIdentifier: identifier,
                completion
            )
        default:
            throw RecoveryCodingError.malformed
        }
    }

    private static func decodeBatch(
        from decoder: inout OpalFusion.Mosaic.CanonicalDecoder
    ) throws -> PublicationBatch {
        let batchPurpose = try purpose(for: decoder.readUInt8())
        let publications: [Publication] = try decoder.readVector(
            maximumCount: maximumRecoveryPublicationCount
        ) { decoder in
            let publicationPurpose = try purpose(for: decoder.readUInt8())
            let recipient = Data(
                try decoder.readFixedBytes(byteCount: 32)
            )
            let expiry = try decoder.readUInt64()
            let identifier = Data(
                try decoder.readFixedBytes(byteCount: 32)
            )
            let canonicalEventBytes = Data(try decoder.readBytes(
                maximumByteCount: OpalFusion.Mosaic.OpalMainnetAlpha
                    .nip59MaximumGiftWrapJSONByteCount
            ))
            let endpoints: [Endpoint] = try decoder.readVector(
                maximumCount: maximumRecoveryEndpointCount
            ) { decoder in
                .init(validatedIdentifier: try decoder.readText(
                    maximumByteCount: maximumRecoveryEndpointByteCount
                ))
            }
            return Publication(
                binding: try .init(
                    channelPurpose: publicationPurpose,
                    recipientEventIdentity: recipient,
                    expiryUnixSeconds: expiry
                ),
                eventIdentifier: identifier,
                canonicalEventBytes: canonicalEventBytes,
                endpoints: endpoints
            )
        }
        return .init(
            channelPurpose: batchPurpose,
            publications: publications
        )
    }

    private static func tag(for purpose: ChannelPurpose) -> UInt8 {
        switch purpose {
        case .control: 0
        case .anonymousComponents: 1
        case .anonymousBCHSignatures: 2
        }
    }

    private static func purpose(for tag: UInt8) throws -> ChannelPurpose {
        switch tag {
        case 0: .control
        case 1: .anonymousComponents
        case 2: .anonymousBCHSignatures
        default: throw RecoveryCodingError.malformed
        }
    }

    private enum RecoveryCodingError: Error {
        case contextMismatch
        case malformed
        case missingSnapshot
        case nonCanonical
        case readbackMismatch
        case resourceLimitExceeded
        case staleSnapshot
        case unsupportedVersion
    }
}

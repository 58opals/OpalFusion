// OpalFusion+Mosaic+OpalMainnetAlpha+PostManifestAdmissionJournal+CanonicalCoding.swift

import Foundation

extension OpalFusion.Mosaic.OpalMainnetAlpha.PostManifestAdmissionJournal {
    private static var recoveryMagic: [UInt8] { [0x4F, 0x46, 0x41, 0x4A] }
    private static var recoveryVersion: UInt16 { 1 }
    private static var maximumRecoveryRecipientCount: Int {
        1 + 8 * OpalFusion.Mosaic.OpalMainnetAlpha
            .componentCountPerContributor
    }
    private static var maximumRecoveryRecordCount: Int {
        maximumRecoveryRecipientCount * 8
    }
    private static var maximumRecoverySnapshotByteCount: Int { 32_000_000 }

    static func initializeRecoverySnapshot(
        binding: OpalFusion.MosaicPrivateAlphaRuntime.Binding,
        persistence: OpalFusion.MosaicPrivateAlphaRuntime
            .PostManifestAdmissionPersistence,
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
            try validateDecodedRecoverySnapshot(
                snapshot,
                expectedContext: context
            )
            guard !requireEmpty || snapshot.acceptedRecords.isEmpty else {
                throw RecoveryCodingError.staleSnapshot
            }
            return
        }
        guard !requireExisting else {
            throw RecoveryCodingError.missingSnapshot
        }
        let replacement = try encodeRecoverySnapshot(.init(
            context: context,
            acceptedRecords: []
        ))
        let readback = try persistence.compareAndSwap(
            binding,
            nil,
            replacement
        )
        guard readback == replacement else {
            throw RecoveryCodingError.readbackMismatch
        }
        let initialized = try decodeRecoverySnapshot(
            readback,
            expectedContext: context
        )
        try validateDecodedRecoverySnapshot(
            initialized,
            expectedContext: context
        )
    }

    static func recoveryStore(
        binding: OpalFusion.MosaicPrivateAlphaRuntime.Binding,
        persistence: OpalFusion.MosaicPrivateAlphaRuntime
            .PostManifestAdmissionPersistence
    ) -> Store {
        return .init(
            load: { context in
                guard Self.matches(binding, context: context) else {
                    return nil
                }
                guard let bytes = try persistence.load(binding) else {
                    throw RecoveryCodingError.missingSnapshot
                }
                let snapshot = try Self.decodeRecoverySnapshot(
                    bytes,
                    expectedContext: context
                )
                try Self.validateDecodedRecoverySnapshot(
                    snapshot,
                    expectedContext: context
                )
                return snapshot
            },
            append: { context, expectedCount, record in
                guard Self.matches(binding, context: context) else {
                    throw RecoveryCodingError.contextMismatch
                }
                let priorBytes = try persistence.load(binding)
                guard let priorBytes else {
                    throw RecoveryCodingError.missingSnapshot
                }
                let prior = try Self.decodeRecoverySnapshot(
                    priorBytes,
                    expectedContext: context
                )
                try Self.validateDecodedRecoverySnapshot(
                    prior,
                    expectedContext: context
                )
                guard prior.acceptedRecords.count == expectedCount else {
                    throw RecoveryCodingError.staleSnapshot
                }
                guard prior.acceptedRecords.count
                        < maximumRecoveryRecordCount else {
                    throw RecoveryCodingError.resourceLimitExceeded
                }
                let replacement = Snapshot(
                    context: context,
                    acceptedRecords: prior.acceptedRecords + [record]
                )
                let replacementBytes = try Self.encodeRecoverySnapshot(
                    replacement
                )
                let readback = try persistence.compareAndSwap(
                    binding,
                    priorBytes,
                    replacementBytes
                )
                guard readback == replacementBytes else {
                    throw RecoveryCodingError.readbackMismatch
                }
                let persisted = try Self.decodeRecoverySnapshot(
                    readback,
                    expectedContext: context
                )
                try Self.validateDecodedRecoverySnapshot(
                    persisted,
                    expectedContext: context
                )
            }
        )
    }

    static func validateRecoveryReadback(
        _ bytes: Data,
        expectedContext: Context
    ) throws {
        let snapshot = try decodeRecoverySnapshot(
            bytes,
            expectedContext: expectedContext
        )
        try validateDecodedRecoverySnapshot(
            snapshot,
            expectedContext: expectedContext
        )
    }

    private static func validateDecodedRecoverySnapshot(
        _ snapshot: Snapshot,
        expectedContext: Context
    ) throws {
        _ = try Self(
            context: expectedContext,
            store: .init(
                load: { context in
                    guard context == expectedContext else {
                        return nil
                    }
                    return snapshot
                },
                append: { _, _, _ in }
            )
        )
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
        try encoder.writeVector(snapshot.acceptedRecords) { encoder, record in
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
            let records = try decoder.readVector(
                maximumCount: maximumRecoveryRecordCount
            ) { decoder in
                try decodeRecord(from: &decoder)
            }
            return Snapshot(
                context: expectedContext,
                acceptedRecords: records
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
        try encoder.writeFixedBytes(context.roundIdentifier, byteCount: 32)
        try encoder.writeVector(context.recipientBindings) { encoder, binding in
            encoder.writeUInt8(binding.channel == .control ? 0 : 1)
            try encoder.writeFixedBytes(binding.eventIdentity, byteCount: 32)
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
        let recipients: [RecipientBinding] = try decoder.readVector(
            maximumCount: maximumRecoveryRecipientCount
        ) { decoder in
            let channel: Transport.Channel
            switch try decoder.readUInt8() {
            case 0: channel = .control
            case 1: channel = .anonymous
            default: throw RecoveryCodingError.malformed
            }
            return .init(
                channel: channel,
                eventIdentity: try decoder.readFixedBytes(byteCount: 32)
            )
        }
        guard attempt == expected.attemptIdentifier.validatedBytes,
              generation == expected.generationIdentifier.opaqueBytes,
              material == expected.materialIdentifier.opaqueBytes,
              local == expected.localControlIdentity.validatedBytes,
              round == expected.roundIdentifier,
              recipients == expected.recipientBindings else {
            throw RecoveryCodingError.contextMismatch
        }
    }

    private static func encode(
        _ record: AcceptedRecord,
        to encoder: inout OpalFusion.Mosaic.CanonicalEncoder
    ) throws {
        switch record {
        case let .control(sender, sequence, digest, source):
            encoder.writeUInt8(0)
            try encoder.writeFixedBytes(sender.validatedBytes, byteCount: 32)
            encoder.writeUInt64(sequence)
            try encoder.writeFixedBytes(digest, byteCount: 32)
            try encode(source, to: &encoder)
        case let .anonymous(
            identifier,
            sender,
            recipient,
            sequence,
            payloadType,
            digest,
            source
        ):
            encoder.writeUInt8(1)
            try encoder.writeFixedBytes(identifier.bytes, byteCount: 32)
            try encoder.writeFixedBytes(sender, byteCount: 32)
            try encoder.writeFixedBytes(recipient, byteCount: 32)
            encoder.writeUInt64(sequence)
            encoder.writeUInt16(payloadType)
            try encoder.writeFixedBytes(digest, byteCount: 32)
            try encode(source, to: &encoder)
        }
    }

    private static func encode(
        _ source: RecoveryAdmission,
        to encoder: inout OpalFusion.Mosaic.CanonicalEncoder
    ) throws {
        encoder.writeUInt64(source.acceptedAtUnixSeconds)
        try encoder.writeBytes(Array(source.canonicalGiftWrapBytes))
    }

    private static func decodeRecord(
        from decoder: inout OpalFusion.Mosaic.CanonicalDecoder
    ) throws -> AcceptedRecord {
        switch try decoder.readUInt8() {
        case 0:
            return .control(
                sender: .init(
                    validatedBytes: try decoder.readFixedBytes(byteCount: 32)
                ),
                sequence: try decoder.readUInt64(),
                messageDigest:
                    try decoder.readFixedBytes(byteCount: 32),
                source: try decodeSource(from: &decoder)
            )
        case 1:
            return try .anonymous(
                messageIdentifier: .init(
                    bytes: decoder.readFixedBytes(byteCount: 32)
                ),
                senderEventIdentity:
                    decoder.readFixedBytes(byteCount: 32),
                recipientEventIdentity:
                    decoder.readFixedBytes(byteCount: 32),
                sequence: decoder.readUInt64(),
                payloadType: decoder.readUInt16(),
                payloadDigest: decoder.readFixedBytes(byteCount: 32),
                source: decodeSource(from: &decoder)
            )
        default:
            throw RecoveryCodingError.malformed
        }
    }

    private static func decodeSource(
        from decoder: inout OpalFusion.Mosaic.CanonicalDecoder
    ) throws -> RecoveryAdmission {
        let acceptedAtUnixSeconds = try decoder.readUInt64()
        return .init(
            canonicalGiftWrapBytes: Data(try decoder.readBytes(
                maximumByteCount: OpalFusion.Mosaic.OpalMainnetAlpha
                    .nip59MaximumGiftWrapJSONByteCount
            )),
            acceptedAtUnixSeconds: acceptedAtUnixSeconds
        )
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

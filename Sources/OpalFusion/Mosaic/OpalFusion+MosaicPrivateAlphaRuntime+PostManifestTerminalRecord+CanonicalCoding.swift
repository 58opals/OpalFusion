// OpalFusion+MosaicPrivateAlphaRuntime+PostManifestTerminalRecord+CanonicalCoding.swift

#if os(macOS)
import Foundation

extension OpalFusion.MosaicPrivateAlphaRuntime.PostManifestTerminalRecord {
    private static var domain: String {
        "OpalFusion/MosaicPrivateAlpha/terminal-record"
    }
    private static var version: UInt16 { 2 }
    private static var maximumSnapshotByteCount: Int { 200_512 }

    static func abort(
        binding: OpalFusion.MosaicPrivateAlphaRuntime.Binding,
        phase: OpalFusion.Mosaic.Attempt.Phase,
        event: OpalFusion.MosaicPrivateAlphaRuntime.PrivateDeploymentEvent,
        wasReceived: Bool,
        manifest: OpalFusion.Mosaic.OpalMainnetAlpha
            .PrivateDeploymentManifestValidation,
        roundManifest: OpalFusion.Mosaic.OpalMainnetAlpha.RoundManifest
    ) throws -> (
        record: Self,
        authority: OpalFusion.Mosaic.OpalMainnetAlpha
            .PrivateDeploymentAbortAuthority,
        reason: OpalFusion.Mosaic.Attempt.AbortReason
    ) {
        typealias Alpha = OpalFusion.Mosaic.OpalMainnetAlpha
        let nostrEvent = try event.decodeCanonicalNostrEvent()
        let participant = OpalFusion.Mosaic.Attempt.ControlIdentity(
            validatedBytes: [UInt8](nostrEvent.publicKey.rawRepresentation)
        )
        let authority = try Alpha.PrivateDeploymentAbortAuthority
            .makePostManifestAuthority(
                phase: phase,
                participant: participant,
                manifest: manifest,
                roundManifest: roundManifest
            )
        let document = try Alpha.PreManifestNostrCodec.decodeAbort(
            nostrEvent,
            authority: authority,
            currentUnixSeconds: event.acceptedAtUnixSeconds
        )
        return (
            .abort(
                binding: binding,
                phase: phase,
                event: event,
                wasReceived: wasReceived
            ),
            authority,
            document.reason
        )
    }

    static func completion(
        binding: OpalFusion.MosaicPrivateAlphaRuntime.Binding,
        event: OpalFusion.MosaicPrivateAlphaRuntime.PrivateDeploymentEvent,
        validation: OpalFusion.Mosaic.OpalMainnetAlpha
            .PrivateDeploymentCompletionValidation
    ) throws -> Self {
        _ = try OpalFusion.Mosaic.OpalMainnetAlpha.PreManifestNostrCodec
            .decodeCompletion(
                event.decodeCanonicalNostrEvent(),
                validation: validation,
                currentUnixSeconds: event.acceptedAtUnixSeconds
            )
        return .completion(binding: binding, event: event)
    }

    func validateAbort(
        manifest: OpalFusion.Mosaic.OpalMainnetAlpha
            .PrivateDeploymentManifestValidation,
        roundManifest: OpalFusion.Mosaic.OpalMainnetAlpha.RoundManifest
    ) throws -> (
        authority: OpalFusion.Mosaic.OpalMainnetAlpha
            .PrivateDeploymentAbortAuthority,
        reason: OpalFusion.Mosaic.Attempt.AbortReason
    ) {
        guard case let .abort(
            binding,
            phase,
            event,
            wasReceived
        ) = self else {
            throw OpalFusion.MosaicPrivateAlphaRuntime.Failure
                .invalidStateTransition
        }
        let validated = try Self.abort(
            binding: binding,
            phase: phase,
            event: event,
            wasReceived: wasReceived,
            manifest: manifest,
            roundManifest: roundManifest
        )
        return (validated.authority, validated.reason)
    }

    func validateCompletion(
        _ validation: OpalFusion.Mosaic.OpalMainnetAlpha
            .PrivateDeploymentCompletionValidation
    ) throws {
        guard case let .completion(binding, event) = self else {
            throw OpalFusion.MosaicPrivateAlphaRuntime.Failure
                .invalidStateTransition
        }
        guard try Self.completion(
            binding: binding,
            event: event,
            validation: validation
        ) == self else {
            throw OpalFusion.MosaicPrivateAlphaRuntime.Failure
                .nonCanonicalRecoverySnapshot
        }
    }

    func canonicalBytes() throws -> Data {
        var encoder = OpalFusion.Mosaic.CanonicalEncoder()
        try encoder.writeText(Self.domain)
        encoder.writeUInt16(Self.version)
        try encoder.writeFixedBytes(
            Array(binding.attemptIdentifier), byteCount: 32
        )
        try encoder.writeFixedBytes(
            Array(binding.generationIdentifier), byteCount: 32
        )
        try encoder.writeFixedBytes(
            Array(binding.materialIdentifier), byteCount: 32
        )
        switch self {
        case let .abort(_, phase, event, wasReceived):
            encoder.writeUInt8(0)
            encoder.writeUInt8(wasReceived ? 1 : 0)
            encoder.writeUInt8(try OpalFusion.MosaicPrivateAlphaRuntime
                .postManifestRecoveryTag(for: phase))
            try encoder.writeBytes(Array(try event.canonicalRecoveryBytes()))
        case let .completion(_, event):
            encoder.writeUInt8(1)
            try encoder.writeBytes(Array(try event.canonicalRecoveryBytes()))
        }
        return Data(encoder.encodedBytes)
    }

    static func decode(
        _ bytes: Data,
        expectedBinding: OpalFusion.MosaicPrivateAlphaRuntime.Binding
    ) throws -> Self {
        typealias Runtime = OpalFusion.MosaicPrivateAlphaRuntime
        guard bytes.count <= maximumSnapshotByteCount else {
            throw Runtime.Failure.opaqueByteCountLimitExceeded
        }
        let record = try OpalFusion.Mosaic.CanonicalDecoder.decode(
            from: Array(bytes)
        ) { decoder in
            guard try decoder.readText(maximumByteCount: 64) == domain,
                  try decoder.readUInt16() == version else {
                throw Runtime.Failure.malformedRecoverySnapshot
            }
            let binding = try Runtime.Binding(
                attemptIdentifier: Data(
                    decoder.readFixedBytes(byteCount: 32)
                ),
                generationIdentifier: Data(
                    decoder.readFixedBytes(byteCount: 32)
                ),
                materialIdentifier: Data(
                    decoder.readFixedBytes(byteCount: 32)
                )
            )
            switch try decoder.readUInt8() {
            case 0:
                let origin = try decoder.readUInt8()
                guard origin <= 1 else {
                    throw Runtime.Failure.malformedRecoverySnapshot
                }
                let phase = try Runtime.postManifestPhase(
                    forRecoveryTag: decoder.readUInt8()
                )
                return try OpalFusion.MosaicPrivateAlphaRuntime
                    .PostManifestTerminalRecord.abort(
                        binding: binding,
                        phase: phase,
                        event: Runtime.PrivateDeploymentEvent
                            .decodeRecoveryBytes(Data(decoder.readBytes(
                                maximumByteCount: Runtime.RecoveryState
                                    .maximumRecordByteCount
                            ))),
                        wasReceived: origin == 1
                    )
            case 1:
                return try OpalFusion.MosaicPrivateAlphaRuntime
                    .PostManifestTerminalRecord.completion(
                        binding: binding,
                        event: Runtime.PrivateDeploymentEvent
                            .decodeRecoveryBytes(Data(decoder.readBytes(
                                maximumByteCount: Runtime.RecoveryState
                                    .maximumRecordByteCount
                            )))
                    )
            default:
                throw Runtime.Failure.malformedRecoverySnapshot
            }
        }
        guard record.binding == expectedBinding else {
            throw Runtime.Failure.recoveryBindingMismatch
        }
        _ = try record.event.decodeCanonicalNostrEvent()
        guard try record.canonicalBytes() == bytes else {
            throw Runtime.Failure.nonCanonicalRecoverySnapshot
        }
        return record
    }
}
#endif

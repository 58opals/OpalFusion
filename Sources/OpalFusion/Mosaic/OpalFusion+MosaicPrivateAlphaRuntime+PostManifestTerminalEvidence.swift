// OpalFusion+MosaicPrivateAlphaRuntime+PostManifestTerminalEvidence.swift

#if os(macOS)
import Foundation

extension OpalFusion.MosaicPrivateAlphaRuntime {
    struct PostManifestTerminalEvidence: Equatable, Sendable {
        let binding: Binding
        let reason: TerminalReason
        let wasReceived: Bool
        let predecessorRevision: UInt64
        let predecessorSnapshotDigest: Data
        let localControlIdentity: Data
        let terminalIdentity: Data
        let event: PrivateDeploymentEvent
        let admissionSnapshotDigest: Data
        let publicationSnapshotDigest: Data

        func canonicalBytes() throws -> Data {
            var encoder = OpalFusion.Mosaic.CanonicalEncoder()
            try encoder.writeText(
                "OpalFusion/MosaicPrivateAlpha/terminal-evidence/2"
            )
            try encoder.writeFixedBytes(
                Array(binding.attemptIdentifier), byteCount: 32
            )
            try encoder.writeFixedBytes(
                Array(binding.generationIdentifier), byteCount: 32
            )
            try encoder.writeFixedBytes(
                Array(binding.materialIdentifier), byteCount: 32
            )
            encoder.writeUInt8(reason.recoveryTag)
            encoder.writeUInt8(wasReceived ? 1 : 0)
            encoder.writeUInt64(predecessorRevision)
            try encoder.writeFixedBytes(
                Array(predecessorSnapshotDigest), byteCount: 32
            )
            try encoder.writeFixedBytes(
                Array(localControlIdentity), byteCount: 32
            )
            try encoder.writeFixedBytes(
                Array(terminalIdentity), byteCount: 32
            )
            try encoder.writeBytes(Array(try event.canonicalRecoveryBytes()))
            try encoder.writeFixedBytes(
                Array(admissionSnapshotDigest), byteCount: 32
            )
            try encoder.writeFixedBytes(
                Array(publicationSnapshotDigest), byteCount: 32
            )
            return Data(encoder.encodedBytes)
        }

        init(
            binding: Binding,
            reason: TerminalReason,
            wasReceived: Bool,
            predecessorRevision: UInt64,
            predecessorSnapshotDigest: Data,
            localControlIdentity: Data,
            terminalIdentity: Data,
            event: PrivateDeploymentEvent,
            admissionSnapshotDigest: Data,
            publicationSnapshotDigest: Data
        ) throws {
            guard predecessorSnapshotDigest.count == 32,
                  localControlIdentity.count == 32,
                  terminalIdentity.count == 32,
                  admissionSnapshotDigest.count == 32,
                  publicationSnapshotDigest.count == 32 else {
                throw Failure.malformedRecoverySnapshot
            }
            self.binding = binding
            self.reason = reason
            self.wasReceived = wasReceived
            self.predecessorRevision = predecessorRevision
            self.predecessorSnapshotDigest = predecessorSnapshotDigest
            self.localControlIdentity = localControlIdentity
            self.terminalIdentity = terminalIdentity
            self.event = event
            self.admissionSnapshotDigest = admissionSnapshotDigest
            self.publicationSnapshotDigest = publicationSnapshotDigest
        }

        static func decode(
            _ bytes: Data,
            expectedBinding: Binding
        ) throws -> Self {
            guard bytes.count <= RecoveryState.maximumOpaqueByteCount else {
                throw Failure.opaqueByteCountLimitExceeded
            }
            let evidence = try OpalFusion.Mosaic.CanonicalDecoder.decode(
                from: Array(bytes)
            ) { decoder in
                guard try decoder.readText(maximumByteCount: 80)
                        == "OpalFusion/MosaicPrivateAlpha/terminal-evidence/2"
                else {
                    throw Failure.malformedRecoverySnapshot
                }
                let binding = try Binding(
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
                guard let reason = TerminalReason(
                    recoveryTag: try decoder.readUInt8()
                ) else {
                    throw Failure.malformedRecoverySnapshot
                }
                let origin = try decoder.readUInt8()
                guard origin <= 1 else {
                    throw Failure.malformedRecoverySnapshot
                }
                return try Self(
                    binding: binding,
                    reason: reason,
                    wasReceived: origin == 1,
                    predecessorRevision: try decoder.readUInt64(),
                    predecessorSnapshotDigest: Data(
                        decoder.readFixedBytes(byteCount: 32)
                    ),
                    localControlIdentity: Data(
                        decoder.readFixedBytes(byteCount: 32)
                    ),
                    terminalIdentity: Data(
                        decoder.readFixedBytes(byteCount: 32)
                    ),
                    event: .decodeRecoveryBytes(Data(
                        decoder.readBytes(
                            maximumByteCount:
                                RecoveryState.maximumRecordByteCount
                        )
                    )),
                    admissionSnapshotDigest: Data(
                        decoder.readFixedBytes(byteCount: 32)
                    ),
                    publicationSnapshotDigest: Data(
                        decoder.readFixedBytes(byteCount: 32)
                    )
                )
            }
            guard evidence.binding == expectedBinding,
                  try evidence.canonicalBytes() == bytes else {
                throw Failure.contradictoryRecoverySnapshot
            }
            return evidence
        }
    }
}
#endif

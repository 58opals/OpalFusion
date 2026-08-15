// OpalFusion+MosaicPrivateAlphaRuntime+PrivateDeploymentEvent.swift

#if os(macOS)
import Foundation

extension OpalFusion.MosaicPrivateAlphaRuntime {
    /// A canonical signed Nostr event and the durable time of its first local acceptance.
    @_spi(MosaicPrivateAlpha)
    public struct PrivateDeploymentEvent: Equatable, Sendable {
        @_spi(MosaicPrivateAlpha) public let canonicalEventBytes: Data
        @_spi(MosaicPrivateAlpha) public let acceptedAtUnixSeconds: UInt64

        @_spi(MosaicPrivateAlpha)
        public init(
            canonicalEventBytes: Data,
            acceptedAtUnixSeconds: UInt64
        ) throws {
            self.canonicalEventBytes = canonicalEventBytes
            self.acceptedAtUnixSeconds = acceptedAtUnixSeconds
            _ = try decodeCanonicalNostrEvent()
        }

        init(
            validatedCanonicalEventBytes: Data,
            acceptedAtUnixSeconds: UInt64
        ) {
            canonicalEventBytes = validatedCanonicalEventBytes
            self.acceptedAtUnixSeconds = acceptedAtUnixSeconds
        }

        func canonicalRecoveryBytes() throws -> Data {
            var encoder = OpalFusion.Mosaic.CanonicalEncoder()
            encoder.writeUInt8(1)
            encoder.writeUInt64(acceptedAtUnixSeconds)
            try encoder.writeBytes(Array(canonicalEventBytes))
            return Data(encoder.encodedBytes)
        }

        static func decodeRecoveryBytes(_ bytes: Data) throws -> Self {
            try OpalFusion.Mosaic.CanonicalDecoder.decode(
                from: Array(bytes)
            ) { decoder in
                guard try decoder.readUInt8() == 1 else {
                    throw OpalFusion.MosaicPrivateAlphaRuntime.Failure
                        .invalidPrivateDeploymentProof
                }
                let acceptedAt = try decoder.readUInt64()
                let eventBytes = Data(try decoder.readBytes())
                let event = try Self(
                    canonicalEventBytes: eventBytes,
                    acceptedAtUnixSeconds: acceptedAt
                )
                guard try event.canonicalRecoveryBytes() == bytes else {
                    throw OpalFusion.MosaicPrivateAlphaRuntime.Failure
                        .invalidPrivateDeploymentProof
                }
                return event
            }
        }

        func decodeCanonicalNostrEvent() throws
            -> OpalFusion.Mosaic.NostrNamespace.Event {
            let limits = try OpalFusion.Mosaic.NostrNamespace.EventCodingLimits(
                maximumEventJSONByteCount: 200_000,
                maximumTagCount: 1,
                maximumTagElementCount: 2,
                maximumStringByteCount: 150_000
            )
            let event = try OpalFusion.Mosaic.NostrNamespace.EventCodec.decode(
                canonicalEventBytes,
                limits: limits
            )
            guard try OpalFusion.Mosaic.NostrNamespace.EventCodec.encode(
                event,
                limits: limits
            ) == canonicalEventBytes else {
                throw OpalFusion.MosaicPrivateAlphaRuntime.Failure
                    .invalidPrivateDeploymentProof
            }
            return event
        }
    }
}
#endif

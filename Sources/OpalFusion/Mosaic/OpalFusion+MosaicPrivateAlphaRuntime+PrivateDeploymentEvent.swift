// OpalFusion+MosaicPrivateAlphaRuntime+PrivateDeploymentEvent.swift

#if os(macOS)
import Foundation

extension OpalFusion.MosaicPrivateAlphaRuntime {
    /// A canonical signed Nostr event and the durable time of its first local acceptance.
    @_spi(MosaicPrivateAlpha)
    public struct PrivateDeploymentEvent: Equatable, Sendable {
        @_spi(MosaicPrivateAlpha) public let canonicalEventBytes: Data
        @_spi(MosaicPrivateAlpha) public let acceptedAtUnixSeconds: UInt64
        private let validatedEvent: ValidatedEventBox

        @_spi(MosaicPrivateAlpha)
        public init(
            canonicalEventBytes: Data,
            acceptedAtUnixSeconds: UInt64
        ) throws {
            self.canonicalEventBytes = canonicalEventBytes
            self.acceptedAtUnixSeconds = acceptedAtUnixSeconds
            validatedEvent = try ValidatedEventBox(
                Self.decodeCanonicalNostrEvent(from: canonicalEventBytes)
            )
        }

        init(
            validatedCanonicalEventBytes: Data,
            acceptedAtUnixSeconds: UInt64,
            validatedEvent: OpalFusion.Mosaic.NostrNamespace.Event
        ) {
            canonicalEventBytes = validatedCanonicalEventBytes
            self.acceptedAtUnixSeconds = acceptedAtUnixSeconds
            self.validatedEvent = ValidatedEventBox(validatedEvent)
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

        /// Extracts the event bytes from an owner-held recovery record whose
        /// enclosing recovery state has already passed full validation.
        static func canonicalEventBytes(
            fromValidatedRecoveryBytes bytes: Data
        ) throws -> Data {
            try OpalFusion.Mosaic.CanonicalDecoder.decode(
                from: Array(bytes)
            ) { decoder in
                guard try decoder.readUInt8() == 1 else {
                    throw OpalFusion.MosaicPrivateAlphaRuntime.Failure
                        .invalidPrivateDeploymentProof
                }
                _ = try decoder.readUInt64()
                return Data(try decoder.readBytes())
            }
        }

        func decodeCanonicalNostrEvent() throws
            -> OpalFusion.Mosaic.NostrNamespace.Event {
            validatedEvent.value
        }

        @_spi(MosaicPrivateAlpha)
        public static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.canonicalEventBytes == rhs.canonicalEventBytes
                && lhs.acceptedAtUnixSeconds == rhs.acceptedAtUnixSeconds
        }

        private static func decodeCanonicalNostrEvent(
            from canonicalEventBytes: Data
        ) throws -> OpalFusion.Mosaic.NostrNamespace.Event {
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

    /// Keeps the validated crypto value off nested recovery-validation stacks.
    private final class ValidatedEventBox: Sendable {
        let value: OpalFusion.Mosaic.NostrNamespace.Event

        init(_ value: OpalFusion.Mosaic.NostrNamespace.Event) {
            self.value = value
        }
    }
}
#endif

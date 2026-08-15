// OpalFusion+MosaicPrivateAlphaRuntime+PrivateDeploymentEvent+Signing.swift

#if os(macOS)
import Foundation

extension OpalFusion.MosaicPrivateAlphaRuntime.PrivateDeploymentEvent {
    static func makeLocal(
        payload: OpalFusion.Mosaic.OpalMainnetAlpha
            .PreManifestNostrPayloadDocument,
        createdAtUnixSeconds: UInt64,
        signing: borrowing OpalFusion.MosaicPrivateAlphaRuntime
            .PrivateDeploymentSigningCapability
    ) throws -> Self {
        typealias Nostr = OpalFusion.Mosaic.NostrNamespace
        typealias Alpha = OpalFusion.Mosaic.OpalMainnetAlpha
        let limits = try Nostr.EventCodingLimits(
            maximumEventJSONByteCount: 200_000,
            maximumTagCount: 1,
            maximumTagElementCount: 2,
            maximumStringByteCount: 150_000
        )
        let event = try Alpha.PreManifestNostrCodec.makeEvent(
            for: payload,
            createdAtUnixSeconds: createdAtUnixSeconds,
            using: signing.signingKey,
            auxiliaryRandomness: signing.eventAuxiliaryRandomness,
            limits: limits
        )
        return .init(
            validatedCanonicalEventBytes: try Nostr.EventCodec.encode(
                event,
                limits: limits
            ),
            acceptedAtUnixSeconds: createdAtUnixSeconds
        )
    }
}
#endif

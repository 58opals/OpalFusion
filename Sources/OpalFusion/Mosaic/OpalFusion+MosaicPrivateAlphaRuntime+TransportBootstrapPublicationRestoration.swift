// OpalFusion+MosaicPrivateAlphaRuntime+TransportBootstrapPublicationRestoration.swift

#if os(macOS)
import Foundation
import OpalCrypto

extension OpalFusion.MosaicPrivateAlphaRuntime {
    /// Restores one exact, already-persisted bootstrap publication without rewrapping it.
    @_spi(MosaicPrivateAlpha)
    public static func restoreTransportBootstrapPublication(
        canonicalEventBytes: Data,
        canonicalDocument: Data,
        senderEventIdentity: Data,
        recipientEventIdentity: Data,
        proof: PrivateDeploymentProof,
        binding: Binding,
        expectedOperationIdentifier: Data,
        currentUnixSeconds: UInt64
    ) throws -> TransportBootstrapPublication {
        let context = TransportBootstrapContract.Context(proof: proof)
        guard (try? OpalCrypto.Signature.BIP340.VerificationKey(
            rawRepresentation: senderEventIdentity
        )) != nil,
        (try? OpalCrypto.Signature.BIP340.VerificationKey(
            rawRepresentation: recipientEventIdentity
        )) != nil else {
            throw TransportBootstrapFailure.invalidRecipient
        }
        try TransportBootstrapContract.validateCurrentTime(
            currentUnixSeconds,
            context: context
        )
        try TransportBootstrapContract.validateDocumentSize(canonicalDocument)

        let event: BootstrapNostr.Event
        do {
            let limits = try transportBootstrapCodingLimits()
            event = try BootstrapNostr.EventCodec.decode(
                canonicalEventBytes,
                limits: limits.event
            )
            guard try BootstrapNostr.EventCodec.encode(
                event,
                limits: limits.event
            ) == canonicalEventBytes else {
                throw TransportBootstrapFailure.invalidEvent
            }
        } catch let failure as TransportBootstrapFailure {
            throw failure
        } catch {
            throw TransportBootstrapFailure.invalidEvent
        }

        let recipientTag = [
            "p",
            BootstrapNostr.EventCodec.hexadecimal(recipientEventIdentity),
        ]
        let wrapperIdentity = event.publicKey.rawRepresentation
        guard event.template.kind == BootstrapNostr.NIP59EnvelopeCodec
                .DeliveryKind.regular.rawValue,
              event.template.tags == [recipientTag],
              event.template.content.utf8.count
                == OpalFusion.Mosaic.OpalMainnetAlpha
                    .nip59GiftWrapContentByteCount,
              event.template.createdAt >= context.phaseStartUnixSeconds,
              event.template.createdAt <= currentUnixSeconds,
              event.template.createdAt < context.expiryUnixSeconds,
              wrapperIdentity != senderEventIdentity,
              wrapperIdentity != recipientEventIdentity,
              !Set(context.preManifestEventIdentities).contains(
                  wrapperIdentity
              ) else {
            throw TransportBootstrapFailure.invalidEvent
        }
        let operationIdentifier = transportBootstrapOperationIdentifier(
            binding: binding,
            canonicalEventBytes: canonicalEventBytes,
            canonicalDocument: canonicalDocument,
            senderEventIdentity: senderEventIdentity,
            recipientEventIdentity: recipientEventIdentity,
            relayEndpointIdentifiers: proof.relayEndpointIdentifiers
        )
        guard operationIdentifier == expectedOperationIdentifier else {
            throw TransportBootstrapFailure.invalidBinding
        }
        return .init(
            canonicalEventBytes: canonicalEventBytes,
            canonicalDocument: canonicalDocument,
            senderEventIdentity: senderEventIdentity,
            recipientEventIdentity: recipientEventIdentity,
            wrapperEventIdentity: wrapperIdentity,
            messageIdentifier: event.identifier.rawRepresentation,
            operationIdentifier: operationIdentifier,
            binding: binding,
            relayEndpointIdentifiers: proof.relayEndpointIdentifiers
        )
    }
}
#endif

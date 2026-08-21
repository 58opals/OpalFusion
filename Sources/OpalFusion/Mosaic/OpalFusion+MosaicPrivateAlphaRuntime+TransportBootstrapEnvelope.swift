// OpalFusion+MosaicPrivateAlphaRuntime+TransportBootstrapEnvelope.swift

#if os(macOS)
import Foundation
import OpalCrypto

extension OpalFusion.MosaicPrivateAlphaRuntime {
    typealias BootstrapNostr = OpalFusion.Mosaic.NostrNamespace

    @_spi(MosaicPrivateAlpha)
    public static func sealTransportBootstrapAuthorizationKeyDocument(
        _ document: TransportBootstrapAuthorizationKeyDocument,
        proof: PrivateDeploymentProof,
        binding: Binding,
        conductorControlSigningKey: OpalCrypto.Secp256k1.SigningKey,
        recipientControlIdentity: Data,
        wrapperSigningKey: OpalCrypto.Secp256k1.SigningKey,
        reservedEventIdentities: Set<Data>,
        timestamps: TransportBootstrapLayerTimestamps
    ) throws -> TransportBootstrapPublication {
        let context = TransportBootstrapContract.Context(proof: proof)
        let validated = try loadTransportBootstrapAuthorizationKeyDocument(
            from: document.canonicalDocument,
            proof: proof,
            currentUnixSeconds: timestamps.currentUnixSeconds
        )
        guard conductorControlSigningKey.bip340VerificationKey
                .rawRepresentation == context.conductorControlIdentity else {
            throw TransportBootstrapFailure.invalidSigner
        }
        return try makeTransportBootstrapPublication(
            canonicalDocument: validated.canonicalDocument,
            senderSigningKey: conductorControlSigningKey,
            recipientEventIdentity: recipientControlIdentity,
            allowedRecipientEventIdentities: Set(context.controlIdentities),
            proof: proof,
            binding: binding,
            wrapperSigningKey: wrapperSigningKey,
            documentEventIdentities: [],
            reservedEventIdentities: reservedEventIdentities,
            timestamps: timestamps
        )
    }

    @_spi(MosaicPrivateAlpha)
    public static func sealTransportBootstrapControlMailboxClaim(
        _ claim: TransportBootstrapControlMailboxClaim,
        proof: PrivateDeploymentProof,
        authorizationKey: TransportBootstrapAuthorizationKeyDocument,
        binding: Binding,
        senderControlSigningKey: OpalCrypto.Secp256k1.SigningKey,
        recipientControlIdentity: Data,
        wrapperSigningKey: OpalCrypto.Secp256k1.SigningKey,
        reservedEventIdentities: Set<Data>,
        timestamps: TransportBootstrapLayerTimestamps
    ) throws -> TransportBootstrapPublication {
        let context = TransportBootstrapContract.Context(proof: proof)
        let key = try loadTransportBootstrapAuthorizationKeyDocument(
            from: authorizationKey.canonicalDocument,
            proof: proof,
            currentUnixSeconds: timestamps.currentUnixSeconds
        )
        let validated = try loadTransportBootstrapControlMailboxClaim(
            from: claim.canonicalDocument,
            context: context,
            authorizationKey: key,
            currentUnixSeconds: timestamps.currentUnixSeconds
        )
        guard validated.controlIdentity
                == senderControlSigningKey.bip340VerificationKey
                    .rawRepresentation else {
            throw TransportBootstrapFailure.invalidSigner
        }
        return try makeTransportBootstrapPublication(
            canonicalDocument: validated.canonicalDocument,
            senderSigningKey: senderControlSigningKey,
            recipientEventIdentity: recipientControlIdentity,
            allowedRecipientEventIdentities: Set(context.controlIdentities),
            proof: proof,
            binding: binding,
            wrapperSigningKey: wrapperSigningKey,
            documentEventIdentities: [validated.recipientEventIdentity],
            reservedEventIdentities: reservedEventIdentities,
            timestamps: timestamps
        )
    }

    @_spi(MosaicPrivateAlpha)
    public static func sealTransportBootstrapBlindResponseSet(
        _ responseSet: TransportBootstrapBlindResponseSet,
        proof: PrivateDeploymentProof,
        authorizationKey: TransportBootstrapAuthorizationKeyDocument,
        claimSet: TransportBootstrapControlMailboxClaimSet,
        binding: Binding,
        conductorControlSigningKey: OpalCrypto.Secp256k1.SigningKey,
        recipientContributorControlIdentity: Data,
        wrapperSigningKey: OpalCrypto.Secp256k1.SigningKey,
        reservedEventIdentities: Set<Data>,
        timestamps: TransportBootstrapLayerTimestamps
    ) throws -> TransportBootstrapPublication {
        let context = TransportBootstrapContract.Context(proof: proof)
        let validated = try loadTransportBootstrapBlindResponseSet(
            from: responseSet.canonicalDocument,
            proof: proof,
            authorizationKey: authorizationKey,
            claimSet: claimSet,
            currentUnixSeconds: timestamps.currentUnixSeconds
        )
        guard conductorControlSigningKey.bip340VerificationKey
                .rawRepresentation == context.conductorControlIdentity else {
            throw TransportBootstrapFailure.invalidSigner
        }
        return try makeTransportBootstrapPublication(
            canonicalDocument: validated.canonicalDocument,
            senderSigningKey: conductorControlSigningKey,
            recipientEventIdentity: recipientContributorControlIdentity,
            allowedRecipientEventIdentities:
                Set(context.contributorControlIdentities),
            proof: proof,
            binding: binding,
            wrapperSigningKey: wrapperSigningKey,
            documentEventIdentities: Set(
                claimSet.claims.map(\.recipientEventIdentity)
            ),
            reservedEventIdentities: reservedEventIdentities,
            timestamps: timestamps
        )
    }

    @_spi(MosaicPrivateAlpha)
    public static func sealTransportBootstrapAnonymousMailboxRegistration(
        _ registration: TransportBootstrapAnonymousMailboxRegistration,
        proof: PrivateDeploymentProof,
        authorizationKey: TransportBootstrapAuthorizationKeyDocument,
        claimSet: TransportBootstrapControlMailboxClaimSet,
        responseSet: TransportBootstrapBlindResponseSet,
        binding: Binding,
        anonymousSenderSigningKey: OpalCrypto.Secp256k1.SigningKey,
        conductorControlIdentity: Data,
        wrapperSigningKey: OpalCrypto.Secp256k1.SigningKey,
        reservedEventIdentities: Set<Data>,
        timestamps: TransportBootstrapLayerTimestamps
    ) throws -> TransportBootstrapPublication {
        let context = TransportBootstrapContract.Context(proof: proof)
        let documents = try validateTransportBootstrapRegistrationDocuments(
            proof: proof,
            authorizationKey: authorizationKey,
            claimSet: claimSet,
            responseSet: responseSet,
            currentUnixSeconds: timestamps.currentUnixSeconds
        )
        guard registration.authorizationKeyDocumentDigest
                == documents.authorizationKey.digest,
              registration.claimSetDigest == documents.claimSet.digest,
              registration.responseSetDigest == documents.responseSet.digest
        else {
            throw TransportBootstrapFailure.invalidBinding
        }
        guard anonymousSenderSigningKey.bip340VerificationKey
                .rawRepresentation
                == registration.anonymousSenderEventIdentity,
              conductorControlIdentity
                == context.conductorControlIdentity else {
            throw TransportBootstrapFailure.invalidSigner
        }
        return try makeTransportBootstrapPublication(
            canonicalDocument: registration.canonicalDocument,
            senderSigningKey: anonymousSenderSigningKey,
            recipientEventIdentity: conductorControlIdentity,
            allowedRecipientEventIdentities:
                [context.conductorControlIdentity],
            proof: proof,
            binding: binding,
            wrapperSigningKey: wrapperSigningKey,
            documentEventIdentities: Set(
                claimSet.claims.map(\.recipientEventIdentity)
            ).union([registration.anonymousSenderEventIdentity]),
            reservedEventIdentities: reservedEventIdentities,
            timestamps: timestamps
        )
    }

    @_spi(MosaicPrivateAlpha)
    public static func sealTransportBootstrapAnonymousMailboxAssignment(
        _ assignment: TransportBootstrapAnonymousMailboxAssignment,
        proof: PrivateDeploymentProof,
        authorizationKey: TransportBootstrapAuthorizationKeyDocument,
        claimSet: TransportBootstrapControlMailboxClaimSet,
        responseSet: TransportBootstrapBlindResponseSet,
        registration: TransportBootstrapAnonymousMailboxRegistration,
        binding: Binding,
        conductorControlSigningKey: OpalCrypto.Secp256k1.SigningKey,
        wrapperSigningKey: OpalCrypto.Secp256k1.SigningKey,
        reservedEventIdentities: Set<Data>,
        timestamps: TransportBootstrapLayerTimestamps
    ) throws -> TransportBootstrapPublication {
        let context = TransportBootstrapContract.Context(proof: proof)
        let documents = try validateTransportBootstrapRegistrationDocuments(
            proof: proof,
            authorizationKey: authorizationKey,
            claimSet: claimSet,
            responseSet: responseSet,
            currentUnixSeconds: timestamps.currentUnixSeconds
        )
        guard registration.authorizationKeyDocumentDigest
                == documents.authorizationKey.digest,
              registration.claimSetDigest == documents.claimSet.digest,
              registration.responseSetDigest == documents.responseSet.digest,
              assignment.registrationDigest == registration.digest,
              assignment.anonymousRecipientEventIdentity
                == registration.anonymousSenderEventIdentity else {
            throw TransportBootstrapFailure.invalidBinding
        }
        guard conductorControlSigningKey.bip340VerificationKey
                .rawRepresentation == context.conductorControlIdentity else {
            throw TransportBootstrapFailure.invalidSigner
        }
        return try makeTransportBootstrapPublication(
            canonicalDocument: assignment.canonicalDocument,
            senderSigningKey: conductorControlSigningKey,
            recipientEventIdentity:
                assignment.anonymousRecipientEventIdentity,
            allowedRecipientEventIdentities: [
                registration.anonymousSenderEventIdentity,
            ],
            proof: proof,
            binding: binding,
            wrapperSigningKey: wrapperSigningKey,
            documentEventIdentities: Set(
                assignment.recipientEventIdentities
                    + claimSet.claims.map(\.recipientEventIdentity)
            ),
            reservedEventIdentities: reservedEventIdentities,
            timestamps: timestamps
        )
    }

    @_spi(MosaicPrivateAlpha)
    public static func openTransportBootstrapControlMailboxClaim(
        from canonicalEventBytes: Data,
        proof: PrivateDeploymentProof,
        authorizationKey: TransportBootstrapAuthorizationKeyDocument,
        recipientControlSigningKey: OpalCrypto.Secp256k1.SigningKey,
        currentUnixSeconds: UInt64
    ) throws -> TransportBootstrapOpenedPublication<
        TransportBootstrapControlMailboxClaim
    > {
        let context = TransportBootstrapContract.Context(proof: proof)
        let key = try loadTransportBootstrapAuthorizationKeyDocument(
            from: authorizationKey.canonicalDocument,
            proof: proof,
            currentUnixSeconds: currentUnixSeconds
        )
        let opened = try openTransportBootstrapEvent(
            canonicalEventBytes,
            proof: proof,
            recipientSigningKey: recipientControlSigningKey,
            allowedRecipientEventIdentities: Set(context.controlIdentities),
            excludedWrapperEventIdentities: Set(
                context.preManifestEventIdentities
            ),
            currentUnixSeconds: currentUnixSeconds
        )
        let claim = try loadTransportBootstrapControlMailboxClaim(
            from: opened.canonicalDocument,
            context: context,
            authorizationKey: key,
            currentUnixSeconds: currentUnixSeconds
        )
        guard claim.controlIdentity == opened.senderEventIdentity,
              opened.wrapperEventIdentity
                != claim.recipientEventIdentity else {
            throw TransportBootstrapFailure.invalidSigner
        }
        return opened.projecting(claim)
    }

    @_spi(MosaicPrivateAlpha)
    public static func openTransportBootstrapAnonymousMailboxRegistration(
        from canonicalEventBytes: Data,
        proof: PrivateDeploymentProof,
        authorizationKey: TransportBootstrapAuthorizationKeyDocument,
        claimSet: TransportBootstrapControlMailboxClaimSet,
        responseSet: TransportBootstrapBlindResponseSet,
        conductorControlSigningKey: OpalCrypto.Secp256k1.SigningKey,
        currentUnixSeconds: UInt64
    ) throws -> TransportBootstrapOpenedPublication<
        TransportBootstrapAnonymousMailboxRegistration
    > {
        let context = TransportBootstrapContract.Context(proof: proof)
        let opened = try openTransportBootstrapEvent(
            canonicalEventBytes,
            proof: proof,
            recipientSigningKey: conductorControlSigningKey,
            allowedRecipientEventIdentities:
                [context.conductorControlIdentity],
            excludedWrapperEventIdentities: Set(
                context.preManifestEventIdentities
                    + claimSet.claims.map(\.recipientEventIdentity)
            ),
            currentUnixSeconds: currentUnixSeconds
        )
        let registration = try loadTransportBootstrapAnonymousMailboxRegistration(
            from: opened.canonicalDocument,
            proof: proof,
            authorizationKey: authorizationKey,
            claimSet: claimSet,
            responseSet: responseSet,
            currentUnixSeconds: currentUnixSeconds
        )
        guard registration.anonymousSenderEventIdentity
                == opened.senderEventIdentity else {
            throw TransportBootstrapFailure.invalidSigner
        }
        return opened.projecting(registration)
    }

    @_spi(MosaicPrivateAlpha)
    public static func openTransportBootstrapAnonymousMailboxAssignment(
        from canonicalEventBytes: Data,
        proof: PrivateDeploymentProof,
        authorizationKey: TransportBootstrapAuthorizationKeyDocument,
        claimSet: TransportBootstrapControlMailboxClaimSet,
        responseSet: TransportBootstrapBlindResponseSet,
        registration: TransportBootstrapAnonymousMailboxRegistration,
        anonymousRecipientSigningKey: OpalCrypto.Secp256k1.SigningKey,
        currentUnixSeconds: UInt64
    ) throws -> TransportBootstrapOpenedPublication<
        TransportBootstrapAnonymousMailboxAssignment
    > {
        let context = TransportBootstrapContract.Context(proof: proof)
        let opened = try openTransportBootstrapEvent(
            canonicalEventBytes,
            proof: proof,
            recipientSigningKey: anonymousRecipientSigningKey,
            allowedRecipientEventIdentities: [
                registration.anonymousSenderEventIdentity,
            ],
            excludedWrapperEventIdentities: Set(
                context.preManifestEventIdentities
                    + claimSet.claims.map(\.recipientEventIdentity)
            ),
            currentUnixSeconds: currentUnixSeconds
        )
        let assignment = try loadTransportBootstrapAnonymousMailboxAssignment(
            from: opened.canonicalDocument,
            proof: proof,
            authorizationKey: authorizationKey,
            claimSet: claimSet,
            responseSet: responseSet,
            registration: registration,
            currentUnixSeconds: currentUnixSeconds
        )
        guard opened.senderEventIdentity
                == context.conductorControlIdentity,
              !assignment.recipientEventIdentities.contains(
                  opened.wrapperEventIdentity
              ) else {
            throw TransportBootstrapFailure.invalidSigner
        }
        return opened.projecting(assignment)
    }

    struct OpenedTransportBootstrapEvent {
        let canonicalDocument: Data
        let senderEventIdentity: Data
        let recipientEventIdentity: Data
        let wrapperEventIdentity: Data
        let messageIdentifier: Data

        func projecting<Document: Sendable>(
            _ document: Document
        ) -> TransportBootstrapOpenedPublication<Document> {
            .init(
                document: document,
                senderEventIdentity: senderEventIdentity,
                recipientEventIdentity: recipientEventIdentity,
                wrapperEventIdentity: wrapperEventIdentity,
                messageIdentifier: messageIdentifier
            )
        }
    }

    static func makeTransportBootstrapPublication(
        canonicalDocument: Data,
        senderSigningKey: OpalCrypto.Secp256k1.SigningKey,
        recipientEventIdentity: Data,
        allowedRecipientEventIdentities: Set<Data>,
        proof: PrivateDeploymentProof,
        binding: Binding,
        wrapperSigningKey: OpalCrypto.Secp256k1.SigningKey,
        documentEventIdentities: Set<Data>,
        reservedEventIdentities: Set<Data>,
        timestamps: TransportBootstrapLayerTimestamps
    ) throws -> TransportBootstrapPublication {
        let context = TransportBootstrapContract.Context(proof: proof)
        guard allowedRecipientEventIdentities.contains(
                  recipientEventIdentity
              ),
              let recipientVerificationKey = try? OpalCrypto.Signature.BIP340
                .VerificationKey(
                    rawRepresentation: recipientEventIdentity
                ) else {
            throw TransportBootstrapFailure.invalidRecipient
        }
        let senderIdentity = senderSigningKey.bip340VerificationKey
            .rawRepresentation
        let wrapperIdentity = wrapperSigningKey.bip340VerificationKey
            .rawRepresentation
        let unavailableIdentities = Set(
            proof.preManifestEventIdentities
        ).union(documentEventIdentities).union(reservedEventIdentities)
        guard wrapperIdentity != senderIdentity,
              wrapperIdentity != recipientEventIdentity,
              !unavailableIdentities.contains(wrapperIdentity) else {
            throw TransportBootstrapFailure.wrapperIdentityReuse
        }
        guard documentEventIdentities.allSatisfy({ $0.count == 32 }),
              reservedEventIdentities.allSatisfy({ $0.count == 32 }) else {
            throw TransportBootstrapFailure.invalidEvent
        }
        try validateTransportBootstrapTimestamps(
            timestamps,
            context: context
        )
        let event = try makeTransportBootstrapEvent(
            canonicalDocument: canonicalDocument,
            senderSigningKey: senderSigningKey,
            recipientVerificationKey: recipientVerificationKey,
            wrapperSigningKey: wrapperSigningKey,
            timestamps: timestamps
        )
        let limits = try transportBootstrapCodingLimits()
        let canonicalEventBytes = try BootstrapNostr.EventCodec.encode(
            event,
            limits: limits.event
        )
        guard event.publicKey.rawRepresentation == wrapperIdentity else {
            throw TransportBootstrapFailure.invalidEvent
        }
        let operationIdentifier = transportBootstrapOperationIdentifier(
            binding: binding,
            canonicalEventBytes: canonicalEventBytes,
            canonicalDocument: canonicalDocument,
            senderEventIdentity: senderIdentity,
            recipientEventIdentity: recipientEventIdentity,
            relayEndpointIdentifiers: proof.relayEndpointIdentifiers
        )
        return .init(
            canonicalEventBytes: canonicalEventBytes,
            canonicalDocument: canonicalDocument,
            senderEventIdentity: senderIdentity,
            recipientEventIdentity: recipientEventIdentity,
            wrapperEventIdentity: wrapperIdentity,
            messageIdentifier: event.identifier.rawRepresentation,
            operationIdentifier: operationIdentifier,
            binding: binding,
            relayEndpointIdentifiers: proof.relayEndpointIdentifiers
        )
    }

    static func openTransportBootstrapEvent(
        _ canonicalEventBytes: Data,
        proof: PrivateDeploymentProof,
        recipientSigningKey: OpalCrypto.Secp256k1.SigningKey,
        allowedRecipientEventIdentities: Set<Data>,
        excludedWrapperEventIdentities: Set<Data>,
        currentUnixSeconds: UInt64
    ) throws -> OpenedTransportBootstrapEvent {
        let context = TransportBootstrapContract.Context(proof: proof)
        let recipientIdentity = recipientSigningKey
            .bip340VerificationKey.rawRepresentation
        guard allowedRecipientEventIdentities.contains(recipientIdentity)
        else {
            throw TransportBootstrapFailure.invalidRecipient
        }
        let event: BootstrapNostr.Event
        let opened: BootstrapNostr.NIP59EnvelopeCodec.AuthenticatedRumor
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
            opened = try BootstrapNostr.NIP59EnvelopeCodec.open(
                event,
                expectedDeliveryKind: .regular,
                expectedRumorKind:
                    OpalFusion.Mosaic.OpalMainnetAlpha.nip59RumorKind,
                recipientSigningKey: recipientSigningKey,
                limits: limits
            )
        } catch let failure as TransportBootstrapFailure {
            throw failure
        } catch {
            throw TransportBootstrapFailure.invalidEvent
        }
        let senderIdentity = opened.senderPublicKey.rawRepresentation
        let wrapperIdentity = event.publicKey.rawRepresentation
        guard opened.rumor.template.tags == transportBootstrapRumorTags,
              opened.recipientPublicKey.rawRepresentation
                == recipientIdentity,
              opened.sealContentByteCount
                == OpalFusion.Mosaic.OpalMainnetAlpha
                    .nip59SealContentByteCount,
              opened.giftWrapContentByteCount
                == OpalFusion.Mosaic.OpalMainnetAlpha
                    .nip59GiftWrapContentByteCount else {
            throw TransportBootstrapFailure.invalidEvent
        }
        guard wrapperIdentity != senderIdentity,
              wrapperIdentity != recipientIdentity,
              !excludedWrapperEventIdentities.contains(wrapperIdentity) else {
            throw TransportBootstrapFailure.wrapperIdentityReuse
        }
        guard opened.rumor.template.createdAt <= currentUnixSeconds,
              currentUnixSeconds <= context.expiryUnixSeconds,
              context.phaseStartUnixSeconds
                < opened.rumor.template.createdAt,
              opened.rumor.template.createdAt
                <= context.expiryUnixSeconds,
              opened.sealCreatedAt >= context.phaseStartUnixSeconds,
              opened.sealCreatedAt < opened.rumor.template.createdAt,
              opened.giftWrapCreatedAt >= context.phaseStartUnixSeconds,
              opened.giftWrapCreatedAt < opened.rumor.template.createdAt else {
            throw TransportBootstrapFailure.invalidTimestamp
        }
        let document: Data
        do {
            document = Data(try OpalFusion.Mosaic.PaddedEnvelopeCodec.decode(
                opened.rumor.template.content
            ))
        } catch {
            throw TransportBootstrapFailure.invalidCanonicalDocument
        }
        return .init(
            canonicalDocument: document,
            senderEventIdentity: senderIdentity,
            recipientEventIdentity: recipientIdentity,
            wrapperEventIdentity: wrapperIdentity,
            messageIdentifier: event.identifier.rawRepresentation
        )
    }

    private static func makeTransportBootstrapEvent(
        canonicalDocument: Data,
        senderSigningKey: OpalCrypto.Secp256k1.SigningKey,
        recipientVerificationKey:
            OpalCrypto.Signature.BIP340.VerificationKey,
        wrapperSigningKey: OpalCrypto.Secp256k1.SigningKey,
        timestamps: TransportBootstrapLayerTimestamps
    ) throws -> BootstrapNostr.Event {
        let content: String
        do {
            content = try OpalFusion.Mosaic.PaddedEnvelopeCodec.encode(
                Array(canonicalDocument)
            )
        } catch {
            throw TransportBootstrapFailure.invalidCanonicalDocument
        }
        guard content.utf8.count == OpalFusion.Mosaic.OpalMainnetAlpha
                .nip59ApplicationContentByteCount else {
            throw TransportBootstrapFailure.invalidCanonicalDocument
        }
        do {
            let limits = try transportBootstrapCodingLimits()
            let template = try BootstrapNostr.EventTemplate(
                createdAt: timestamps.rumorCreatedAt,
                kind: OpalFusion.Mosaic.OpalMainnetAlpha.nip59RumorKind,
                tags: transportBootstrapRumorTags,
                content: content,
                limits: limits.event
            )
            let rumor = try BootstrapNostr.UnsignedEvent(
                publicKey: senderSigningKey.bip340VerificationKey,
                template: template,
                limits: limits.event
            )
            let seal = try BootstrapNostr.NIP59EnvelopeCodec.seal(
                rumor,
                createdAt: timestamps.sealCreatedAt,
                senderSigningKey: senderSigningKey,
                recipientPublicKey: recipientVerificationKey,
                limits: limits
            )
            let giftWrap = try BootstrapNostr.NIP59EnvelopeCodec.wrap(
                seal,
                deliveryKind: .regular,
                createdAt: timestamps.giftWrapCreatedAt,
                wrapperSigningKey: wrapperSigningKey,
                limits: limits
            )
            guard seal.event.template.content.utf8.count
                    == OpalFusion.Mosaic.OpalMainnetAlpha
                        .nip59SealContentByteCount,
                  giftWrap.template.content.utf8.count
                    == OpalFusion.Mosaic.OpalMainnetAlpha
                        .nip59GiftWrapContentByteCount,
                  try BootstrapNostr.EventCodec.encode(
                    giftWrap,
                    limits: limits.event
                  ).count <= OpalFusion.Mosaic.OpalMainnetAlpha
                    .nip59MaximumGiftWrapJSONByteCount else {
                throw TransportBootstrapFailure.invalidEvent
            }
            return giftWrap
        } catch let failure as TransportBootstrapFailure {
            throw failure
        } catch {
            throw TransportBootstrapFailure.invalidEvent
        }
    }

    private static func validateTransportBootstrapTimestamps(
        _ timestamps: TransportBootstrapLayerTimestamps,
        context: TransportBootstrapContract.Context
    ) throws {
        guard timestamps.currentUnixSeconds
                >= timestamps.rumorCreatedAt,
              timestamps.currentUnixSeconds <= context.expiryUnixSeconds,
              context.phaseStartUnixSeconds < timestamps.rumorCreatedAt,
              timestamps.rumorCreatedAt <= context.expiryUnixSeconds,
              timestamps.sealCreatedAt >= context.phaseStartUnixSeconds,
              timestamps.sealCreatedAt < timestamps.rumorCreatedAt,
              timestamps.giftWrapCreatedAt
                >= context.phaseStartUnixSeconds,
              timestamps.giftWrapCreatedAt
                < timestamps.rumorCreatedAt else {
            throw TransportBootstrapFailure.invalidTimestamp
        }
    }

    static func transportBootstrapCodingLimits()
        throws -> BootstrapNostr.NIP59EnvelopeCodec.CodingLimits {
        let event = try BootstrapNostr.EventCodingLimits(
            maximumEventJSONByteCount:
                OpalFusion.Mosaic.OpalMainnetAlpha
                    .nip59MaximumGiftWrapJSONByteCount,
            maximumTagCount: 1,
            maximumTagElementCount: 2,
            maximumStringByteCount:
                OpalFusion.Mosaic.OpalMainnetAlpha
                    .nip59GiftWrapContentByteCount
        )
        return try .init(
            event: event,
            maximumRumorJSONByteCount:
                OpalFusion.Mosaic.OpalMainnetAlpha
                    .nip59MaximumRumorJSONByteCount,
            maximumSealJSONByteCount:
                OpalFusion.Mosaic.OpalMainnetAlpha
                    .nip59MaximumSealJSONByteCount
        )
    }

    private static var transportBootstrapRumorTags: [[String]] {
        [["d", TransportBootstrapContract.nostrSelector]]
    }

    static func transportBootstrapOperationIdentifier(
        binding: Binding,
        canonicalEventBytes: Data,
        canonicalDocument: Data,
        senderEventIdentity: Data,
        recipientEventIdentity: Data,
        relayEndpointIdentifiers: [String]
    ) -> Data {
        var data = Data(
            "OpalFusion/MosaicPrivateAlpha/bootstrap-publication/1".utf8
        )
        data.append(binding.attemptIdentifier)
        data.append(binding.generationIdentifier)
        data.append(binding.materialIdentifier)
        data.append(senderEventIdentity)
        data.append(recipientEventIdentity)
        data.append(OpalCrypto.Hashing.sha256(canonicalDocument))
        data.append(OpalCrypto.Hashing.sha256(canonicalEventBytes))
        for endpoint in relayEndpointIdentifiers.sorted() {
            data.append(OpalCrypto.Hashing.sha256(Data(endpoint.utf8)))
        }
        return OpalCrypto.Hashing.sha256(data)
    }
}
#endif

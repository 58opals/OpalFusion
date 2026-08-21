// OpalFusion+MosaicPrivateAlphaRuntime+TransportBootstrapControlMailboxDocuments.swift

#if os(macOS)
import Foundation
import OpalCrypto

extension OpalFusion.MosaicPrivateAlphaRuntime {
    @_spi(MosaicPrivateAlpha)
    public static var transportBootstrapIdentifier: String {
        TransportBootstrapContract.identifier
    }

    @_spi(MosaicPrivateAlpha)
    public static var transportBootstrapNostrSelector: String {
        TransportBootstrapContract.nostrSelector
    }

    @_spi(MosaicPrivateAlpha)
    public static func makeTransportBootstrapControlMailboxClaim(
        proof: PrivateDeploymentProof,
        authorizationKey: TransportBootstrapAuthorizationKeyDocument,
        controlSigningKey: OpalCrypto.Secp256k1.SigningKey,
        recipientEventVerificationKey:
            OpalCrypto.Signature.BIP340.VerificationKey,
        anonymousMailboxRequest:
            TransportBootstrapAnonymousMailboxRequest?,
        auxiliaryRandomness:
            OpalCrypto.Signature.BIP340.AuxiliaryRandomness
    ) throws -> TransportBootstrapControlMailboxClaim {
        let context = TransportBootstrapContract.Context(proof: proof)
        let keyDocument = try makeTransportBootstrapAuthorizationKeyDocument(
            canonicalDocument: authorizationKey.canonicalDocument,
            context: context,
            currentUnixSeconds: nil
        )
        let controlIdentity = controlSigningKey.bip340VerificationKey
            .rawRepresentation
        let recipientIdentity = recipientEventVerificationKey
            .rawRepresentation
        guard context.controlIdentities.contains(controlIdentity) else {
            throw TransportBootstrapFailure.invalidSigner
        }
        let isContributor = context.contributorControlIdentities.contains(
            controlIdentity
        )
        guard isContributor == (anonymousMailboxRequest != nil) else {
            throw TransportBootstrapFailure.invalidBlindRequest
        }
        if let anonymousMailboxRequest {
            guard anonymousMailboxRequest.input.authorizationKeyIdentifier
                    == keyDocument.verificationKey.keyIdentifier else {
                throw TransportBootstrapFailure.invalidBlindRequest
            }
        }
        try TransportBootstrapContract.validateEventIdentity(
            recipientIdentity,
            excluding: Set(context.preManifestEventIdentities)
        )

        var encoder = OpalFusion.Mosaic.CanonicalEncoder()
        try TransportBootstrapContract.writeCommon(
            to: &encoder,
            context: context,
            kind: .controlMailboxClaim
        )
        try encoder.writeFixedBytes(Array(keyDocument.digest), byteCount: 32)
        try encoder.writeFixedBytes(Array(controlIdentity), byteCount: 32)
        try encoder.writeFixedBytes(Array(recipientIdentity), byteCount: 32)
        if let anonymousMailboxRequest {
            encoder.writeUInt8(1)
            try encoder.writeFixedBytes(
                Array(anonymousMailboxRequest.blindedMessage),
                byteCount: 256
            )
        } else {
            encoder.writeUInt8(0)
        }
        let body = Data(encoder.encodedBytes)
        let signature = try TransportBootstrapContract.sign(
            body: body,
            suffix: "control-mailbox-claim",
            using: controlSigningKey,
            auxiliaryRandomness: auxiliaryRandomness
        )
        var canonical = body
        canonical.append(signature)
        return try loadTransportBootstrapControlMailboxClaim(
            from: canonical,
            context: context,
            authorizationKey: keyDocument,
            currentUnixSeconds: nil
        )
    }

    @_spi(MosaicPrivateAlpha)
    public static func loadTransportBootstrapControlMailboxClaim(
        from canonicalDocument: Data,
        proof: PrivateDeploymentProof,
        authorizationKey: TransportBootstrapAuthorizationKeyDocument,
        currentUnixSeconds: UInt64
    ) throws -> TransportBootstrapControlMailboxClaim {
        let context = TransportBootstrapContract.Context(proof: proof)
        let keyDocument = try makeTransportBootstrapAuthorizationKeyDocument(
            canonicalDocument: authorizationKey.canonicalDocument,
            context: context,
            currentUnixSeconds: currentUnixSeconds
        )
        return try loadTransportBootstrapControlMailboxClaim(
            from: canonicalDocument,
            context: context,
            authorizationKey: keyDocument,
            currentUnixSeconds: currentUnixSeconds
        )
    }

    @_spi(MosaicPrivateAlpha)
    public static func makeTransportBootstrapControlMailboxClaimSet(
        proof: PrivateDeploymentProof,
        authorizationKey: TransportBootstrapAuthorizationKeyDocument,
        claims: [TransportBootstrapControlMailboxClaim]
    ) throws -> TransportBootstrapControlMailboxClaimSet {
        let context = TransportBootstrapContract.Context(proof: proof)
        let keyDocument = try makeTransportBootstrapAuthorizationKeyDocument(
            canonicalDocument: authorizationKey.canonicalDocument,
            context: context,
            currentUnixSeconds: nil
        )
        return try makeTransportBootstrapControlMailboxClaimSet(
            context: context,
            authorizationKey: keyDocument,
            claims: claims
        )
    }

    @_spi(MosaicPrivateAlpha)
    public static func loadTransportBootstrapControlMailboxClaimSet(
        from canonicalDocument: Data,
        proof: PrivateDeploymentProof,
        authorizationKey: TransportBootstrapAuthorizationKeyDocument,
        currentUnixSeconds: UInt64
    ) throws -> TransportBootstrapControlMailboxClaimSet {
        let context = TransportBootstrapContract.Context(proof: proof)
        let keyDocument = try makeTransportBootstrapAuthorizationKeyDocument(
            canonicalDocument: authorizationKey.canonicalDocument,
            context: context,
            currentUnixSeconds: currentUnixSeconds
        )
        try TransportBootstrapContract.validateAggregateDocumentSize(
            canonicalDocument
        )
        let claims: [TransportBootstrapControlMailboxClaim]
        do {
            claims = try OpalFusion.Mosaic.CanonicalDecoder.decode(
                from: Array(canonicalDocument)
            ) { decoder in
                guard try decoder.readText()
                        == TransportBootstrapContract.identifier,
                      Data(try decoder.readFixedBytes(byteCount: 32))
                        == context.roundIdentifier,
                      Data(try decoder.readFixedBytes(byteCount: 32))
                        == context.relaySetDigest,
                      Data(try decoder.readFixedBytes(byteCount: 32))
                        == keyDocument.digest else {
                    throw TransportBootstrapFailure.invalidBinding
                }
                return try decoder.readVector(
                    maximumCount: context.controlIdentities.count
                ) { decoder in
                    try loadTransportBootstrapControlMailboxClaim(
                        from: Data(try decoder.readBytes(
                            maximumByteCount: TransportBootstrapContract
                                .maximumCanonicalDocumentByteCount
                        )),
                        context: context,
                        authorizationKey: keyDocument,
                        currentUnixSeconds: currentUnixSeconds
                    )
                }
            }
        } catch let failure as TransportBootstrapFailure {
            throw failure
        } catch {
            throw TransportBootstrapFailure.invalidCanonicalDocument
        }
        let result = try makeTransportBootstrapControlMailboxClaimSet(
            context: context,
            authorizationKey: keyDocument,
            claims: claims
        )
        guard result.canonicalDocument == canonicalDocument else {
            throw TransportBootstrapFailure.invalidCanonicalDocument
        }
        return result
    }

    static func loadTransportBootstrapControlMailboxClaim(
        from canonicalDocument: Data,
        context: TransportBootstrapContract.Context,
        authorizationKey: TransportBootstrapAuthorizationKeyDocument,
        currentUnixSeconds: UInt64?
    ) throws -> TransportBootstrapControlMailboxClaim {
        try TransportBootstrapContract.validateDocumentSize(canonicalDocument)
        let decoded: (
            body: Data,
            authorizationKeyDigest: Data,
            controlIdentity: Data,
            recipientIdentity: Data,
            blindedMessage: Data?,
            signature: Data
        )
        do {
            decoded = try OpalFusion.Mosaic.CanonicalDecoder.decode(
                from: Array(canonicalDocument)
            ) { decoder in
                try TransportBootstrapContract.readCommon(
                    from: &decoder,
                    context: context,
                    expectedKind: .controlMailboxClaim
                )
                let bodyByteCount = canonicalDocument.count - 64
                guard bodyByteCount > 0 else {
                    throw TransportBootstrapFailure
                        .invalidCanonicalDocument
                }
                let authorizationKeyDigest = Data(
                    try decoder.readFixedBytes(byteCount: 32)
                )
                let controlIdentity = Data(
                    try decoder.readFixedBytes(byteCount: 32)
                )
                let recipientIdentity = Data(
                    try decoder.readFixedBytes(byteCount: 32)
                )
                let requestFlag = try decoder.readUInt8()
                let blindedMessage: Data?
                switch requestFlag {
                case 0:
                    blindedMessage = nil
                case 1:
                    blindedMessage = Data(
                        try decoder.readFixedBytes(byteCount: 256)
                    )
                default:
                    throw TransportBootstrapFailure.invalidBlindRequest
                }
                let signature = Data(
                    try decoder.readFixedBytes(byteCount: 64)
                )
                return (
                    canonicalDocument.prefix(bodyByteCount),
                    authorizationKeyDigest,
                    controlIdentity,
                    recipientIdentity,
                    blindedMessage,
                    signature
                )
            }
        } catch let failure as TransportBootstrapFailure {
            throw failure
        } catch {
            throw TransportBootstrapFailure.invalidCanonicalDocument
        }
        guard decoded.authorizationKeyDigest == authorizationKey.digest,
              context.controlIdentities.contains(decoded.controlIdentity),
              context.contributorControlIdentities.contains(
                  decoded.controlIdentity
              ) == (decoded.blindedMessage != nil) else {
            throw TransportBootstrapFailure.invalidBlindRequest
        }
        try TransportBootstrapContract.validateEventIdentity(
            decoded.recipientIdentity,
            excluding: Set(context.preManifestEventIdentities)
        )
        try TransportBootstrapContract.verifySignature(
            decoded.signature,
            body: decoded.body,
            suffix: "control-mailbox-claim",
            signerIdentity: decoded.controlIdentity
        )
        try TransportBootstrapContract.validateCurrentTime(
            currentUnixSeconds,
            context: context
        )
        return .init(
            controlIdentity: decoded.controlIdentity,
            recipientEventIdentity: decoded.recipientIdentity,
            authorizationKeyDocumentDigest:
                decoded.authorizationKeyDigest,
            blindedMessage: decoded.blindedMessage,
            expiryUnixSeconds: context.expiryUnixSeconds,
            canonicalDocument: canonicalDocument,
            signature: decoded.signature
        )
    }

    static func makeTransportBootstrapControlMailboxClaimSet(
        context: TransportBootstrapContract.Context,
        authorizationKey: TransportBootstrapAuthorizationKeyDocument,
        claims: [TransportBootstrapControlMailboxClaim]
    ) throws -> TransportBootstrapControlMailboxClaimSet {
        guard claims.count == context.controlIdentities.count else {
            throw TransportBootstrapFailure.invalidClaimCount
        }
        let normalized = try claims.map {
            try loadTransportBootstrapControlMailboxClaim(
                from: $0.canonicalDocument,
                context: context,
                authorizationKey: authorizationKey,
                currentUnixSeconds: nil
            )
        }.sorted {
            $0.controlIdentity.lexicographicallyPrecedes(
                $1.controlIdentity
            )
        }
        guard normalized.map(\.controlIdentity)
                == context.controlIdentities,
              Set(normalized.map(\.controlIdentity)).count
                == normalized.count else {
            throw TransportBootstrapFailure.claimSetMismatch
        }
        guard Set(normalized.map(\.recipientEventIdentity)).count
                == normalized.count else {
            throw TransportBootstrapFailure.duplicateMailboxIdentity
        }
        let blindedMessages = normalized.compactMap(\.blindedMessage)
        guard blindedMessages.count
                == context.contributorControlIdentities.count,
              Set(blindedMessages).count == blindedMessages.count else {
            throw TransportBootstrapFailure.invalidBlindRequest
        }

        var encoder = OpalFusion.Mosaic.CanonicalEncoder()
        try encoder.writeText(TransportBootstrapContract.identifier)
        try encoder.writeFixedBytes(
            Array(context.roundIdentifier),
            byteCount: 32
        )
        try encoder.writeFixedBytes(
            Array(context.relaySetDigest),
            byteCount: 32
        )
        try encoder.writeFixedBytes(
            Array(authorizationKey.digest),
            byteCount: 32
        )
        try encoder.writeVector(normalized) { encoder, claim in
            try encoder.writeBytes(Array(claim.canonicalDocument))
        }
        let canonical = Data(encoder.encodedBytes)
        try TransportBootstrapContract.validateAggregateDocumentSize(
            canonical
        )
        return .init(
            claims: normalized,
            authorizationKeyDocumentDigest: authorizationKey.digest,
            digest: TransportBootstrapContract.hash(
                suffix: "control-mailbox-claim-set",
                body: canonical
            ),
            canonicalDocument: canonical
        )
    }
}
#endif

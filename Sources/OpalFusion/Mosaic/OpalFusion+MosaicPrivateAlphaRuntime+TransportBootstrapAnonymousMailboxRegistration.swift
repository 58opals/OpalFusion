// OpalFusion+MosaicPrivateAlphaRuntime+TransportBootstrapAnonymousMailboxRegistration.swift

#if os(macOS)
import Foundation
import OpalCrypto

extension OpalFusion.MosaicPrivateAlphaRuntime {
    /// One anonymous redemption of a contributor's blind authorization.
    @_spi(MosaicPrivateAlpha)
    public struct TransportBootstrapAnonymousMailboxRegistration:
        Sendable,
        Equatable
    {
        @_spi(MosaicPrivateAlpha) public let anonymousSenderEventIdentity: Data
        @_spi(MosaicPrivateAlpha) public let authorizationSpentIdentifier: Data
        @_spi(MosaicPrivateAlpha) public let digest: Data
        @_spi(MosaicPrivateAlpha) public let canonicalDocument: Data

        let token: TransportBootstrapAnonymousMailboxAuthorizationToken
        let signature: Data
        let authorizationKeyDocumentDigest: Data
        let claimSetDigest: Data
        let responseSetDigest: Data

        init(
            anonymousSenderEventIdentity: Data,
            authorizationSpentIdentifier: Data,
            digest: Data,
            canonicalDocument: Data,
            token: TransportBootstrapAnonymousMailboxAuthorizationToken,
            signature: Data,
            authorizationKeyDocumentDigest: Data,
            claimSetDigest: Data,
            responseSetDigest: Data
        ) {
            self.anonymousSenderEventIdentity =
                anonymousSenderEventIdentity
            self.authorizationSpentIdentifier =
                authorizationSpentIdentifier
            self.digest = digest
            self.canonicalDocument = canonicalDocument
            self.token = token
            self.signature = signature
            self.authorizationKeyDocumentDigest =
                authorizationKeyDocumentDigest
            self.claimSetDigest = claimSetDigest
            self.responseSetDigest = responseSetDigest
        }
    }

    @_spi(MosaicPrivateAlpha)
    public static func makeTransportBootstrapAnonymousMailboxRegistration(
        proof: PrivateDeploymentProof,
        authorizationKey: TransportBootstrapAuthorizationKeyDocument,
        claimSet: TransportBootstrapControlMailboxClaimSet,
        responseSet: TransportBootstrapBlindResponseSet,
        contributorControlIdentity: Data,
        request: TransportBootstrapAnonymousMailboxRequest,
        anonymousSenderSigningKey: OpalCrypto.Secp256k1.SigningKey,
        auxiliaryRandomness:
            OpalCrypto.Signature.BIP340.AuxiliaryRandomness
    ) throws -> TransportBootstrapAnonymousMailboxRegistration {
        let context = TransportBootstrapContract.Context(proof: proof)
        let documents = try validateTransportBootstrapRegistrationDocuments(
            proof: proof,
            authorizationKey: authorizationKey,
            claimSet: claimSet,
            responseSet: responseSet,
            currentUnixSeconds: context.phaseStartUnixSeconds
        )
        let token = try finalizeTransportBootstrapAnonymousMailboxRequest(
            request,
            contributorControlIdentity: contributorControlIdentity,
            authorizationKey: documents.authorizationKey,
            claimSet: documents.claimSet,
            responseSet: documents.responseSet
        )
        guard anonymousSenderSigningKey.bip340VerificationKey
                .rawRepresentation == request.anonymousSenderEventIdentity
        else {
            throw TransportBootstrapFailure.invalidSigner
        }
        try TransportBootstrapContract.validateEventIdentity(
            request.anonymousSenderEventIdentity,
            excluding: Set(context.preManifestEventIdentities).union(
                documents.claimSet.claims.map(\.recipientEventIdentity)
            )
        )

        var encoder = OpalFusion.Mosaic.CanonicalEncoder()
        try TransportBootstrapContract.writeCommon(
            to: &encoder,
            context: context,
            kind: .anonymousMailboxRegistration
        )
        try encoder.writeFixedBytes(
            Array(documents.authorizationKey.digest),
            byteCount: 32
        )
        try encoder.writeFixedBytes(
            Array(documents.claimSet.digest),
            byteCount: 32
        )
        try encoder.writeFixedBytes(
            Array(documents.responseSet.digest),
            byteCount: 32
        )
        try encoder.writeBytes(Array(token.input.canonicalDocument))
        try encoder.writeFixedBytes(
            Array(token.messageRandomizer.rawRepresentation),
            byteCount: 32
        )
        try encoder.writeFixedBytes(
            Array(token.signature.rawRepresentation),
            byteCount: 256
        )
        let body = Data(encoder.encodedBytes)
        let signature = try TransportBootstrapContract.sign(
            body: body,
            suffix: "anonymous-mailbox-registration",
            using: anonymousSenderSigningKey,
            auxiliaryRandomness: auxiliaryRandomness
        )
        var canonical = body
        canonical.append(signature)
        try TransportBootstrapContract.validateDocumentSize(canonical)
        return .init(
            anonymousSenderEventIdentity:
                token.input.anonymousSenderEventIdentity,
            authorizationSpentIdentifier: token.input.spentIdentifier,
            digest: TransportBootstrapContract.hash(
                suffix: "anonymous-mailbox-registration-document",
                body: canonical
            ),
            canonicalDocument: canonical,
            token: token,
            signature: signature,
            authorizationKeyDocumentDigest:
                documents.authorizationKey.digest,
            claimSetDigest: documents.claimSet.digest,
            responseSetDigest: documents.responseSet.digest
        )
    }

    @_spi(MosaicPrivateAlpha)
    public static func loadTransportBootstrapAnonymousMailboxRegistration(
        from canonicalDocument: Data,
        proof: PrivateDeploymentProof,
        authorizationKey: TransportBootstrapAuthorizationKeyDocument,
        claimSet: TransportBootstrapControlMailboxClaimSet,
        responseSet: TransportBootstrapBlindResponseSet,
        currentUnixSeconds: UInt64
    ) throws -> TransportBootstrapAnonymousMailboxRegistration {
        let context = TransportBootstrapContract.Context(proof: proof)
        let documents = try validateTransportBootstrapRegistrationDocuments(
            proof: proof,
            authorizationKey: authorizationKey,
            claimSet: claimSet,
            responseSet: responseSet,
            currentUnixSeconds: currentUnixSeconds
        )
        try TransportBootstrapContract.validateDocumentSize(canonicalDocument)
        let decoded: (
            body: Data,
            inputDocument: Data,
            messageRandomizer: Data,
            authorizationSignature: Data,
            signature: Data
        )
        do {
            decoded = try OpalFusion.Mosaic.CanonicalDecoder.decode(
                from: Array(canonicalDocument)
            ) { decoder in
                try TransportBootstrapContract.readCommon(
                    from: &decoder,
                    context: context,
                    expectedKind: .anonymousMailboxRegistration
                )
                let bodyByteCount = canonicalDocument.count - 64
                guard bodyByteCount > 0,
                      Data(try decoder.readFixedBytes(byteCount: 32))
                        == documents.authorizationKey.digest,
                      Data(try decoder.readFixedBytes(byteCount: 32))
                        == documents.claimSet.digest,
                      Data(try decoder.readFixedBytes(byteCount: 32))
                        == documents.responseSet.digest else {
                    throw TransportBootstrapFailure.invalidBinding
                }
                return (
                    canonicalDocument.prefix(bodyByteCount),
                    Data(try decoder.readBytes(maximumByteCount: 256)),
                    Data(try decoder.readFixedBytes(byteCount: 32)),
                    Data(try decoder.readFixedBytes(byteCount: 256)),
                    Data(try decoder.readFixedBytes(byteCount: 64))
                )
            }
        } catch let failure as TransportBootstrapFailure {
            throw failure
        } catch {
            throw TransportBootstrapFailure.invalidCanonicalDocument
        }
        let input = try loadTransportBootstrapAnonymousMailboxInput(
            decoded.inputDocument,
            context: context,
            authorizationKey: documents.authorizationKey
        )
        let token: TransportBootstrapAnonymousMailboxAuthorizationToken
        do {
            token = .init(
                input: input,
                messageRandomizer: try .init(
                    rawRepresentation: decoded.messageRandomizer
                ),
                signature: try .init(
                    rawRepresentation: decoded.authorizationSignature
                )
            )
        } catch {
            throw TransportBootstrapFailure.invalidBlindResponse
        }
        guard token.verify(using: documents.authorizationKey.verificationKey)
        else {
            throw TransportBootstrapFailure.invalidBlindResponse
        }
        try TransportBootstrapContract.validateEventIdentity(
            input.anonymousSenderEventIdentity,
            excluding: Set(context.preManifestEventIdentities).union(
                documents.claimSet.claims.map(\.recipientEventIdentity)
            )
        )
        try TransportBootstrapContract.verifySignature(
            decoded.signature,
            body: decoded.body,
            suffix: "anonymous-mailbox-registration",
            signerIdentity: input.anonymousSenderEventIdentity
        )
        try TransportBootstrapContract.validateCurrentTime(
            currentUnixSeconds,
            context: context
        )
        return .init(
            anonymousSenderEventIdentity:
                input.anonymousSenderEventIdentity,
            authorizationSpentIdentifier: input.spentIdentifier,
            digest: TransportBootstrapContract.hash(
                suffix: "anonymous-mailbox-registration-document",
                body: canonicalDocument
            ),
            canonicalDocument: canonicalDocument,
            token: token,
            signature: decoded.signature,
            authorizationKeyDocumentDigest:
                documents.authorizationKey.digest,
            claimSetDigest: documents.claimSet.digest,
            responseSetDigest: documents.responseSet.digest
        )
    }

    static func validateTransportBootstrapRegistrationDocuments(
        proof: PrivateDeploymentProof,
        authorizationKey: TransportBootstrapAuthorizationKeyDocument,
        claimSet: TransportBootstrapControlMailboxClaimSet,
        responseSet: TransportBootstrapBlindResponseSet,
        currentUnixSeconds: UInt64
    ) throws -> (
        authorizationKey: TransportBootstrapAuthorizationKeyDocument,
        claimSet: TransportBootstrapControlMailboxClaimSet,
        responseSet: TransportBootstrapBlindResponseSet
    ) {
        let key = try loadTransportBootstrapAuthorizationKeyDocument(
            from: authorizationKey.canonicalDocument,
            proof: proof,
            currentUnixSeconds: currentUnixSeconds
        )
        let claims = try loadTransportBootstrapControlMailboxClaimSet(
            from: claimSet.canonicalDocument,
            proof: proof,
            authorizationKey: key,
            currentUnixSeconds: currentUnixSeconds
        )
        let responses = try loadTransportBootstrapBlindResponseSet(
            from: responseSet.canonicalDocument,
            proof: proof,
            authorizationKey: key,
            claimSet: claims,
            currentUnixSeconds: currentUnixSeconds
        )
        return (key, claims, responses)
    }
}
#endif

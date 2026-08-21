// OpalFusion+MosaicPrivateAlphaRuntime+TransportBootstrapBlindResponseSet.swift

#if os(macOS)
import Foundation
import OpalCrypto

extension OpalFusion.MosaicPrivateAlphaRuntime {
    @_spi(MosaicPrivateAlpha)
    public struct TransportBootstrapBlindResponse: Sendable, Equatable {
        @_spi(MosaicPrivateAlpha) public let contributorControlIdentity: Data
        @_spi(MosaicPrivateAlpha) public let blindSignature: Data

        init(contributorControlIdentity: Data, blindSignature: Data) {
            self.contributorControlIdentity = contributorControlIdentity
            self.blindSignature = blindSignature
        }
    }

    @_spi(MosaicPrivateAlpha)
    public struct TransportBootstrapBlindResponseSet: Sendable, Equatable {
        @_spi(MosaicPrivateAlpha) public let claimSetDigest: Data
        @_spi(MosaicPrivateAlpha) public let responses:
            [TransportBootstrapBlindResponse]
        @_spi(MosaicPrivateAlpha) public let digest: Data
        @_spi(MosaicPrivateAlpha) public let canonicalDocument: Data

        let signature: Data

        init(
            claimSetDigest: Data,
            responses: [TransportBootstrapBlindResponse],
            digest: Data,
            canonicalDocument: Data,
            signature: Data
        ) {
            self.claimSetDigest = claimSetDigest
            self.responses = responses
            self.digest = digest
            self.canonicalDocument = canonicalDocument
            self.signature = signature
        }
    }

    struct TransportBootstrapAnonymousMailboxAuthorizationToken:
        Sendable,
        Equatable
    {
        let input: TransportBootstrapAnonymousMailboxAuthorizationInput
        let messageRandomizer: OpalCrypto.RSABSSA.MessageRandomizer
        let signature: OpalCrypto.RSABSSA.Signature

        var spentIdentifier: Data { input.spentIdentifier }

        func verify(
            using verificationKey: OpalCrypto.RSABSSA.VerificationKey
        ) -> Bool {
            input.authorizationKeyIdentifier
                == verificationKey.keyIdentifier
                && signature.verify(
                    message: input.canonicalDocument,
                    messageRandomizer: messageRandomizer,
                    using: verificationKey
                )
        }
    }

    @_spi(MosaicPrivateAlpha)
    public static func makeTransportBootstrapBlindResponseSet(
        proof: PrivateDeploymentProof,
        authorizationKey: TransportBootstrapAuthorizationKeyDocument,
        claimSet: TransportBootstrapControlMailboxClaimSet,
        authorizationSigningKey: OpalCrypto.RSABSSA.SigningKey,
        conductorControlSigningKey: OpalCrypto.Secp256k1.SigningKey,
        auxiliaryRandomness:
            OpalCrypto.Signature.BIP340.AuxiliaryRandomness
    ) throws -> TransportBootstrapBlindResponseSet {
        let context = TransportBootstrapContract.Context(proof: proof)
        let keyDocument = try makeTransportBootstrapAuthorizationKeyDocument(
            canonicalDocument: authorizationKey.canonicalDocument,
            context: context,
            currentUnixSeconds: nil
        )
        let claims = try makeTransportBootstrapControlMailboxClaimSet(
            context: context,
            authorizationKey: keyDocument,
            claims: claimSet.claims
        )
        guard authorizationSigningKey.verificationKey
                == keyDocument.verificationKey,
              conductorControlSigningKey.bip340VerificationKey
                .rawRepresentation == context.conductorControlIdentity else {
            throw TransportBootstrapFailure.invalidSigner
        }
        let responses = try claims.claims.compactMap { claim ->
            TransportBootstrapBlindResponse? in
            guard let blindedMessage = claim.blindedMessage else {
                return nil
            }
            let blindSignature = try authorizationSigningKey.blindSign(
                try .init(rawRepresentation: blindedMessage)
            ).rawRepresentation
            return .init(
                contributorControlIdentity: claim.controlIdentity,
                blindSignature: blindSignature
            )
        }
        return try makeTransportBootstrapBlindResponseSet(
            context: context,
            authorizationKey: keyDocument,
            claimSet: claims,
            responses: responses,
            conductorControlSigningKey: conductorControlSigningKey,
            auxiliaryRandomness: auxiliaryRandomness
        )
    }

    @_spi(MosaicPrivateAlpha)
    public static func loadTransportBootstrapBlindResponseSet(
        from canonicalDocument: Data,
        proof: PrivateDeploymentProof,
        authorizationKey: TransportBootstrapAuthorizationKeyDocument,
        claimSet: TransportBootstrapControlMailboxClaimSet,
        currentUnixSeconds: UInt64
    ) throws -> TransportBootstrapBlindResponseSet {
        let context = TransportBootstrapContract.Context(proof: proof)
        let keyDocument = try makeTransportBootstrapAuthorizationKeyDocument(
            canonicalDocument: authorizationKey.canonicalDocument,
            context: context,
            currentUnixSeconds: currentUnixSeconds
        )
        let claims = try makeTransportBootstrapControlMailboxClaimSet(
            context: context,
            authorizationKey: keyDocument,
            claims: claimSet.claims
        )
        try TransportBootstrapContract.validateDocumentSize(canonicalDocument)
        let decoded: (
            body: Data,
            responses: [TransportBootstrapBlindResponse],
            signature: Data
        )
        do {
            decoded = try OpalFusion.Mosaic.CanonicalDecoder.decode(
                from: Array(canonicalDocument)
            ) { decoder in
                try TransportBootstrapContract.readCommon(
                    from: &decoder,
                    context: context,
                    expectedKind: .blindResponseSet
                )
                let bodyByteCount = canonicalDocument.count - 64
                guard bodyByteCount > 0,
                      Data(try decoder.readFixedBytes(byteCount: 32))
                        == keyDocument.digest,
                      Data(try decoder.readFixedBytes(byteCount: 32))
                        == claims.digest else {
                    throw TransportBootstrapFailure.invalidBinding
                }
                let responses = try decoder.readVector(
                    maximumCount:
                        context.contributorControlIdentities.count
                ) { decoder in
                    TransportBootstrapBlindResponse(
                        contributorControlIdentity: Data(
                            try decoder.readFixedBytes(byteCount: 32)
                        ),
                        blindSignature: Data(
                            try decoder.readFixedBytes(byteCount: 256)
                        )
                    )
                }
                let signature = Data(
                    try decoder.readFixedBytes(byteCount: 64)
                )
                return (
                    canonicalDocument.prefix(bodyByteCount),
                    responses,
                    signature
                )
            }
        } catch let failure as TransportBootstrapFailure {
            throw failure
        } catch {
            throw TransportBootstrapFailure.invalidCanonicalDocument
        }
        let normalized = decoded.responses.sorted {
            $0.contributorControlIdentity.lexicographicallyPrecedes(
                $1.contributorControlIdentity
            )
        }
        guard normalized == decoded.responses,
              normalized.map(\.contributorControlIdentity)
                == context.contributorControlIdentities,
              Set(normalized.map(\.contributorControlIdentity)).count
                == normalized.count else {
            throw TransportBootstrapFailure.invalidBlindResponse
        }
        try TransportBootstrapContract.verifySignature(
            decoded.signature,
            body: decoded.body,
            suffix: "blind-response-set",
            signerIdentity: context.conductorControlIdentity
        )
        try TransportBootstrapContract.validateCurrentTime(
            currentUnixSeconds,
            context: context
        )
        return .init(
            claimSetDigest: claims.digest,
            responses: normalized,
            digest: TransportBootstrapContract.hash(
                suffix: "blind-response-set-document",
                body: canonicalDocument
            ),
            canonicalDocument: canonicalDocument,
            signature: decoded.signature
        )
    }

    static func finalizeTransportBootstrapAnonymousMailboxRequest(
        _ request: TransportBootstrapAnonymousMailboxRequest,
        contributorControlIdentity: Data,
        authorizationKey: TransportBootstrapAuthorizationKeyDocument,
        claimSet: TransportBootstrapControlMailboxClaimSet,
        responseSet: TransportBootstrapBlindResponseSet
    ) throws -> TransportBootstrapAnonymousMailboxAuthorizationToken {
        guard let claim = claimSet.claims.first(where: {
            $0.controlIdentity == contributorControlIdentity
        }),
        claim.blindedMessage == request.blindedMessage,
        claim.authorizationKeyDocumentDigest == authorizationKey.digest,
        responseSet.claimSetDigest == claimSet.digest,
        let response = responseSet.responses.first(where: {
            $0.contributorControlIdentity == contributorControlIdentity
        }) else {
            throw TransportBootstrapFailure.invalidBlindResponse
        }
        let token = TransportBootstrapAnonymousMailboxAuthorizationToken(
            input: request.input,
            messageRandomizer: request.blindRequest.messageRandomizer,
            signature: try request.blindRequest.finalize(
                try .init(rawRepresentation: response.blindSignature),
                using: authorizationKey.verificationKey
            )
        )
        // OpalCrypto finalization validates and unblinds the response, then
        // verifies the resulting RSA-PSS signature before it returns.
        return token
    }

    private static func makeTransportBootstrapBlindResponseSet(
        context: TransportBootstrapContract.Context,
        authorizationKey: TransportBootstrapAuthorizationKeyDocument,
        claimSet: TransportBootstrapControlMailboxClaimSet,
        responses: [TransportBootstrapBlindResponse],
        conductorControlSigningKey: OpalCrypto.Secp256k1.SigningKey,
        auxiliaryRandomness:
            OpalCrypto.Signature.BIP340.AuxiliaryRandomness
    ) throws -> TransportBootstrapBlindResponseSet {
        let normalized = responses.sorted {
            $0.contributorControlIdentity.lexicographicallyPrecedes(
                $1.contributorControlIdentity
            )
        }
        guard normalized.map(\.contributorControlIdentity)
                == context.contributorControlIdentities else {
            throw TransportBootstrapFailure.invalidBlindResponse
        }
        var encoder = OpalFusion.Mosaic.CanonicalEncoder()
        try TransportBootstrapContract.writeCommon(
            to: &encoder,
            context: context,
            kind: .blindResponseSet
        )
        try encoder.writeFixedBytes(Array(authorizationKey.digest), byteCount: 32)
        try encoder.writeFixedBytes(Array(claimSet.digest), byteCount: 32)
        try encoder.writeVector(normalized) { encoder, response in
            try encoder.writeFixedBytes(
                Array(response.contributorControlIdentity),
                byteCount: 32
            )
            try encoder.writeFixedBytes(
                Array(response.blindSignature),
                byteCount: 256
            )
        }
        let body = Data(encoder.encodedBytes)
        let signature = try TransportBootstrapContract.sign(
            body: body,
            suffix: "blind-response-set",
            using: conductorControlSigningKey,
            auxiliaryRandomness: auxiliaryRandomness
        )
        var canonical = body
        canonical.append(signature)
        try TransportBootstrapContract.validateDocumentSize(canonical)
        return .init(
            claimSetDigest: claimSet.digest,
            responses: normalized,
            digest: TransportBootstrapContract.hash(
                suffix: "blind-response-set-document",
                body: canonical
            ),
            canonicalDocument: canonical,
            signature: signature
        )
    }
}
#endif

// OpalFusion+MosaicPrivateAlphaRuntime+TransportBootstrapAuthorizationKeyDocument.swift

#if os(macOS)
import Foundation
import OpalCrypto

extension OpalFusion.MosaicPrivateAlphaRuntime {
    /// One conductor-signed, attempt-exclusive RFC 9474 authorization key.
    @_spi(MosaicPrivateAlpha)
    public struct TransportBootstrapAuthorizationKeyDocument:
        Sendable,
        Equatable
    {
        @_spi(MosaicPrivateAlpha) public let verificationKey:
            OpalCrypto.RSABSSA.VerificationKey
        @_spi(MosaicPrivateAlpha) public let digest: Data
        @_spi(MosaicPrivateAlpha) public let canonicalDocument: Data

        let signature: Data

        init(
            verificationKey: OpalCrypto.RSABSSA.VerificationKey,
            digest: Data,
            canonicalDocument: Data,
            signature: Data
        ) {
            self.verificationKey = verificationKey
            self.digest = digest
            self.canonicalDocument = canonicalDocument
            self.signature = signature
        }
    }

    @_spi(MosaicPrivateAlpha)
    public static func makeTransportBootstrapAuthorizationKeyDocument(
        proof: PrivateDeploymentProof,
        authorizationSigningKey: OpalCrypto.RSABSSA.SigningKey,
        conductorControlSigningKey: OpalCrypto.Secp256k1.SigningKey,
        auxiliaryRandomness:
            OpalCrypto.Signature.BIP340.AuxiliaryRandomness
    ) throws -> TransportBootstrapAuthorizationKeyDocument {
        let context = TransportBootstrapContract.Context(proof: proof)
        guard conductorControlSigningKey.bip340VerificationKey
                .rawRepresentation == context.conductorControlIdentity else {
            throw TransportBootstrapFailure.invalidSigner
        }
        var encoder = OpalFusion.Mosaic.CanonicalEncoder()
        try TransportBootstrapContract.writeCommon(
            to: &encoder,
            context: context,
            kind: .authorizationKey
        )
        try encoder.writeBytes(
            Array(authorizationSigningKey.verificationKey
                .subjectPublicKeyInfo)
        )
        let body = Data(encoder.encodedBytes)
        let signature = try TransportBootstrapContract.sign(
            body: body,
            suffix: "authorization-key",
            using: conductorControlSigningKey,
            auxiliaryRandomness: auxiliaryRandomness
        )
        var canonical = body
        canonical.append(signature)
        return try makeTransportBootstrapAuthorizationKeyDocument(
            canonicalDocument: canonical,
            context: context,
            currentUnixSeconds: nil
        )
    }

    @_spi(MosaicPrivateAlpha)
    public static func loadTransportBootstrapAuthorizationKeyDocument(
        from canonicalDocument: Data,
        proof: PrivateDeploymentProof,
        currentUnixSeconds: UInt64
    ) throws -> TransportBootstrapAuthorizationKeyDocument {
        try makeTransportBootstrapAuthorizationKeyDocument(
            canonicalDocument: canonicalDocument,
            context: .init(proof: proof),
            currentUnixSeconds: currentUnixSeconds
        )
    }

    static func makeTransportBootstrapAuthorizationKeyDocument(
        canonicalDocument: Data,
        context: TransportBootstrapContract.Context,
        currentUnixSeconds: UInt64?
    ) throws -> TransportBootstrapAuthorizationKeyDocument {
        try TransportBootstrapContract.validateDocumentSize(canonicalDocument)
        let decoded: (
            body: Data,
            verificationKey: OpalCrypto.RSABSSA.VerificationKey,
            signature: Data
        )
        do {
            decoded = try OpalFusion.Mosaic.CanonicalDecoder.decode(
                from: Array(canonicalDocument)
            ) { decoder in
                try TransportBootstrapContract.readCommon(
                    from: &decoder,
                    context: context,
                    expectedKind: .authorizationKey
                )
                let bodyByteCount = canonicalDocument.count - 64
                guard bodyByteCount > 0 else {
                    throw TransportBootstrapFailure
                        .invalidCanonicalDocument
                }
                let subjectPublicKeyInfo = Data(
                    try decoder.readBytes(maximumByteCount: 512)
                )
                let signature = Data(
                    try decoder.readFixedBytes(byteCount: 64)
                )
                return (
                    canonicalDocument.prefix(bodyByteCount),
                    try OpalCrypto.RSABSSA.VerificationKey(
                        subjectPublicKeyInfo: subjectPublicKeyInfo
                    ),
                    signature
                )
            }
        } catch let failure as TransportBootstrapFailure {
            throw failure
        } catch {
            throw TransportBootstrapFailure.invalidCanonicalDocument
        }
        try TransportBootstrapContract.verifySignature(
            decoded.signature,
            body: decoded.body,
            suffix: "authorization-key",
            signerIdentity: context.conductorControlIdentity
        )
        try TransportBootstrapContract.validateCurrentTime(
            currentUnixSeconds,
            context: context
        )
        return .init(
            verificationKey: decoded.verificationKey,
            digest: TransportBootstrapContract.hash(
                suffix: "authorization-key-document",
                body: canonicalDocument
            ),
            canonicalDocument: canonicalDocument,
            signature: decoded.signature
        )
    }
}
#endif

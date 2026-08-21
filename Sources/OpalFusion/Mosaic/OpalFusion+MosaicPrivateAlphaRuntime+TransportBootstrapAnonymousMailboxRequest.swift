// OpalFusion+MosaicPrivateAlphaRuntime+TransportBootstrapAnonymousMailboxRequest.swift

#if os(macOS)
import Foundation
import OpalCrypto

extension OpalFusion.MosaicPrivateAlphaRuntime {
    struct TransportBootstrapAnonymousMailboxAuthorizationInput:
        Sendable,
        Equatable
    {
        let authorizationKeyIdentifier: Data
        let nonce: Data
        let anonymousSenderEventIdentity: Data
        let canonicalDocument: Data
        let spentIdentifier: Data
    }

    /// Contributor-local state for one unlinkable anonymous registration request.
    @_spi(MosaicPrivateAlpha)
    public struct TransportBootstrapAnonymousMailboxRequest: Sendable {
        @_spi(MosaicPrivateAlpha) public let anonymousSenderEventIdentity: Data
        @_spi(MosaicPrivateAlpha) public let blindedMessage: Data
        @_spi(MosaicPrivateAlpha) public let recoveryState:
            OpalCrypto.RSABSSA.BlindRequest.RecoveryState

        let input: TransportBootstrapAnonymousMailboxAuthorizationInput
        let blindRequest: OpalCrypto.RSABSSA.BlindRequest

        init(
            anonymousSenderEventIdentity: Data,
            blindedMessage: Data,
            recoveryState:
                OpalCrypto.RSABSSA.BlindRequest.RecoveryState,
            input: TransportBootstrapAnonymousMailboxAuthorizationInput,
            blindRequest: OpalCrypto.RSABSSA.BlindRequest
        ) {
            self.anonymousSenderEventIdentity =
                anonymousSenderEventIdentity
            self.blindedMessage = blindedMessage
            self.recoveryState = recoveryState
            self.input = input
            self.blindRequest = blindRequest
        }
    }

    @_spi(MosaicPrivateAlpha)
    public static func makeTransportBootstrapAnonymousMailboxRequest(
        proof: PrivateDeploymentProof,
        authorizationKey: TransportBootstrapAuthorizationKeyDocument,
        authorizationNonce: Data,
        anonymousSenderPrivateKey: OpalCrypto.Secp256k1.PrivateKey
    ) throws -> TransportBootstrapAnonymousMailboxRequest {
        let context = TransportBootstrapContract.Context(proof: proof)
        let keyDocument = try makeTransportBootstrapAuthorizationKeyDocument(
            canonicalDocument: authorizationKey.canonicalDocument,
            context: context,
            currentUnixSeconds: nil
        )
        let input = try makeTransportBootstrapAnonymousMailboxInput(
            context: context,
            authorizationKey: keyDocument,
            authorizationNonce: authorizationNonce,
            anonymousSenderPrivateKey: anonymousSenderPrivateKey
        )
        let blindRequest = try OpalCrypto.RSABSSA.makeBlindRequest(
            message: input.canonicalDocument,
            using: keyDocument.verificationKey
        )
        return .init(
            anonymousSenderEventIdentity:
                input.anonymousSenderEventIdentity,
            blindedMessage: blindRequest.blindedMessage.rawRepresentation,
            recoveryState: blindRequest.recoveryState,
            input: input,
            blindRequest: blindRequest
        )
    }

    @_spi(MosaicPrivateAlpha)
    public static func restoreTransportBootstrapAnonymousMailboxRequest(
        proof: PrivateDeploymentProof,
        authorizationKey: TransportBootstrapAuthorizationKeyDocument,
        authorizationNonce: Data,
        anonymousSenderPrivateKey: OpalCrypto.Secp256k1.PrivateKey,
        recoveryState: OpalCrypto.RSABSSA.BlindRequest.RecoveryState,
        expectedBlindedMessage: Data
    ) throws -> TransportBootstrapAnonymousMailboxRequest {
        let context = TransportBootstrapContract.Context(proof: proof)
        let keyDocument = try makeTransportBootstrapAuthorizationKeyDocument(
            canonicalDocument: authorizationKey.canonicalDocument,
            context: context,
            currentUnixSeconds: nil
        )
        let input = try makeTransportBootstrapAnonymousMailboxInput(
            context: context,
            authorizationKey: keyDocument,
            authorizationNonce: authorizationNonce,
            anonymousSenderPrivateKey: anonymousSenderPrivateKey
        )
        let blindRequest = try OpalCrypto.RSABSSA.restoreBlindRequest(
            message: input.canonicalDocument,
            using: keyDocument.verificationKey,
            from: recoveryState
        )
        guard blindRequest.blindedMessage.rawRepresentation
                == expectedBlindedMessage else {
            throw TransportBootstrapFailure.invalidBinding
        }
        return .init(
            anonymousSenderEventIdentity:
                input.anonymousSenderEventIdentity,
            blindedMessage: expectedBlindedMessage,
            recoveryState: blindRequest.recoveryState,
            input: input,
            blindRequest: blindRequest
        )
    }

    static func loadTransportBootstrapAnonymousMailboxInput(
        _ canonicalDocument: Data,
        context: TransportBootstrapContract.Context,
        authorizationKey: TransportBootstrapAuthorizationKeyDocument
    ) throws -> TransportBootstrapAnonymousMailboxAuthorizationInput {
        do {
            return try OpalFusion.Mosaic.CanonicalDecoder.decode(
                from: Array(canonicalDocument)
            ) { decoder in
                guard try decoder.readText()
                        == TransportBootstrapContract.identifier,
                      Data(try decoder.readFixedBytes(byteCount: 32))
                        == context.roundIdentifier,
                      Data(try decoder.readFixedBytes(byteCount: 32))
                        == context.relaySetDigest,
                      Data(try decoder.readFixedBytes(byteCount: 32))
                        == authorizationKey.verificationKey.keyIdentifier
                else {
                    throw TransportBootstrapFailure.invalidBlindRequest
                }
                let nonce = Data(
                    try decoder.readFixedBytes(byteCount: 32)
                )
                let senderIdentity = Data(
                    try decoder.readFixedBytes(byteCount: 32)
                )
                try TransportBootstrapContract.validateEventIdentity(
                    senderIdentity,
                    excluding: Set(context.preManifestEventIdentities)
                )
                return .init(
                    authorizationKeyIdentifier:
                        authorizationKey.verificationKey.keyIdentifier,
                    nonce: nonce,
                    anonymousSenderEventIdentity: senderIdentity,
                    canonicalDocument: canonicalDocument,
                    spentIdentifier: TransportBootstrapContract.hash(
                        suffix: "anonymous-mailbox-authorization-spent",
                        body: canonicalDocument
                    )
                )
            }
        } catch let failure as TransportBootstrapFailure {
            throw failure
        } catch {
            throw TransportBootstrapFailure.invalidBlindRequest
        }
    }

    private static func makeTransportBootstrapAnonymousMailboxInput(
        context: TransportBootstrapContract.Context,
        authorizationKey: TransportBootstrapAuthorizationKeyDocument,
        authorizationNonce: Data,
        anonymousSenderPrivateKey: OpalCrypto.Secp256k1.PrivateKey
    ) throws -> TransportBootstrapAnonymousMailboxAuthorizationInput {
        guard authorizationNonce.count == 32 else {
            throw TransportBootstrapFailure.invalidBlindRequest
        }
        let senderIdentity = anonymousSenderPrivateKey.makeSigningKey()
            .bip340VerificationKey.rawRepresentation
        try TransportBootstrapContract.validateEventIdentity(
            senderIdentity,
            excluding: Set(context.preManifestEventIdentities)
        )
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
            Array(authorizationKey.verificationKey.keyIdentifier),
            byteCount: 32
        )
        try encoder.writeFixedBytes(
            Array(authorizationNonce),
            byteCount: 32
        )
        try encoder.writeFixedBytes(Array(senderIdentity), byteCount: 32)
        let canonical = Data(encoder.encodedBytes)
        return .init(
            authorizationKeyIdentifier:
                authorizationKey.verificationKey.keyIdentifier,
            nonce: authorizationNonce,
            anonymousSenderEventIdentity: senderIdentity,
            canonicalDocument: canonical,
            spentIdentifier: TransportBootstrapContract.hash(
                suffix: "anonymous-mailbox-authorization-spent",
                body: canonical
            )
        )
    }
}
#endif

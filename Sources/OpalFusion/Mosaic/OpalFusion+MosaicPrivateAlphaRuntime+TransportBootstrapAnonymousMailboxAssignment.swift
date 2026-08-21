// OpalFusion+MosaicPrivateAlphaRuntime+TransportBootstrapAnonymousMailboxAssignment.swift

#if os(macOS)
import Foundation
import OpalCrypto

extension OpalFusion.MosaicPrivateAlphaRuntime {
    /// One conductor-signed public-key bundle addressed to an anonymous return identity.
    @_spi(MosaicPrivateAlpha)
    public struct TransportBootstrapAnonymousMailboxAssignment:
        Sendable,
        Equatable
    {
        @_spi(MosaicPrivateAlpha) public let registrationDigest: Data
        @_spi(MosaicPrivateAlpha) public let anonymousRecipientEventIdentity:
            Data
        @_spi(MosaicPrivateAlpha) public let mailboxBundleCommitment: Data
        @_spi(MosaicPrivateAlpha) public let recipientEventIdentities: [Data]
        @_spi(MosaicPrivateAlpha) public let digest: Data
        @_spi(MosaicPrivateAlpha) public let canonicalDocument: Data

        let signature: Data
        let roundIdentifier: Data
        let relaySetDigest: Data

        init(
            registrationDigest: Data,
            anonymousRecipientEventIdentity: Data,
            mailboxBundleCommitment: Data,
            recipientEventIdentities: [Data],
            digest: Data,
            canonicalDocument: Data,
            signature: Data,
            roundIdentifier: Data,
            relaySetDigest: Data
        ) {
            self.registrationDigest = registrationDigest
            self.anonymousRecipientEventIdentity =
                anonymousRecipientEventIdentity
            self.mailboxBundleCommitment = mailboxBundleCommitment
            self.recipientEventIdentities = recipientEventIdentities
            self.digest = digest
            self.canonicalDocument = canonicalDocument
            self.signature = signature
            self.roundIdentifier = roundIdentifier
            self.relaySetDigest = relaySetDigest
        }
    }

    /// Conductor-local assignment retaining the corresponding recipient capabilities.
    @_spi(MosaicPrivateAlpha)
    public struct TransportBootstrapConductorMailboxAssignment: Sendable {
        @_spi(MosaicPrivateAlpha) public let assignment:
            TransportBootstrapAnonymousMailboxAssignment
        @_spi(MosaicPrivateAlpha) public let recipientSigningKeys:
            [OpalCrypto.Secp256k1.SigningKey]

        init(
            assignment: TransportBootstrapAnonymousMailboxAssignment,
            recipientSigningKeys: [OpalCrypto.Secp256k1.SigningKey]
        ) {
            self.assignment = assignment
            self.recipientSigningKeys = recipientSigningKeys
        }
    }

    @_spi(MosaicPrivateAlpha)
    public static func makeTransportBootstrapAnonymousMailboxAssignment(
        proof: PrivateDeploymentProof,
        authorizationKey: TransportBootstrapAuthorizationKeyDocument,
        claimSet: TransportBootstrapControlMailboxClaimSet,
        responseSet: TransportBootstrapBlindResponseSet,
        registration: TransportBootstrapAnonymousMailboxRegistration,
        recipientPrivateKeys: [OpalCrypto.Secp256k1.PrivateKey],
        conductorControlSigningKey: OpalCrypto.Secp256k1.SigningKey,
        auxiliaryRandomness:
            OpalCrypto.Signature.BIP340.AuxiliaryRandomness,
        currentUnixSeconds: UInt64
    ) throws -> TransportBootstrapConductorMailboxAssignment {
        let context = TransportBootstrapContract.Context(proof: proof)
        guard conductorControlSigningKey.bip340VerificationKey
                .rawRepresentation == context.conductorControlIdentity,
              recipientPrivateKeys.count
                == TransportBootstrapContract.anonymousMailboxCount else {
            throw TransportBootstrapFailure.invalidSigner
        }
        _ = try validateTransportBootstrapRegistrationDocuments(
            proof: proof,
            authorizationKey: authorizationKey,
            claimSet: claimSet,
            responseSet: responseSet,
            currentUnixSeconds: currentUnixSeconds
        )
        guard registration.authorizationKeyDocumentDigest
                == authorizationKey.digest,
              registration.claimSetDigest == claimSet.digest,
              registration.responseSetDigest == responseSet.digest else {
            throw TransportBootstrapFailure.invalidBinding
        }
        let recipientIdentities = recipientPrivateKeys.map {
            $0.makeSigningKey().bip340VerificationKey.rawRepresentation
        }
        try validateTransportBootstrapAssignmentIdentities(
            recipientIdentities,
            registration: registration,
            context: context,
            claimSet: claimSet
        )
        let commitment = try TransportBootstrapContract
            .mailboxBundleCommitment(
                recipientEventIdentities: recipientIdentities
            )
        var encoder = OpalFusion.Mosaic.CanonicalEncoder()
        try TransportBootstrapContract.writeCommon(
            to: &encoder,
            context: context,
            kind: .anonymousMailboxAssignment
        )
        try encoder.writeFixedBytes(
            Array(registration.digest),
            byteCount: 32
        )
        try encoder.writeFixedBytes(
            Array(registration.anonymousSenderEventIdentity),
            byteCount: 32
        )
        try encoder.writeFixedBytes(Array(commitment), byteCount: 32)
        try encoder.writeVector(recipientIdentities) { encoder, identity in
            try encoder.writeFixedBytes(Array(identity), byteCount: 32)
        }
        let body = Data(encoder.encodedBytes)
        let signature = try TransportBootstrapContract.sign(
            body: body,
            suffix: "anonymous-mailbox-assignment",
            using: conductorControlSigningKey,
            auxiliaryRandomness: auxiliaryRandomness
        )
        var canonical = body
        canonical.append(signature)
        try TransportBootstrapContract.validateDocumentSize(canonical)
        let assignment = TransportBootstrapAnonymousMailboxAssignment(
            registrationDigest: registration.digest,
            anonymousRecipientEventIdentity:
                registration.anonymousSenderEventIdentity,
            mailboxBundleCommitment: commitment,
            recipientEventIdentities: recipientIdentities,
            digest: TransportBootstrapContract.hash(
                suffix: "anonymous-mailbox-assignment-document",
                body: canonical
            ),
            canonicalDocument: canonical,
            signature: signature,
            roundIdentifier: context.roundIdentifier,
            relaySetDigest: context.relaySetDigest
        )
        return .init(
            assignment: assignment,
            recipientSigningKeys: recipientPrivateKeys.map {
                $0.makeSigningKey()
            }
        )
    }

    @_spi(MosaicPrivateAlpha)
    public static func loadTransportBootstrapAnonymousMailboxAssignment(
        from canonicalDocument: Data,
        proof: PrivateDeploymentProof,
        authorizationKey: TransportBootstrapAuthorizationKeyDocument,
        claimSet: TransportBootstrapControlMailboxClaimSet,
        responseSet: TransportBootstrapBlindResponseSet,
        registration: TransportBootstrapAnonymousMailboxRegistration,
        currentUnixSeconds: UInt64
    ) throws -> TransportBootstrapAnonymousMailboxAssignment {
        let context = TransportBootstrapContract.Context(proof: proof)
        let validatedRegistration = try loadTransportBootstrapAnonymousMailboxRegistration(
            from: registration.canonicalDocument,
            proof: proof,
            authorizationKey: authorizationKey,
            claimSet: claimSet,
            responseSet: responseSet,
            currentUnixSeconds: currentUnixSeconds
        )
        try TransportBootstrapContract.validateDocumentSize(canonicalDocument)
        let decoded: (
            body: Data,
            registrationDigest: Data,
            anonymousRecipient: Data,
            commitment: Data,
            recipients: [Data],
            signature: Data
        )
        do {
            decoded = try OpalFusion.Mosaic.CanonicalDecoder.decode(
                from: Array(canonicalDocument)
            ) { decoder in
                try TransportBootstrapContract.readCommon(
                    from: &decoder,
                    context: context,
                    expectedKind: .anonymousMailboxAssignment
                )
                let bodyByteCount = canonicalDocument.count - 64
                guard bodyByteCount > 0 else {
                    throw TransportBootstrapFailure
                        .invalidCanonicalDocument
                }
                return (
                    canonicalDocument.prefix(bodyByteCount),
                    Data(try decoder.readFixedBytes(byteCount: 32)),
                    Data(try decoder.readFixedBytes(byteCount: 32)),
                    Data(try decoder.readFixedBytes(byteCount: 32)),
                    try decoder.readVector(
                        maximumCount:
                            TransportBootstrapContract.anonymousMailboxCount
                    ) { decoder in
                        Data(try decoder.readFixedBytes(byteCount: 32))
                    },
                    Data(try decoder.readFixedBytes(byteCount: 64))
                )
            }
        } catch let failure as TransportBootstrapFailure {
            throw failure
        } catch {
            throw TransportBootstrapFailure.invalidCanonicalDocument
        }
        guard decoded.registrationDigest == validatedRegistration.digest,
              decoded.anonymousRecipient
                == validatedRegistration.anonymousSenderEventIdentity,
              decoded.recipients.count
                == TransportBootstrapContract.anonymousMailboxCount,
              try TransportBootstrapContract.mailboxBundleCommitment(
                  recipientEventIdentities: decoded.recipients
              ) == decoded.commitment else {
            throw TransportBootstrapFailure.invalidBinding
        }
        try validateTransportBootstrapAssignmentIdentities(
            decoded.recipients,
            registration: validatedRegistration,
            context: context,
            claimSet: claimSet
        )
        try TransportBootstrapContract.verifySignature(
            decoded.signature,
            body: decoded.body,
            suffix: "anonymous-mailbox-assignment",
            signerIdentity: context.conductorControlIdentity
        )
        try TransportBootstrapContract.validateCurrentTime(
            currentUnixSeconds,
            context: context
        )
        return .init(
            registrationDigest: decoded.registrationDigest,
            anonymousRecipientEventIdentity:
                decoded.anonymousRecipient,
            mailboxBundleCommitment: decoded.commitment,
            recipientEventIdentities: decoded.recipients,
            digest: TransportBootstrapContract.hash(
                suffix: "anonymous-mailbox-assignment-document",
                body: canonicalDocument
            ),
            canonicalDocument: canonicalDocument,
            signature: decoded.signature,
            roundIdentifier: context.roundIdentifier,
            relaySetDigest: context.relaySetDigest
        )
    }

    @_spi(MosaicPrivateAlpha)
    public static func restoreTransportBootstrapConductorMailboxAssignment(
        from canonicalDocument: Data,
        proof: PrivateDeploymentProof,
        authorizationKey: TransportBootstrapAuthorizationKeyDocument,
        claimSet: TransportBootstrapControlMailboxClaimSet,
        responseSet: TransportBootstrapBlindResponseSet,
        registration: TransportBootstrapAnonymousMailboxRegistration,
        recipientPrivateKeys: [OpalCrypto.Secp256k1.PrivateKey],
        currentUnixSeconds: UInt64
    ) throws -> TransportBootstrapConductorMailboxAssignment {
        let assignment = try loadTransportBootstrapAnonymousMailboxAssignment(
            from: canonicalDocument,
            proof: proof,
            authorizationKey: authorizationKey,
            claimSet: claimSet,
            responseSet: responseSet,
            registration: registration,
            currentUnixSeconds: currentUnixSeconds
        )
        let signingKeys = recipientPrivateKeys.map { $0.makeSigningKey() }
        guard signingKeys.map({
            $0.bip340VerificationKey.rawRepresentation
        }) == assignment.recipientEventIdentities else {
            throw TransportBootstrapFailure.invalidKeyBundle
        }
        return .init(
            assignment: assignment,
            recipientSigningKeys: signingKeys
        )
    }

    static func validateTransportBootstrapAssignmentIdentities(
        _ recipientIdentities: [Data],
        registration: TransportBootstrapAnonymousMailboxRegistration,
        context: TransportBootstrapContract.Context,
        claimSet: TransportBootstrapControlMailboxClaimSet
    ) throws {
        guard recipientIdentities.count
                == TransportBootstrapContract.anonymousMailboxCount,
              Set(recipientIdentities).count == recipientIdentities.count
        else {
            throw TransportBootstrapFailure.invalidAnonymousMailboxCount
        }
        let unavailable = Set(context.preManifestEventIdentities)
            .union(claimSet.claims.map(\.recipientEventIdentity))
            .union([registration.anonymousSenderEventIdentity])
        for identity in recipientIdentities {
            try TransportBootstrapContract.validateEventIdentity(
                identity,
                excluding: unavailable
            )
        }
    }
}
#endif

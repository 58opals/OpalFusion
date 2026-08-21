// OpalFusion+MosaicPrivateAlphaRuntime+TransportBootstrapAnonymousMailboxRegistrationSet.swift

#if os(macOS)
import Foundation
import OpalCrypto

extension OpalFusion.MosaicPrivateAlphaRuntime {
    /// The conductor-signed, unlabeled set of all anonymous mailbox-bundle commitments.
    @_spi(MosaicPrivateAlpha)
    public struct TransportBootstrapAnonymousMailboxRegistrationSet:
        Sendable,
        Equatable
    {
        @_spi(MosaicPrivateAlpha) public let mailboxBundleCommitments: [Data]
        @_spi(MosaicPrivateAlpha) public let digest: Data
        @_spi(MosaicPrivateAlpha) public let canonicalDocument: Data

        let signature: Data

        init(
            mailboxBundleCommitments: [Data],
            digest: Data,
            canonicalDocument: Data,
            signature: Data
        ) {
            self.mailboxBundleCommitments = mailboxBundleCommitments
            self.digest = digest
            self.canonicalDocument = canonicalDocument
            self.signature = signature
        }
    }

    @_spi(MosaicPrivateAlpha)
    public static func makeTransportBootstrapAnonymousMailboxRegistrationSet(
        proof: PrivateDeploymentProof,
        authorizationKey: TransportBootstrapAuthorizationKeyDocument,
        claimSet: TransportBootstrapControlMailboxClaimSet,
        responseSet: TransportBootstrapBlindResponseSet,
        registrations: [TransportBootstrapAnonymousMailboxRegistration],
        conductorAssignments: [TransportBootstrapConductorMailboxAssignment],
        conductorControlSigningKey: OpalCrypto.Secp256k1.SigningKey,
        auxiliaryRandomness:
            OpalCrypto.Signature.BIP340.AuxiliaryRandomness,
        currentUnixSeconds: UInt64
    ) throws -> TransportBootstrapAnonymousMailboxRegistrationSet {
        let context = TransportBootstrapContract.Context(proof: proof)
        guard conductorControlSigningKey.bip340VerificationKey
                .rawRepresentation == context.conductorControlIdentity else {
            throw TransportBootstrapFailure.invalidSigner
        }
        let validated = try validateTransportBootstrapRegistrationBacking(
            proof: proof,
            authorizationKey: authorizationKey,
            claimSet: claimSet,
            responseSet: responseSet,
            registrations: registrations,
            conductorAssignments: conductorAssignments,
            currentUnixSeconds: currentUnixSeconds
        )
        var encoder = OpalFusion.Mosaic.CanonicalEncoder()
        try TransportBootstrapContract.writeCommon(
            to: &encoder,
            context: context,
            kind: .anonymousMailboxRegistrationSet
        )
        try encoder.writeFixedBytes(
            Array(authorizationKey.digest),
            byteCount: 32
        )
        try encoder.writeFixedBytes(Array(claimSet.digest), byteCount: 32)
        try encoder.writeFixedBytes(Array(responseSet.digest), byteCount: 32)
        try encoder.writeVector(validated.commitments) { encoder, value in
            try encoder.writeFixedBytes(Array(value), byteCount: 32)
        }
        let body = Data(encoder.encodedBytes)
        let signature = try TransportBootstrapContract.sign(
            body: body,
            suffix: "anonymous-mailbox-registration-set",
            using: conductorControlSigningKey,
            auxiliaryRandomness: auxiliaryRandomness
        )
        var canonical = body
        canonical.append(signature)
        return try loadTransportBootstrapAnonymousMailboxRegistrationSet(
            from: canonical,
            proof: proof,
            authorizationKey: authorizationKey,
            claimSet: claimSet,
            responseSet: responseSet,
            currentUnixSeconds: currentUnixSeconds
        )
    }

    @_spi(MosaicPrivateAlpha)
    public static func loadTransportBootstrapAnonymousMailboxRegistrationSet(
        from canonicalDocument: Data,
        proof: PrivateDeploymentProof,
        authorizationKey: TransportBootstrapAuthorizationKeyDocument,
        claimSet: TransportBootstrapControlMailboxClaimSet,
        responseSet: TransportBootstrapBlindResponseSet,
        currentUnixSeconds: UInt64
    ) throws -> TransportBootstrapAnonymousMailboxRegistrationSet {
        let context = TransportBootstrapContract.Context(proof: proof)
        _ = try validateTransportBootstrapRegistrationDocuments(
            proof: proof,
            authorizationKey: authorizationKey,
            claimSet: claimSet,
            responseSet: responseSet,
            currentUnixSeconds: currentUnixSeconds
        )
        try TransportBootstrapContract.validateDocumentSize(canonicalDocument)
        let decoded: (
            body: Data,
            commitments: [Data],
            signature: Data
        )
        do {
            decoded = try OpalFusion.Mosaic.CanonicalDecoder.decode(
                from: Array(canonicalDocument)
            ) { decoder in
                try TransportBootstrapContract.readCommon(
                    from: &decoder,
                    context: context,
                    expectedKind: .anonymousMailboxRegistrationSet
                )
                let bodyByteCount = canonicalDocument.count - 64
                guard bodyByteCount > 0,
                      Data(try decoder.readFixedBytes(byteCount: 32))
                        == authorizationKey.digest,
                      Data(try decoder.readFixedBytes(byteCount: 32))
                        == claimSet.digest,
                      Data(try decoder.readFixedBytes(byteCount: 32))
                        == responseSet.digest else {
                    throw TransportBootstrapFailure.invalidBinding
                }
                return (
                    canonicalDocument.prefix(bodyByteCount),
                    try decoder.readVector(
                        maximumCount:
                            context.contributorControlIdentities.count
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
        let normalized = decoded.commitments.sorted {
            $0.lexicographicallyPrecedes($1)
        }
        guard decoded.commitments.count
                == context.contributorControlIdentities.count,
              decoded.commitments == normalized,
              Set(decoded.commitments).count == decoded.commitments.count
        else {
            throw TransportBootstrapFailure.invalidRegistrationSet
        }
        try TransportBootstrapContract.verifySignature(
            decoded.signature,
            body: decoded.body,
            suffix: "anonymous-mailbox-registration-set",
            signerIdentity: context.conductorControlIdentity
        )
        try TransportBootstrapContract.validateCurrentTime(
            currentUnixSeconds,
            context: context
        )
        return .init(
            mailboxBundleCommitments: decoded.commitments,
            digest: TransportBootstrapContract.hash(
                suffix: "anonymous-mailbox-registration-set-document",
                body: canonicalDocument
            ),
            canonicalDocument: canonicalDocument,
            signature: decoded.signature
        )
    }

    static func validateTransportBootstrapRegistrationBacking(
        proof: PrivateDeploymentProof,
        authorizationKey: TransportBootstrapAuthorizationKeyDocument,
        claimSet: TransportBootstrapControlMailboxClaimSet,
        responseSet: TransportBootstrapBlindResponseSet,
        registrations: [TransportBootstrapAnonymousMailboxRegistration],
        conductorAssignments: [TransportBootstrapConductorMailboxAssignment],
        currentUnixSeconds: UInt64
    ) throws -> (
        registrations: [TransportBootstrapAnonymousMailboxRegistration],
        assignments: [TransportBootstrapConductorMailboxAssignment],
        commitments: [Data]
    ) {
        let context = TransportBootstrapContract.Context(proof: proof)
        guard registrations.count
                == context.contributorControlIdentities.count,
              conductorAssignments.count == registrations.count else {
            throw TransportBootstrapFailure.invalidRegistrationSet
        }
        _ = try validateTransportBootstrapRegistrationDocuments(
            proof: proof,
            authorizationKey: authorizationKey,
            claimSet: claimSet,
            responseSet: responseSet,
            currentUnixSeconds: currentUnixSeconds
        )
        let validatedRegistrations = registrations
        guard validatedRegistrations.allSatisfy({ registration in
            registration.authorizationKeyDocumentDigest
                == authorizationKey.digest
                && registration.claimSetDigest == claimSet.digest
                && registration.responseSetDigest == responseSet.digest
        }) else {
            throw TransportBootstrapFailure.invalidBinding
        }
        guard Set(validatedRegistrations.map(\.digest)).count
                == validatedRegistrations.count,
              Set(validatedRegistrations.map(
                \.authorizationSpentIdentifier
              )).count == validatedRegistrations.count,
              Set(validatedRegistrations.map(
                \.anonymousSenderEventIdentity
              )).count == validatedRegistrations.count else {
            throw TransportBootstrapFailure.invalidRegistrationSet
        }
        let registrationByDigest = Dictionary(
            uniqueKeysWithValues: validatedRegistrations.map {
                ($0.digest, $0)
            }
        )
        let anonymousSenders = Set(validatedRegistrations.map(
            \.anonymousSenderEventIdentity
        ))
        var allRecipients = Set<Data>()
        var commitments: [Data] = []
        for conductorAssignment in conductorAssignments {
            let assignment = conductorAssignment.assignment
            guard let registration = registrationByDigest[
                assignment.registrationDigest
            ],
            assignment.anonymousRecipientEventIdentity
                == registration.anonymousSenderEventIdentity,
            conductorAssignment.recipientSigningKeys.map({
                $0.bip340VerificationKey.rawRepresentation
            }) == assignment.recipientEventIdentities else {
                throw TransportBootstrapFailure.invalidRegistrationSet
            }
            for recipient in assignment.recipientEventIdentities {
                guard !anonymousSenders.contains(recipient),
                      allRecipients.insert(recipient).inserted else {
                    throw TransportBootstrapFailure
                        .duplicateMailboxIdentity
                }
            }
            commitments.append(assignment.mailboxBundleCommitment)
        }
        guard Set(conductorAssignments.map {
            $0.assignment.registrationDigest
        }).count == validatedRegistrations.count else {
            throw TransportBootstrapFailure.invalidRegistrationSet
        }
        commitments.sort { $0.lexicographicallyPrecedes($1) }
        guard Set(commitments).count == commitments.count else {
            throw TransportBootstrapFailure.invalidRegistrationSet
        }
        return (
            validatedRegistrations,
            conductorAssignments,
            commitments
        )
    }
}
#endif

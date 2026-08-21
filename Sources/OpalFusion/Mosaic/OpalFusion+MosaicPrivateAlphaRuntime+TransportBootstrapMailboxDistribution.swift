// OpalFusion+MosaicPrivateAlphaRuntime+TransportBootstrapMailboxDistribution.swift

#if os(macOS)
import Foundation
import OpalCrypto

extension OpalFusion.MosaicPrivateAlphaRuntime {
    /// Package-minted proof that live mailbox capabilities came from signed bootstrap state.
    @_spi(MosaicPrivateAlpha)
    public struct TransportBootstrapMailboxDistribution: Sendable {
        @_spi(MosaicPrivateAlpha) public let mailboxCapabilities:
            PostManifestMailboxCapabilities
        @_spi(MosaicPrivateAlpha) public let controlClaimSetDigest: Data
        @_spi(MosaicPrivateAlpha) public let registrationSetDigest: Data
        @_spi(MosaicPrivateAlpha) public let acknowledgementSetDigest: Data
        @_spi(MosaicPrivateAlpha) public let authenticatedDocuments: [Data]

        init(
            mailboxCapabilities: PostManifestMailboxCapabilities,
            controlClaimSetDigest: Data,
            registrationSetDigest: Data,
            acknowledgementSetDigest: Data,
            authenticatedDocuments: [Data]
        ) {
            self.mailboxCapabilities = mailboxCapabilities
            self.controlClaimSetDigest = controlClaimSetDigest
            self.registrationSetDigest = registrationSetDigest
            self.acknowledgementSetDigest = acknowledgementSetDigest
            self.authenticatedDocuments = authenticatedDocuments
        }
    }

    @_spi(MosaicPrivateAlpha)
    public static func makeContributorTransportBootstrapMailboxDistribution(
        proof: PrivateDeploymentProof,
        authorizationKey: TransportBootstrapAuthorizationKeyDocument,
        claimSet: TransportBootstrapControlMailboxClaimSet,
        responseSet: TransportBootstrapBlindResponseSet,
        registration: TransportBootstrapAnonymousMailboxRegistration,
        assignment: TransportBootstrapAnonymousMailboxAssignment,
        registrationSet: TransportBootstrapAnonymousMailboxRegistrationSet,
        acknowledgementSet:
            TransportBootstrapRegistrationSetAcknowledgementSet,
        contributorControlIdentity: Data,
        localControlRecipientSigningKey:
            OpalCrypto.Secp256k1.SigningKey,
        currentUnixSeconds: UInt64
    ) throws -> TransportBootstrapMailboxDistribution {
        let context = TransportBootstrapContract.Context(proof: proof)
        guard context.contributorControlIdentities.contains(
                  contributorControlIdentity
              ) else {
            throw TransportBootstrapFailure.invalidSigner
        }
        let documents = try validateTransportBootstrapRegistrationDocuments(
            proof: proof,
            authorizationKey: authorizationKey,
            claimSet: claimSet,
            responseSet: responseSet,
            currentUnixSeconds: currentUnixSeconds
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
        let validatedSet = try loadTransportBootstrapAnonymousMailboxRegistrationSet(
            from: registrationSet.canonicalDocument,
            proof: proof,
            authorizationKey: documents.authorizationKey,
            claimSet: documents.claimSet,
            responseSet: documents.responseSet,
            currentUnixSeconds: currentUnixSeconds
        )
        guard validatedSet.mailboxBundleCommitments.contains(
            assignment.mailboxBundleCommitment
        ) else {
            throw TransportBootstrapFailure.invalidRegistrationSet
        }
        let acknowledgements = try loadTransportBootstrapRegistrationSetAcknowledgementSet(
            from: acknowledgementSet.canonicalDocument,
            proof: proof,
            authorizationKey: documents.authorizationKey,
            claimSet: documents.claimSet,
            responseSet: documents.responseSet,
            registrationSet: validatedSet,
            currentUnixSeconds: currentUnixSeconds
        )
        let controlMailboxes = try makeTransportBootstrapControlMailboxes(
            documents.claimSet
        )
        try validateTransportBootstrapLocalControlRecipient(
            localControlRecipientSigningKey,
            controlIdentity: contributorControlIdentity,
            claimSet: documents.claimSet
        )
        let anonymousKeys = try assignment
            .recipientEventIdentities.map {
                try OpalCrypto.Signature.BIP340.VerificationKey(
                    rawRepresentation: $0
                )
            }
        return .init(
            mailboxCapabilities: .init(
                controlMailboxes: controlMailboxes,
                localControlRecipientSigningKey:
                    localControlRecipientSigningKey,
                anonymous: .contributor(anonymousKeys)
            ),
            controlClaimSetDigest: documents.claimSet.digest,
            registrationSetDigest: validatedSet.digest,
            acknowledgementSetDigest: acknowledgements.digest,
            authenticatedDocuments: [
                documents.authorizationKey.canonicalDocument,
                documents.claimSet.canonicalDocument,
                documents.responseSet.canonicalDocument,
                registration.canonicalDocument,
                assignment.canonicalDocument,
                validatedSet.canonicalDocument,
                acknowledgements.canonicalDocument,
            ]
        )
    }

    @_spi(MosaicPrivateAlpha)
    public static func makeConductorTransportBootstrapMailboxDistribution(
        proof: PrivateDeploymentProof,
        authorizationKey: TransportBootstrapAuthorizationKeyDocument,
        claimSet: TransportBootstrapControlMailboxClaimSet,
        responseSet: TransportBootstrapBlindResponseSet,
        registrations: [TransportBootstrapAnonymousMailboxRegistration],
        conductorAssignments: [TransportBootstrapConductorMailboxAssignment],
        registrationSet: TransportBootstrapAnonymousMailboxRegistrationSet,
        acknowledgementSet:
            TransportBootstrapRegistrationSetAcknowledgementSet,
        localControlRecipientSigningKey:
            OpalCrypto.Secp256k1.SigningKey,
        currentUnixSeconds: UInt64
    ) throws -> TransportBootstrapMailboxDistribution {
        let context = TransportBootstrapContract.Context(proof: proof)
        let documents = try validateTransportBootstrapRegistrationDocuments(
            proof: proof,
            authorizationKey: authorizationKey,
            claimSet: claimSet,
            responseSet: responseSet,
            currentUnixSeconds: currentUnixSeconds
        )
        let backing = try validateTransportBootstrapRegistrationBacking(
            proof: proof,
            authorizationKey: documents.authorizationKey,
            claimSet: documents.claimSet,
            responseSet: documents.responseSet,
            registrations: registrations,
            conductorAssignments: conductorAssignments,
            currentUnixSeconds: currentUnixSeconds
        )
        let validatedSet = try loadTransportBootstrapAnonymousMailboxRegistrationSet(
            from: registrationSet.canonicalDocument,
            proof: proof,
            authorizationKey: documents.authorizationKey,
            claimSet: documents.claimSet,
            responseSet: documents.responseSet,
            currentUnixSeconds: currentUnixSeconds
        )
        guard validatedSet.mailboxBundleCommitments
                == backing.commitments else {
            throw TransportBootstrapFailure.invalidRegistrationSet
        }
        let acknowledgements = try loadTransportBootstrapRegistrationSetAcknowledgementSet(
            from: acknowledgementSet.canonicalDocument,
            proof: proof,
            authorizationKey: documents.authorizationKey,
            claimSet: documents.claimSet,
            responseSet: documents.responseSet,
            registrationSet: validatedSet,
            currentUnixSeconds: currentUnixSeconds
        )
        let controlMailboxes = try makeTransportBootstrapControlMailboxes(
            documents.claimSet
        )
        try validateTransportBootstrapLocalControlRecipient(
            localControlRecipientSigningKey,
            controlIdentity: context.conductorControlIdentity,
            claimSet: documents.claimSet
        )
        let anonymousKeys = conductorAssignments.flatMap {
            $0.recipientSigningKeys
        }.sorted {
            $0.bip340VerificationKey.rawRepresentation
                .lexicographicallyPrecedes(
                    $1.bip340VerificationKey.rawRepresentation
                )
        }
        guard anonymousKeys.count
                == context.contributorControlIdentities.count
                    * TransportBootstrapContract.anonymousMailboxCount else {
            throw TransportBootstrapFailure.invalidAnonymousMailboxCount
        }
        let assignmentDocuments = conductorAssignments.map {
            $0.assignment.canonicalDocument
        }.sorted { $0.lexicographicallyPrecedes($1) }
        let registrationDocuments = backing.registrations.map(
            \.canonicalDocument
        ).sorted { $0.lexicographicallyPrecedes($1) }
        return .init(
            mailboxCapabilities: .init(
                controlMailboxes: controlMailboxes,
                localControlRecipientSigningKey:
                    localControlRecipientSigningKey,
                anonymous: .conductor(anonymousKeys)
            ),
            controlClaimSetDigest: documents.claimSet.digest,
            registrationSetDigest: validatedSet.digest,
            acknowledgementSetDigest: acknowledgements.digest,
            authenticatedDocuments: [
                documents.authorizationKey.canonicalDocument,
                documents.claimSet.canonicalDocument,
                documents.responseSet.canonicalDocument,
            ] + registrationDocuments + assignmentDocuments + [
                validatedSet.canonicalDocument,
                acknowledgements.canonicalDocument,
            ]
        )
    }

    private static func makeTransportBootstrapControlMailboxes(
        _ claimSet: TransportBootstrapControlMailboxClaimSet
    ) throws -> [PostManifestControlMailbox] {
        try claimSet.claims.map { claim in
            .init(
                controlIdentity: claim.controlIdentity,
                eventVerificationKey: try .init(
                    rawRepresentation: claim.recipientEventIdentity
                )
            )
        }
    }

    private static func validateTransportBootstrapLocalControlRecipient(
        _ signingKey: OpalCrypto.Secp256k1.SigningKey,
        controlIdentity: Data,
        claimSet: TransportBootstrapControlMailboxClaimSet
    ) throws {
        guard let claim = claimSet.claims.first(where: {
            $0.controlIdentity == controlIdentity
        }),
        signingKey.bip340VerificationKey.rawRepresentation
            == claim.recipientEventIdentity else {
            throw TransportBootstrapFailure.invalidRecipient
        }
    }
}
#endif

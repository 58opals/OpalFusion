// OpalFusion+MosaicPrivateAlphaRuntime+TransportBootstrapConsensusEnvelope.swift

#if os(macOS)
import Foundation
import OpalCrypto

extension OpalFusion.MosaicPrivateAlphaRuntime {
    @_spi(MosaicPrivateAlpha)
    public static func openTransportBootstrapAuthorizationKeyDocument(
        from canonicalEventBytes: Data,
        proof: PrivateDeploymentProof,
        recipientControlSigningKey: OpalCrypto.Secp256k1.SigningKey,
        currentUnixSeconds: UInt64
    ) throws -> TransportBootstrapOpenedPublication<
        TransportBootstrapAuthorizationKeyDocument
    > {
        let context = TransportBootstrapContract.Context(proof: proof)
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
        let document = try loadTransportBootstrapAuthorizationKeyDocument(
            from: opened.canonicalDocument,
            proof: proof,
            currentUnixSeconds: currentUnixSeconds
        )
        guard opened.senderEventIdentity
                == context.conductorControlIdentity else {
            throw TransportBootstrapFailure.invalidSigner
        }
        return opened.projecting(document)
    }

    @_spi(MosaicPrivateAlpha)
    public static func openTransportBootstrapBlindResponseSet(
        from canonicalEventBytes: Data,
        proof: PrivateDeploymentProof,
        authorizationKey: TransportBootstrapAuthorizationKeyDocument,
        claimSet: TransportBootstrapControlMailboxClaimSet,
        recipientContributorControlSigningKey:
            OpalCrypto.Secp256k1.SigningKey,
        currentUnixSeconds: UInt64
    ) throws -> TransportBootstrapOpenedPublication<
        TransportBootstrapBlindResponseSet
    > {
        let context = TransportBootstrapContract.Context(proof: proof)
        let opened = try openTransportBootstrapEvent(
            canonicalEventBytes,
            proof: proof,
            recipientSigningKey:
                recipientContributorControlSigningKey,
            allowedRecipientEventIdentities:
                Set(context.contributorControlIdentities),
            excludedWrapperEventIdentities: Set(
                context.preManifestEventIdentities
                    + claimSet.claims.map(\.recipientEventIdentity)
            ),
            currentUnixSeconds: currentUnixSeconds
        )
        let responseSet = try loadTransportBootstrapBlindResponseSet(
            from: opened.canonicalDocument,
            proof: proof,
            authorizationKey: authorizationKey,
            claimSet: claimSet,
            currentUnixSeconds: currentUnixSeconds
        )
        guard opened.senderEventIdentity
                == context.conductorControlIdentity else {
            throw TransportBootstrapFailure.invalidSigner
        }
        return opened.projecting(responseSet)
    }

    @_spi(MosaicPrivateAlpha)
    public static func sealTransportBootstrapAnonymousMailboxRegistrationSet(
        _ registrationSet: TransportBootstrapAnonymousMailboxRegistrationSet,
        proof: PrivateDeploymentProof,
        authorizationKey: TransportBootstrapAuthorizationKeyDocument,
        claimSet: TransportBootstrapControlMailboxClaimSet,
        responseSet: TransportBootstrapBlindResponseSet,
        conductorAssignments: [TransportBootstrapConductorMailboxAssignment],
        binding: Binding,
        conductorControlSigningKey: OpalCrypto.Secp256k1.SigningKey,
        recipientControlIdentity: Data,
        wrapperSigningKey: OpalCrypto.Secp256k1.SigningKey,
        reservedEventIdentities: Set<Data>,
        timestamps: TransportBootstrapLayerTimestamps
    ) throws -> TransportBootstrapPublication {
        let context = TransportBootstrapContract.Context(proof: proof)
        let validated = try loadTransportBootstrapAnonymousMailboxRegistrationSet(
            from: registrationSet.canonicalDocument,
            proof: proof,
            authorizationKey: authorizationKey,
            claimSet: claimSet,
            responseSet: responseSet,
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
            documentEventIdentities:
                try transportBootstrapAssignmentEventIdentities(
                    conductorAssignments,
                    registrationSet: validated,
                    context: context,
                    claimSet: claimSet
                ),
            reservedEventIdentities: reservedEventIdentities,
            timestamps: timestamps
        )
    }

    @_spi(MosaicPrivateAlpha)
    public static func openTransportBootstrapAnonymousMailboxRegistrationSet(
        from canonicalEventBytes: Data,
        proof: PrivateDeploymentProof,
        authorizationKey: TransportBootstrapAuthorizationKeyDocument,
        claimSet: TransportBootstrapControlMailboxClaimSet,
        responseSet: TransportBootstrapBlindResponseSet,
        localAnonymousMailboxAssignment:
            TransportBootstrapAnonymousMailboxAssignment?,
        recipientControlSigningKey: OpalCrypto.Secp256k1.SigningKey,
        currentUnixSeconds: UInt64
    ) throws -> TransportBootstrapOpenedPublication<
        TransportBootstrapAnonymousMailboxRegistrationSet
    > {
        let context = TransportBootstrapContract.Context(proof: proof)
        let recipientControlIdentity = recipientControlSigningKey
            .bip340VerificationKey.rawRepresentation
        let knownEventIdentities = try transportBootstrapKnownEventIdentities(
            context: context,
            claimSet: claimSet,
            registrationSet: nil,
            recipientControlIdentity: recipientControlIdentity,
            assignment: localAnonymousMailboxAssignment
        )
        let opened = try openTransportBootstrapEvent(
            canonicalEventBytes,
            proof: proof,
            recipientSigningKey: recipientControlSigningKey,
            allowedRecipientEventIdentities: Set(context.controlIdentities),
            excludedWrapperEventIdentities: knownEventIdentities,
            currentUnixSeconds: currentUnixSeconds
        )
        let registrationSet = try loadTransportBootstrapAnonymousMailboxRegistrationSet(
            from: opened.canonicalDocument,
            proof: proof,
            authorizationKey: authorizationKey,
            claimSet: claimSet,
            responseSet: responseSet,
            currentUnixSeconds: currentUnixSeconds
        )
        guard opened.senderEventIdentity
                == context.conductorControlIdentity else {
            throw TransportBootstrapFailure.invalidSigner
        }
        _ = try transportBootstrapKnownEventIdentities(
            context: context,
            claimSet: claimSet,
            registrationSet: registrationSet,
            recipientControlIdentity: recipientControlIdentity,
            assignment: localAnonymousMailboxAssignment
        )
        return opened.projecting(registrationSet)
    }

    @_spi(MosaicPrivateAlpha)
    public static func sealTransportBootstrapRegistrationSetAcknowledgement(
        _ acknowledgement:
            TransportBootstrapRegistrationSetAcknowledgement,
        proof: PrivateDeploymentProof,
        authorizationKey: TransportBootstrapAuthorizationKeyDocument,
        claimSet: TransportBootstrapControlMailboxClaimSet,
        responseSet: TransportBootstrapBlindResponseSet,
        registrationSet: TransportBootstrapAnonymousMailboxRegistrationSet,
        localAnonymousMailboxAssignment:
            TransportBootstrapAnonymousMailboxAssignment?,
        binding: Binding,
        senderControlSigningKey: OpalCrypto.Secp256k1.SigningKey,
        conductorControlIdentity: Data,
        wrapperSigningKey: OpalCrypto.Secp256k1.SigningKey,
        reservedEventIdentities: Set<Data>,
        timestamps: TransportBootstrapLayerTimestamps
    ) throws -> TransportBootstrapPublication {
        let context = TransportBootstrapContract.Context(proof: proof)
        let validated = try loadTransportBootstrapRegistrationSetAcknowledgement(
            from: acknowledgement.canonicalDocument,
            proof: proof,
            authorizationKey: authorizationKey,
            claimSet: claimSet,
            responseSet: responseSet,
            registrationSet: registrationSet,
            currentUnixSeconds: timestamps.currentUnixSeconds
        )
        let validatedSet = try loadTransportBootstrapAnonymousMailboxRegistrationSet(
            from: registrationSet.canonicalDocument,
            proof: proof,
            authorizationKey: authorizationKey,
            claimSet: claimSet,
            responseSet: responseSet,
            currentUnixSeconds: timestamps.currentUnixSeconds
        )
        guard validated.controlIdentity
                == senderControlSigningKey.bip340VerificationKey
                    .rawRepresentation,
              conductorControlIdentity
                == context.conductorControlIdentity else {
            throw TransportBootstrapFailure.invalidSigner
        }
        return try makeTransportBootstrapPublication(
            canonicalDocument: validated.canonicalDocument,
            senderSigningKey: senderControlSigningKey,
            recipientEventIdentity: conductorControlIdentity,
            allowedRecipientEventIdentities:
                [context.conductorControlIdentity],
            proof: proof,
            binding: binding,
            wrapperSigningKey: wrapperSigningKey,
            documentEventIdentities:
                try transportBootstrapKnownEventIdentities(
                    context: context,
                    claimSet: claimSet,
                    registrationSet: validatedSet,
                    recipientControlIdentity: validated.controlIdentity,
                    assignment: localAnonymousMailboxAssignment
                ),
            reservedEventIdentities: reservedEventIdentities,
            timestamps: timestamps
        )
    }

    @_spi(MosaicPrivateAlpha)
    public static func openTransportBootstrapRegistrationSetAcknowledgement(
        from canonicalEventBytes: Data,
        proof: PrivateDeploymentProof,
        authorizationKey: TransportBootstrapAuthorizationKeyDocument,
        claimSet: TransportBootstrapControlMailboxClaimSet,
        responseSet: TransportBootstrapBlindResponseSet,
        registrationSet: TransportBootstrapAnonymousMailboxRegistrationSet,
        conductorAssignments: [TransportBootstrapConductorMailboxAssignment],
        conductorControlSigningKey: OpalCrypto.Secp256k1.SigningKey,
        currentUnixSeconds: UInt64
    ) throws -> TransportBootstrapOpenedPublication<
        TransportBootstrapRegistrationSetAcknowledgement
    > {
        let context = TransportBootstrapContract.Context(proof: proof)
        let validatedSet = try loadTransportBootstrapAnonymousMailboxRegistrationSet(
            from: registrationSet.canonicalDocument,
            proof: proof,
            authorizationKey: authorizationKey,
            claimSet: claimSet,
            responseSet: responseSet,
            currentUnixSeconds: currentUnixSeconds
        )
        let opened = try openTransportBootstrapEvent(
            canonicalEventBytes,
            proof: proof,
            recipientSigningKey: conductorControlSigningKey,
            allowedRecipientEventIdentities:
                [context.conductorControlIdentity],
            excludedWrapperEventIdentities:
                try transportBootstrapAssignmentEventIdentities(
                    conductorAssignments,
                    registrationSet: validatedSet,
                    context: context,
                    claimSet: claimSet
                ).union(context.preManifestEventIdentities),
            currentUnixSeconds: currentUnixSeconds
        )
        let acknowledgement = try loadTransportBootstrapRegistrationSetAcknowledgement(
            from: opened.canonicalDocument,
            proof: proof,
            authorizationKey: authorizationKey,
            claimSet: claimSet,
            responseSet: responseSet,
            registrationSet: validatedSet,
            currentUnixSeconds: currentUnixSeconds
        )
        guard opened.senderEventIdentity
                == acknowledgement.controlIdentity else {
            throw TransportBootstrapFailure.invalidSigner
        }
        return opened.projecting(acknowledgement)
    }

    @_spi(MosaicPrivateAlpha)
    public static func sealTransportBootstrapRegistrationSetAcknowledgementSet(
        _ acknowledgementSet:
            TransportBootstrapRegistrationSetAcknowledgementSet,
        proof: PrivateDeploymentProof,
        authorizationKey: TransportBootstrapAuthorizationKeyDocument,
        claimSet: TransportBootstrapControlMailboxClaimSet,
        responseSet: TransportBootstrapBlindResponseSet,
        registrationSet: TransportBootstrapAnonymousMailboxRegistrationSet,
        conductorAssignments: [TransportBootstrapConductorMailboxAssignment],
        binding: Binding,
        conductorControlSigningKey: OpalCrypto.Secp256k1.SigningKey,
        recipientControlIdentity: Data,
        wrapperSigningKey: OpalCrypto.Secp256k1.SigningKey,
        reservedEventIdentities: Set<Data>,
        timestamps: TransportBootstrapLayerTimestamps
    ) throws -> TransportBootstrapPublication {
        let context = TransportBootstrapContract.Context(proof: proof)
        let validatedSet = try loadTransportBootstrapAnonymousMailboxRegistrationSet(
            from: registrationSet.canonicalDocument,
            proof: proof,
            authorizationKey: authorizationKey,
            claimSet: claimSet,
            responseSet: responseSet,
            currentUnixSeconds: timestamps.currentUnixSeconds
        )
        let validated = try loadTransportBootstrapRegistrationSetAcknowledgementSet(
            from: acknowledgementSet.canonicalDocument,
            proof: proof,
            authorizationKey: authorizationKey,
            claimSet: claimSet,
            responseSet: responseSet,
            registrationSet: validatedSet,
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
            documentEventIdentities:
                try transportBootstrapAssignmentEventIdentities(
                    conductorAssignments,
                    registrationSet: validatedSet,
                    context: context,
                    claimSet: claimSet
                ),
            reservedEventIdentities: reservedEventIdentities,
            timestamps: timestamps
        )
    }

    @_spi(MosaicPrivateAlpha)
    public static func openTransportBootstrapRegistrationSetAcknowledgementSet(
        from canonicalEventBytes: Data,
        proof: PrivateDeploymentProof,
        authorizationKey: TransportBootstrapAuthorizationKeyDocument,
        claimSet: TransportBootstrapControlMailboxClaimSet,
        responseSet: TransportBootstrapBlindResponseSet,
        registrationSet: TransportBootstrapAnonymousMailboxRegistrationSet,
        localAnonymousMailboxAssignment:
            TransportBootstrapAnonymousMailboxAssignment?,
        recipientControlSigningKey: OpalCrypto.Secp256k1.SigningKey,
        currentUnixSeconds: UInt64
    ) throws -> TransportBootstrapOpenedPublication<
        TransportBootstrapRegistrationSetAcknowledgementSet
    > {
        let context = TransportBootstrapContract.Context(proof: proof)
        let recipientControlIdentity = recipientControlSigningKey
            .bip340VerificationKey.rawRepresentation
        let validatedSet = try loadTransportBootstrapAnonymousMailboxRegistrationSet(
            from: registrationSet.canonicalDocument,
            proof: proof,
            authorizationKey: authorizationKey,
            claimSet: claimSet,
            responseSet: responseSet,
            currentUnixSeconds: currentUnixSeconds
        )
        let opened = try openTransportBootstrapEvent(
            canonicalEventBytes,
            proof: proof,
            recipientSigningKey: recipientControlSigningKey,
            allowedRecipientEventIdentities: Set(context.controlIdentities),
            excludedWrapperEventIdentities:
                try transportBootstrapKnownEventIdentities(
                    context: context,
                    claimSet: claimSet,
                    registrationSet: validatedSet,
                    recipientControlIdentity: recipientControlIdentity,
                    assignment: localAnonymousMailboxAssignment
                ),
            currentUnixSeconds: currentUnixSeconds
        )
        let acknowledgementSet = try loadTransportBootstrapRegistrationSetAcknowledgementSet(
            from: opened.canonicalDocument,
            proof: proof,
            authorizationKey: authorizationKey,
            claimSet: claimSet,
            responseSet: responseSet,
            registrationSet: validatedSet,
            currentUnixSeconds: currentUnixSeconds
        )
        guard opened.senderEventIdentity
                == context.conductorControlIdentity else {
            throw TransportBootstrapFailure.invalidSigner
        }
        return opened.projecting(acknowledgementSet)
    }

    private static func transportBootstrapAssignmentEventIdentities(
        _ assignments: [TransportBootstrapConductorMailboxAssignment],
        registrationSet: TransportBootstrapAnonymousMailboxRegistrationSet,
        context: TransportBootstrapContract.Context,
        claimSet: TransportBootstrapControlMailboxClaimSet
    ) throws -> Set<Data> {
        guard assignments.count
                == context.contributorControlIdentities.count else {
            throw TransportBootstrapFailure.invalidRegistrationSet
        }
        let projected = assignments.map(\.assignment)
        let commitments = projected.map(\.mailboxBundleCommitment)
        guard commitments.sorted(by: { $0.lexicographicallyPrecedes($1) })
                == registrationSet.mailboxBundleCommitments,
              Set(commitments).count == assignments.count,
              Set(projected.map(\.anonymousRecipientEventIdentity)).count
                == assignments.count else {
            throw TransportBootstrapFailure.invalidRegistrationSet
        }

        let claimRecipients = Set(
            claimSet.claims.map(\.recipientEventIdentity)
        )
        let anonymousRecipients = Set(
            projected.map(\.anonymousRecipientEventIdentity)
        )
        let unavailable = Set(context.preManifestEventIdentities)
            .union(claimRecipients)
        var mailboxRecipients = Set<Data>()
        for conductorAssignment in assignments {
            let assignment = conductorAssignment.assignment
            guard assignment.roundIdentifier == context.roundIdentifier,
                  assignment.relaySetDigest == context.relaySetDigest,
                  conductorAssignment.recipientSigningKeys.map({
                      $0.bip340VerificationKey.rawRepresentation
                  }) == assignment.recipientEventIdentities,
                  try TransportBootstrapContract.mailboxBundleCommitment(
                      recipientEventIdentities:
                          assignment.recipientEventIdentities
                  ) == assignment.mailboxBundleCommitment else {
                throw TransportBootstrapFailure.invalidRegistrationSet
            }
            try TransportBootstrapContract.validateEventIdentity(
                assignment.anonymousRecipientEventIdentity,
                excluding: unavailable
            )
            for recipient in assignment.recipientEventIdentities {
                try TransportBootstrapContract.validateEventIdentity(
                    recipient,
                    excluding: unavailable.union(anonymousRecipients)
                )
                guard mailboxRecipients.insert(recipient).inserted else {
                    throw TransportBootstrapFailure.duplicateMailboxIdentity
                }
            }
        }
        return claimRecipients
            .union(anonymousRecipients)
            .union(mailboxRecipients)
    }

    private static func transportBootstrapKnownEventIdentities(
        context: TransportBootstrapContract.Context,
        claimSet: TransportBootstrapControlMailboxClaimSet,
        registrationSet:
            TransportBootstrapAnonymousMailboxRegistrationSet?,
        recipientControlIdentity: Data,
        assignment: TransportBootstrapAnonymousMailboxAssignment?
    ) throws -> Set<Data> {
        let isContributor = context.contributorControlIdentities.contains(
            recipientControlIdentity
        )
        guard context.controlIdentities.contains(recipientControlIdentity),
              isContributor == (assignment != nil) else {
            throw TransportBootstrapFailure.invalidRecipient
        }
        var identities = Set(
            context.preManifestEventIdentities
                + claimSet.claims.map(\.recipientEventIdentity)
        )
        if let assignment {
            guard assignment.roundIdentifier == context.roundIdentifier,
                  assignment.relaySetDigest == context.relaySetDigest,
                  try TransportBootstrapContract.mailboxBundleCommitment(
                      recipientEventIdentities:
                          assignment.recipientEventIdentities
                  ) == assignment.mailboxBundleCommitment,
                  registrationSet?.mailboxBundleCommitments.contains(
                      assignment.mailboxBundleCommitment
                  ) ?? true else {
                throw TransportBootstrapFailure.invalidRegistrationSet
            }
            identities.insert(
                assignment.anonymousRecipientEventIdentity
            )
            identities.formUnion(assignment.recipientEventIdentities)
        }
        return identities
    }
}
#endif

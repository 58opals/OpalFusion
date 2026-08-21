// MosaicPrivateDeploymentFixtures~RuntimeCapabilities.swift

import Foundation
import OpalCrypto
@_spi(MosaicPrivateAlpha) @testable import OpalFusion

extension MosaicPrivateDeploymentFixtures {
    typealias Runtime = OpalFusion.MosaicPrivateAlphaRuntime

    static func makeLocalBeaconInput(
        formation: Formation
    ) -> (candidate: CandidateKeyMaterial, proofOfWorkNonce: UInt64) {
        let beacon = formation.selection.selectedBeacons[0]
        return (
            formation.discovery.candidate(
                for: beacon.core.discoveryIdentity
            ),
            beacon.core.proofOfWorkNonce
        )
    }

    static func makeAlternateBeaconEvent(
        formation: Formation,
        documentAuxiliaryByte: UInt8,
        eventAuxiliaryByte: UInt8
    ) throws -> Runtime.PrivateDeploymentEvent {
        let beacon = formation.selection.selectedBeacons[0]
        let candidate = formation.discovery.candidate(
            for: beacon.core.discoveryIdentity
        )
        let alternate = try Alpha.AvailabilityBeaconDocument(
            core: beacon.core,
            claimedWorkBitCount: beacon.claimedWorkBitCount,
            signature: sign(
                digestBytes: beacon.signatureDigest,
                using: candidate.signingKey,
                auxiliaryByte: documentAuxiliaryByte
            )
        )
        let limits = try OpalFusion.Mosaic.NostrNamespace.EventCodingLimits(
            maximumEventJSONByteCount: 200_000,
            maximumTagCount: 1,
            maximumTagElementCount: 2,
            maximumStringByteCount: 150_000
        )
        let createdAt = formation.discovery.epochStart + 1
        let event = try Alpha.PreManifestNostrCodec.makeEvent(
            for: .makeAvailabilityBeacon(alternate),
            createdAtUnixSeconds: createdAt,
            using: candidate.signingKey,
            auxiliaryRandomness: .init(
                rawRepresentation: Data(
                    repeating: eventAuxiliaryByte,
                    count: 32
                )
            ),
            limits: limits
        )
        return try .init(
            canonicalEventBytes: try OpalFusion.Mosaic.NostrNamespace
                .EventCodec.encode(event, limits: limits),
            acceptedAtUnixSeconds: createdAt
        )
    }

    static func rewrapPrivateDeploymentEvent(
        _ event: Runtime.PrivateDeploymentEvent,
        using signingKey: OpalCrypto.Secp256k1.SigningKey,
        createdAtUnixSeconds: UInt64,
        eventAuxiliaryByte: UInt8
    ) throws -> Runtime.PrivateDeploymentEvent {
        let payload = try Alpha.PreManifestNostrCodec
            .decodeCanonicalEnvelope(event.decodeCanonicalNostrEvent())
        return try makeStoredPrivateDeploymentEvent(
            payload: payload,
            using: signingKey,
            createdAtUnixSeconds: createdAtUnixSeconds,
            eventAuxiliaryByte: eventAuxiliaryByte
        )
    }

    static func makeConflictingAdmissionEvent(
        formation: Formation,
        replacing event: Runtime.PrivateDeploymentEvent,
        createdAtUnixSeconds: UInt64,
        eventAuxiliaryByte: UInt8
    ) throws -> Runtime.PrivateDeploymentEvent {
        let signer = try event.decodeCanonicalNostrEvent().publicKey
        let discoveryCandidate = formation.discovery.candidate(for: signer)
        guard let original = formation.controlRoster.admissions.first(where: {
            $0.discoveryIdentity == signer
        }), let alternateControl = formation.controlCandidates.first(where: {
            $0.controlIdentity != original.controlIdentity
        }) else {
            throw Runtime.Failure.invalidPrivateDeploymentProof
        }
        let conflicting = try makeAdmission(
            selection: formation.selection,
            discoveryCandidate: discoveryCandidate,
            controlCandidate: alternateControl
        )
        return try makeStoredPrivateDeploymentEvent(
            payload: .makeCandidateAdmission(conflicting),
            using: discoveryCandidate.signingKey,
            createdAtUnixSeconds: createdAtUnixSeconds,
            eventAuxiliaryByte: eventAuxiliaryByte
        )
    }

    private static func makeStoredPrivateDeploymentEvent(
        payload: Alpha.PreManifestNostrPayloadDocument,
        using signingKey: OpalCrypto.Secp256k1.SigningKey,
        createdAtUnixSeconds: UInt64,
        eventAuxiliaryByte: UInt8
    ) throws -> Runtime.PrivateDeploymentEvent {
        let limits = try OpalFusion.Mosaic.NostrNamespace.EventCodingLimits(
            maximumEventJSONByteCount: 200_000,
            maximumTagCount: 1,
            maximumTagElementCount: 2,
            maximumStringByteCount: 150_000
        )
        let event = try Alpha.PreManifestNostrCodec.makeEvent(
            for: payload,
            createdAtUnixSeconds: createdAtUnixSeconds,
            using: signingKey,
            auxiliaryRandomness: .init(
                rawRepresentation: Data(
                    repeating: eventAuxiliaryByte,
                    count: 32
                )
            ),
            limits: limits
        )
        return try .init(
            canonicalEventBytes: try OpalFusion.Mosaic.NostrNamespace
                .EventCodec.encode(event, limits: limits),
            acceptedAtUnixSeconds: createdAtUnixSeconds
        )
    }

    static func makeLocalFormationInputs(
        formation: Formation
    ) throws -> (
        discoveryCandidate: CandidateKeyMaterial,
        admissionControlCandidate: CandidateKeyMaterial,
        roleCandidate: CandidateKeyMaterial,
        roleRandomness: Data,
        conductorCandidate: CandidateKeyMaterial,
        publicSources: [Data],
        authorizationKeys: Runtime.PrivateDeploymentManifestAuthorizationKeys,
        manifestSigner: CandidateKeyMaterial
    ) {
        let selected = formation.selection.selectedBeacons[0]
        let roleReveal = formation.reveals[0]
        return (
            formation.discovery.candidate(
                for: selected.core.discoveryIdentity
            ),
            formation.controlCandidates[0],
            formation.controlCandidate(for: roleReveal.candidate),
            Data(roleReveal.randomness),
            formation.controlCandidate(
                for: formation.roleElection.roster.conductor
            ),
            formation.nonceAllocation.allocations.map {
                Data($0.publicSource)
            },
            .init(
                component: try MosaicMainnetAlphaFixtures
                    .rsaVerificationKey(),
                bchSignature: try MosaicMainnetAlphaFixtures
                    .bchSignatureRSAVerificationKey()
            ),
            formation.controlCandidate(
                for: formation.roleElection.roster.controlIdentities[0]
            )
        )
    }

    static func makeRuntimeCapabilities(
        formation: Formation,
        localControlIdentity: Data,
        admissionStore: MosaicPrivateAlphaRuntimePersistenceStore,
        publicationStore: MosaicPrivateAlphaRuntimePersistenceStore,
        terminalStore: MosaicPrivateAlphaRuntimePersistenceStore,
        routeStore: MosaicPrivateAlphaRuntimePersistenceStore
    ) throws -> Runtime.PostManifestRuntimeCapabilities {
        let roster = formation.roleElection.roster
        let mailboxKeys = try roster.controlIdentities.indices.map { index in
            try CandidateKeyMaterial(scalar: UInt8(100 + index)).signingKey
        }
        guard let localIndex = roster.controlIdentities.firstIndex(where: {
            Data($0.validatedBytes) == localControlIdentity
        }) else {
            throw Runtime.Failure.localControlIdentityNotInPrivateDeployment
        }
        let controlMailboxes = zip(
            roster.controlIdentities,
            mailboxKeys
        ).map { identity, key in
            Runtime.PostManifestControlMailbox(
                controlIdentity: Data(identity.validatedBytes),
                eventVerificationKey: key.bip340VerificationKey
            )
        }
        let anonymous: Runtime.PostManifestAnonymousMailboxes
        if Data(roster.conductor.validatedBytes) == localControlIdentity {
            anonymous = .conductor(try (0 ..< roster.contributors.count
                * Alpha.componentCountPerContributor).map { index in
                    try makeSigningKey(seed: 150 + index)
                })
        } else {
            anonymous = .contributor(try (0 ..< Alpha
                .componentCountPerContributor).map { index in
                    try makeSigningKey(seed: 400 + index)
                        .bip340VerificationKey
                })
        }
        let admissionPersistence = Runtime.PostManifestAdmissionPersistence(
            load: admissionStore.load,
            compareAndSwap: admissionStore.compareAndSwap
        )
        let publicationPersistence = Runtime
            .PostManifestPublicationPersistence(
                load: publicationStore.load,
                compareAndSwap: publicationStore.compareAndSwap
            )
        let terminalPersistence = Runtime.PostManifestTerminalPersistence(
            load: terminalStore.load,
            compareAndSwap: terminalStore.compareAndSwap
        )
        let phaseStart = try Alpha.PrivateDeploymentPolicy.frozen
            .preManifestDeadlines(
                forEpochStartingAt: formation.discovery.epochStart
            ).manifestAgreement
        return .init(
            mailboxes: .init(
                controlMailboxes: controlMailboxes,
                localControlRecipientSigningKey: mailboxKeys[localIndex],
                anonymous: anonymous
            ),
            relays: .init(
                provisionRoutes: { _ in
                    routeStore.recordProvisionCall()
                    throw Runtime.Failure.invalidStateTransition
                },
                makeSubscriptionIdentifier: { request, endpoint in
                    let seed = request.recipientEventIdentity.prefix(4)
                        .map { String(format: "%02x", $0) }.joined()
                    return "mosaic-\(seed)-\(endpoint)"
                },
                maximumSubscriptionIdentifierByteCount: 80
            ),
            timing: .init(
                currentUnixSeconds: { phaseStart },
                makeLayerTimestamps: { request in
                    guard request.phaseStartUnixSeconds == phaseStart else {
                        throw Runtime.Failure.invalidStateTransition
                    }
                    return .init(
                        phaseStartUnixSeconds: request.phaseStartUnixSeconds,
                        currentUnixSeconds: request.expiryUnixSeconds,
                        sealCreatedAt: request.expiryUnixSeconds - 2,
                        giftWrapCreatedAt: request.expiryUnixSeconds - 1
                    )
                }
            ),
            admissionPersistence: admissionPersistence,
            publicationPersistence: publicationPersistence,
            terminalPersistence: terminalPersistence
        )
    }

    static func makePostManifestControlRecoveryRecord(
        formation: Formation,
        bootstrap: Alpha.PostManifestRuntimeDriver.Bootstrap,
        recipientSigningKey: OpalCrypto.Secp256k1.SigningKey,
        acceptedAtUnixSeconds: UInt64
    ) throws -> Alpha.PostManifestAdmissionJournal.AcceptedRecord {
        let sender = formation.roleElection.roster.conductor
        guard let senderIndex = formation.roleElection.roster
            .controlIdentities.firstIndex(of: sender) else {
            throw Runtime.Failure.invalidStateTransition
        }
        let senderControlKey = formation.controlCandidate(for: sender)
            .signingKey
        let senderEventKey = try makeSigningKey(seed: 125 + senderIndex)
        let payload: [UInt8] = [0x01]
        let expiry = bootstrap.proposalValidation.core.deadlines
            .walletReservation
        let digest = try Alpha.ControlEnvelope.signingDigest(
            roundIdentifier:
                bootstrap.proposalValidation.core.roundIdentifier,
            phase: .walletReservation,
            senderControlIdentity: sender,
            senderEventIdentity: Array(
                senderEventKey.bip340VerificationKey.rawRepresentation
            ),
            sequence: 0,
            payloadType: .aggregateReservation,
            expiryUnixSeconds: expiry,
            payload: payload
        )
        let signature = try senderControlKey.signBIP340(
            digest: .init(rawRepresentation: Data(digest)),
            auxiliaryRandomness: .init(
                rawRepresentation: Data(repeating: 0xA4, count: 32)
            )
        )
        let envelope = try Alpha.ControlEnvelope(
            roundIdentifier:
                bootstrap.proposalValidation.core.roundIdentifier,
            phase: .walletReservation,
            senderControlIdentity: sender,
            senderEventIdentity: Array(
                senderEventKey.bip340VerificationKey.rawRepresentation
            ),
            sequence: 0,
            payloadType: .aggregateReservation,
            expiryUnixSeconds: expiry,
            controlSignature: Array(signature.rawRepresentation),
            payload: payload
        )
        let phaseStart = bootstrap.proposalValidation.core.deadlines.phaseStart
        let giftWrap = try Alpha.PostManifestNIP59Transport.makeControlGiftWrap(
            envelope,
            context: .init(
                attemptIdentifier: bootstrap.attemptIdentifier,
                generationIdentifier: bootstrap.generationIdentifier,
                phaseStartUnixSeconds: phaseStart
            ),
            timestamps: .init(
                phaseStartUnixSeconds: phaseStart,
                currentUnixSeconds: phaseStart + 1,
                sealCreatedAt: phaseStart,
                giftWrapCreatedAt: phaseStart
            ),
            senderEventSigningKey: senderEventKey,
            recipientPublicKey:
                recipientSigningKey.bip340VerificationKey
        )
        let source = Alpha.PostManifestTransportIngress.RecoveredAdmission(
            canonicalGiftWrapBytes: try OpalFusion.Mosaic.NostrNamespace
                .EventCodec.encode(
                    giftWrap,
                    limits: (try Alpha.PostManifestNIP59Transport
                        .codingLimits).event
                ),
            acceptedAtUnixSeconds: acceptedAtUnixSeconds
        )
        let delivery = try Alpha.PostManifestNIP59Transport.openControl(
            giftWrap,
            context: .init(
                attemptIdentifier: bootstrap.attemptIdentifier,
                generationIdentifier: bootstrap.generationIdentifier,
                phaseStartUnixSeconds: phaseStart
            ),
            recipientSigningKey: recipientSigningKey,
            currentUnixSeconds: acceptedAtUnixSeconds
        )
        guard case let .control(control) = delivery.storage else {
            throw Runtime.Failure.invalidStateTransition
        }
        return .init(control: control, source: source)
    }

    private static func makeSigningKey(
        seed: Int
    ) throws -> OpalCrypto.Secp256k1.SigningKey {
        guard (1 ... Int(UInt16.max)).contains(seed) else {
            throw Runtime.Failure.invalidStateTransition
        }
        let scalar = UInt16(seed)
        return try .init(
            rawRepresentation: Data(repeating: 0, count: 30)
                + Data([UInt8(scalar >> 8), UInt8(truncatingIfNeeded: scalar)])
        )
    }
}

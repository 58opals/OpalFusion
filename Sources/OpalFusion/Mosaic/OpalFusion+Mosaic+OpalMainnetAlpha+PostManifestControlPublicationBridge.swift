// OpalFusion+Mosaic+OpalMainnetAlpha+PostManifestControlPublicationBridge.swift

import Foundation
import OpalCrypto

extension OpalFusion.Mosaic.OpalMainnetAlpha {
    /// Owns one roster member's sender-global post-manifest control sequence.
    ///
    /// The bridge signs each canonical control envelope once, creates one recipient-bound gift
    /// wrap for every roster peer, and waits for the injected recipient-batch handoff before using
    /// the next sequence. It owns no relay endpoints, Tor capabilities, persistence, retry, or
    /// semantic loopback admission. Any ambiguous or partial publication terminalizes the bridge;
    /// retry requires a fresh attempt, generation, round, and key allocation.
    actor PostManifestControlPublicationBridge {
        private enum PublicationShape: Sendable, Equatable {
            case aggregate(AggregateKind)
            case preSignAcknowledgement
        }

        private let context: Context
        private let controlSigningKey: OpalCrypto.Secp256k1.SigningKey
        private let eventSigningKey: OpalCrypto.Secp256k1.SigningKey
        private let recipients: [Recipient]
        private let dependencies: Dependencies

        private(set) var state: State = .ready(
            nextSequence: 0,
            lastPublishedPhase: nil
        )

        init(
            context: Context,
            controlSigningKey: OpalCrypto.Secp256k1.SigningKey,
            eventSigningKey: OpalCrypto.Secp256k1.SigningKey,
            recipients: [Recipient],
            dependencies: Dependencies
        ) throws(InitializationError) {
            let rosterIdentities = context.roster.controlIdentities
            let controlIdentity = Array(
                controlSigningKey.bip340VerificationKey.rawRepresentation
            )
            guard controlIdentity
                    == context.localControlIdentity.validatedBytes else {
                throw .controlSigningKeyMismatch
            }
            let eventIdentity = Array(
                eventSigningKey.bip340VerificationKey.rawRepresentation
            )
            let rosterControlIdentities = Set(
                rosterIdentities.map { Data($0.validatedBytes) }
            )
            guard !rosterControlIdentities.contains(Data(eventIdentity)) else {
                throw .reusedControlAndEventIdentity
            }
            guard recipients.count == rosterIdentities.count else {
                throw .invalidRecipientCount(actual: recipients.count)
            }

            var recipientsByIdentity: [ControlIdentity: Recipient] = [:]
            var recipientEventIdentities: Set<Data> = []
            let senderEventIdentity = Data(eventIdentity)
            for recipient in recipients {
                guard recipientsByIdentity.updateValue(
                    recipient,
                    forKey: recipient.controlIdentity
                ) == nil else {
                    throw .duplicateRecipient(recipient.controlIdentity)
                }
                let recipientEventIdentity = recipient.eventVerificationKey
                    .rawRepresentation
                guard !rosterControlIdentities.contains(
                    recipientEventIdentity
                ) else {
                    throw .recipientEventIdentityReusesRosterControlIdentity
                }
                guard recipientEventIdentity != senderEventIdentity else {
                    throw .recipientEventIdentityReusesSenderEventIdentity
                }
                guard recipientEventIdentities.insert(
                    recipientEventIdentity
                ).inserted else {
                    throw .duplicateRecipientEventIdentity
                }
            }
            guard Set(recipientsByIdentity.keys) == Set(rosterIdentities) else {
                throw .recipientSetMismatch
            }

            self.context = context
            self.controlSigningKey = controlSigningKey
            self.eventSigningKey = eventSigningKey
            self.recipients = rosterIdentities.map {
                guard let recipient = recipientsByIdentity[$0] else {
                    preconditionFailure(
                        "Validated control-recipient coverage must be complete."
                    )
                }
                return recipient
            }
            self.dependencies = dependencies
        }

        /// Publishes the exact manifest already bound to the validated runtime bootstrap.
        func publishManifest(
            expiryUnixSeconds: UInt64
        ) async throws {
            try requireReadyForPublication()
            try failIfCancelled()
            try await publishValidatedAggregate(
                .completeManifest(context.manifest),
                expiryUnixSeconds: expiryUnixSeconds
            )
        }

        /// Publishes the PlayerCommit sealed to one exact reservation and material identity.
        func publishPlayerCommit(
            _ validation: RuntimeSession.ReservationPublicationValidation,
            expiryUnixSeconds: UInt64
        ) async throws {
            try requireReadyForPublication()
            try failIfCancelled()
            let request = validation.request
            guard context.roster.contributors.contains(
                    context.localControlIdentity
                  ),
                  request.attemptIdentifier == context.attemptIdentifier,
                  request.generationIdentifier == context.generationIdentifier,
                  request.materialIdentifier == context.materialIdentifier,
                  request.contributor == context.localControlIdentity,
                  request.manifest == context.manifest else {
                throw terminate(.invalidPublication)
            }
            try await publishValidatedAggregate(
                .playerCommit(request.playerCommit),
                expiryUnixSeconds: expiryUnixSeconds
            )
        }

        /// Publishes one document minted by the exact conductor runtime material.
        func publish(
            _ validation: ConductorCoordinator.PublicationValidation,
            expiryUnixSeconds: UInt64
        ) async throws {
            try requireReadyForPublication()
            try failIfCancelled()
            guard context.localControlIdentity == context.roster.conductor,
                  validation.attemptIdentifier == context.attemptIdentifier,
                  validation.generationIdentifier == context.generationIdentifier,
                  validation.materialIdentifier == context.materialIdentifier,
                  validation.conductor == context.localControlIdentity,
                  validation.manifestBinding == context.manifest.binding else {
                throw terminate(.invalidPublication)
            }
            try await publishValidatedAggregate(
                validation.publication.aggregateDocument,
                expiryUnixSeconds: expiryUnixSeconds
            )
        }

        private func publishValidatedAggregate(
            _ document: AggregateDocument,
            expiryUnixSeconds: UInt64
        ) async throws {
            let kind = document.kind
            let phase = kind.phase
            do {
                try validate(document, phase: phase)
            } catch {
                throw terminate(.invalidPublication)
            }

            let canonicalBytes = document.canonicalBytes
            let reservation: AggregateReservation
            do {
                reservation = try .init(
                    aggregateKind: kind,
                    aggregateDigest: RoleSeedValidator.hash(
                        domainSuffix: kind.digestDomainSuffix,
                        fields: [canonicalBytes]
                    ),
                    declaredCanonicalByteCount: canonicalBytes.count
                )
            } catch {
                throw terminate(.invalidPublication)
            }

            let sequenceReservation = try claimSequences(
                envelopeCount: reservation.fragmentCount + 1,
                phase: phase,
                shape: .aggregate(kind)
            )
            let envelopes: [ControlEnvelope]
            do {
                envelopes = try makeAggregateEnvelopes(
                    canonicalBytes: canonicalBytes,
                    reservation: reservation,
                    sequenceReservation: sequenceReservation,
                    expiryUnixSeconds: expiryUnixSeconds
                )
            } catch {
                throw terminate(.signatureConstructionFailed)
            }
            try await handoff(
                envelopes,
                reservation: sequenceReservation
            )
        }

        /// Signs and publishes one contributor's inner transcript acknowledgement.
        func publishPreSignAcknowledgement(
            _ validation: OpalFusion.Mosaic.LocalAttempt
                .TranscriptInclusionValidation,
            expiryUnixSeconds: UInt64
        ) async throws {
            try requireReadyForPublication()
            try failIfCancelled()
            let contributor = validation.contributor
            let transcript = validation.transcript
            let roundIdentifier = transcript.manifest.roundIdentifier
            let transcriptRoot = transcript.transcriptRoot
            guard context.roster.contributors.contains(
                    context.localControlIdentity
                  ),
                  validation.attemptIdentifier == context.attemptIdentifier,
                  validation.generationIdentifier == context.generationIdentifier,
                  validation.materialIdentifier == context.materialIdentifier,
                  contributor == context.localControlIdentity,
                  roundIdentifier == context.roundIdentifier,
                  transcript.manifest == context.manifest.binding else {
                throw terminate(.invalidPublication)
            }

            let sequenceReservation = try claimSequences(
                envelopeCount: 1,
                phase: .transcriptAgreement,
                shape: .preSignAcknowledgement
            )
            let acknowledgement: PreSignAcknowledgementSubmission
            do {
                let digest = OpalFusion.Mosaic.Attempt
                    .TranscriptAcknowledgementValidation.signatureDigest(
                        profile: .opalMainnetAlpha,
                        roundIdentifier: roundIdentifier,
                        transcriptRoot: transcriptRoot.validatedBytes
                    )
                let signature = try controlSigningKey.signBIP340(
                    digest: digest,
                    auxiliaryRandomness: try dependencies
                        .makeSignatureAuxiliaryRandomness()
                )
                acknowledgement = try .init(
                    contributor: contributor,
                    roundIdentifier: roundIdentifier,
                    transcriptRoot: transcriptRoot.validatedBytes,
                    signature: Array(signature.rawRepresentation)
                )
            } catch {
                throw terminate(.signatureConstructionFailed)
            }

            let envelope: ControlEnvelope
            do {
                envelope = try makeEnvelope(
                    phase: .transcriptAgreement,
                    sequence: sequenceReservation.firstSequence,
                    payloadType: .preSignAcknowledgement,
                    payload: acknowledgement.canonicalBytes,
                    expiryUnixSeconds: expiryUnixSeconds
                )
            } catch {
                throw terminate(.signatureConstructionFailed)
            }
            try await handoff(
                [envelope],
                reservation: sequenceReservation
            )
        }

        private func requireReadyForPublication() throws {
            switch state {
            case .ready:
                return
            case .publishing:
                throw terminate(.concurrentPublication)
            case .terminal:
                throw Failure.inputAfterTermination
            }
        }

        private func failIfCancelled() throws {
            guard !Task.isCancelled else {
                throw terminate(.cancelled)
            }
        }

        private func claimSequences(
            envelopeCount: Int,
            phase: Phase,
            shape: PublicationShape
        ) throws -> SequenceReservation {
            guard case let .ready(nextSequence, lastPublishedPhase) = state else {
                preconditionFailure("Publication readiness was checked before sequence claim.")
            }
            if nextSequence == 0 {
                let expectedFirst: PublicationShape = context.localControlIdentity
                    == context.roster.conductor
                    ? .aggregate(.completeManifest)
                    : .aggregate(.playerCommit)
                guard shape == expectedFirst else {
                    throw terminate(.invalidFirstPublication)
                }
            }
            if let lastPublishedPhase,
               phase.rawValue < lastPublishedPhase.rawValue {
                throw terminate(
                    .phaseRollback(previous: lastPublishedPhase, next: phase)
                )
            }
            guard envelopeCount > 0,
                  let count = UInt64(exactly: envelopeCount) else {
                throw terminate(.sequenceExhausted)
            }
            let (next, overflow) = nextSequence.addingReportingOverflow(count)
            guard !overflow else {
                throw terminate(.sequenceExhausted)
            }
            let reservation = SequenceReservation(
                firstSequence: nextSequence,
                envelopeCount: envelopeCount,
                nextSequence: next,
                phase: phase
            )
            state = .publishing(reservation)
            return reservation
        }

        private func makeAggregateEnvelopes(
            canonicalBytes: [UInt8],
            reservation: AggregateReservation,
            sequenceReservation: SequenceReservation,
            expiryUnixSeconds: UInt64
        ) throws -> [ControlEnvelope] {
            let reservationSequence = sequenceReservation.firstSequence
            var envelopes = [
                try makeEnvelope(
                    phase: sequenceReservation.phase,
                    sequence: reservationSequence,
                    payloadType: .aggregateReservation,
                    payload: try CanonicalWireCodec
                        .encodeAggregateReservation(reservation),
                    expiryUnixSeconds: expiryUnixSeconds
                )
            ]
            let capacity = OpalFusion.Mosaic.OpalMainnetAlpha
                .maximumAggregateFragmentBodyByteCount
            for index in 0 ..< reservation.fragmentCount {
                let lowerBound = index * capacity
                let upperBound = min(lowerBound + capacity, canonicalBytes.count)
                let fragment = try AggregateFragment(
                    reservationSequence: reservationSequence,
                    fragmentIndex: index,
                    body: Array(canonicalBytes[lowerBound ..< upperBound]),
                    reservation: reservation
                )
                envelopes.append(
                    try makeEnvelope(
                        phase: sequenceReservation.phase,
                        sequence: reservationSequence + UInt64(index) + 1,
                        payloadType: .aggregateFragment,
                        payload: try CanonicalWireCodec
                            .encodeAggregateFragment(fragment),
                        expiryUnixSeconds: expiryUnixSeconds
                    )
                )
            }
            precondition(
                envelopes.count == sequenceReservation.envelopeCount,
                "A validated aggregate reservation fixes its complete envelope count."
            )
            return envelopes
        }

        private func makeEnvelope(
            phase: Phase,
            sequence: UInt64,
            payloadType: ControlPayloadType,
            payload: [UInt8],
            expiryUnixSeconds: UInt64
        ) throws -> ControlEnvelope {
            let eventIdentity = Array(
                eventSigningKey.bip340VerificationKey.rawRepresentation
            )
            let digest = try ControlEnvelope.signingDigest(
                roundIdentifier: context.roundIdentifier,
                phase: phase,
                senderControlIdentity: context.localControlIdentity,
                senderEventIdentity: eventIdentity,
                sequence: sequence,
                payloadType: payloadType,
                expiryUnixSeconds: expiryUnixSeconds,
                payload: payload
            )
            let signature = try controlSigningKey.signBIP340(
                digest: .init(rawRepresentation: Data(digest)),
                auxiliaryRandomness: try dependencies
                    .makeSignatureAuxiliaryRandomness()
            )
            return try .init(
                roundIdentifier: context.roundIdentifier,
                phase: phase,
                senderControlIdentity: context.localControlIdentity,
                senderEventIdentity: eventIdentity,
                sequence: sequence,
                payloadType: payloadType,
                expiryUnixSeconds: expiryUnixSeconds,
                controlSignature: Array(signature.rawRepresentation),
                payload: payload
            )
        }

        private func handoff(
            _ envelopes: [ControlEnvelope],
            reservation: SequenceReservation
        ) async throws {
            for envelope in envelopes {
                try failIfCancelled()
                let batch: GiftWrapBatch
                do {
                    let timestamps = try dependencies.makeLayerTimestamps(
                        .init(
                            phase: envelope.phase,
                            sequence: envelope.sequence,
                            expiryUnixSeconds: envelope.expiryUnixSeconds
                        )
                    )
                    let transportContext = Transport.RuntimeContext(
                        attemptIdentifier: context.attemptIdentifier,
                        generationIdentifier: context.generationIdentifier,
                        phaseStartUnixSeconds: context.phaseStartUnixSeconds
                    )
                    let recipientGiftWraps = try recipients.map { recipient in
                        let event = try Transport.makeControlGiftWrap(
                            envelope,
                            context: transportContext,
                            timestamps: timestamps,
                            senderEventSigningKey: eventSigningKey,
                            recipientPublicKey: recipient.eventVerificationKey
                        )
                        return RecipientGiftWrap(
                            controlIdentity: recipient.controlIdentity,
                            giftWrap: try .init(validating: event)
                        )
                    }
                    batch = .init(
                        envelope: envelope,
                        recipients: recipientGiftWraps
                    )
                } catch {
                    throw terminate(.giftWrapConstructionFailed)
                }

                do {
                    try failIfCancelled()
                    try await dependencies.handoffGiftWrapBatch(batch)
                } catch {
                    if Task.isCancelled {
                        throw terminate(.cancelled)
                    }
                    throw terminate(.handoffFailed)
                }
                try failIfCancelled()
                guard state == .publishing(reservation) else {
                    if case let .terminal(failure) = state {
                        throw failure
                    }
                    preconditionFailure(
                        "A publication reservation cannot change without terminalization."
                    )
                }
            }
            state = .ready(
                nextSequence: reservation.nextSequence,
                lastPublishedPhase: reservation.phase
            )
        }

        private func validate(
            _ document: AggregateDocument,
            phase: Phase
        ) throws {
            if case let .completeManifest(manifest) = document,
               manifest != context.manifest {
                throw Failure.invalidPublication
            }
            if case let .completeTransaction(transaction) = document {
                guard context.localControlIdentity == context.roster.conductor,
                      phase == .bchSigning,
                      transaction.roundIdentifier == context.roundIdentifier
                else {
                    throw Failure.invalidPublication
                }
                return
            }
            let publicationContext = try AggregatePublicationContext(
                roundIdentifier: context.roundIdentifier,
                transcriptRoot: document.transcriptRoot,
                phase: phase,
                sender: context.localControlIdentity,
                roster: context.roster
            )
            _ = try ValidatedAggregatePublication(
                document: document,
                context: publicationContext
            )
        }

        @discardableResult
        private func terminate(_ failure: Failure) -> Failure {
            if case let .terminal(existing) = state {
                return existing
            }
            state = .terminal(failure)
            return failure
        }
    }
}

private extension OpalFusion.Mosaic.OpalMainnetAlpha.AggregateKind {
    var phase: OpalFusion.Mosaic.Attempt.Phase {
        switch self {
        case .completeManifest:
            .manifestAgreement
        case .playerCommit, .authorizationResponseSet:
            .walletReservation
        case .commitmentSet:
            .groupedCommitment
        case .componentSet:
            .anonymousComponentSubmission
        case .preSignAcknowledgementSet:
            .transcriptAgreement
        case .bchSignatureSet, .completeTransaction:
            .bchSigning
        }
    }
}

private extension OpalFusion.Mosaic.OpalMainnetAlpha.AggregateDocument {
    var kind: OpalFusion.Mosaic.OpalMainnetAlpha.AggregateKind {
        switch self {
        case .commitmentSet:
            .commitmentSet
        case .componentSet:
            .componentSet
        case .playerCommit:
            .playerCommit
        case .authorizationResponseSet:
            .authorizationResponseSet
        case .completeManifest:
            .completeManifest
        case .preSignAcknowledgementSet:
            .preSignAcknowledgementSet
        case .bchSignatureSet:
            .bchSignatureSet
        case .completeTransaction:
            .completeTransaction
        }
    }

    var canonicalBytes: [UInt8] {
        switch self {
        case let .commitmentSet(commitmentSet):
            commitmentSet.canonicalBytes
        case let .componentSet(componentSet):
            componentSet.canonicalBytes
        case let .playerCommit(playerCommit):
            playerCommit.canonicalBytes
        case let .authorizationResponseSet(responseSet):
            responseSet.canonicalBytes
        case let .completeManifest(manifest):
            manifest.canonicalBytes
        case let .preSignAcknowledgementSet(acknowledgementSet):
            acknowledgementSet.canonicalBytes
        case let .bchSignatureSet(signatureSet):
            signatureSet.canonicalBytes
        case let .completeTransaction(transaction):
            transaction.canonicalBytes
        }
    }

    var transcriptRoot: [UInt8]? {
        switch self {
        case let .preSignAcknowledgementSet(acknowledgementSet):
            acknowledgementSet.transcriptRoot
        case let .bchSignatureSet(signatureSet):
            signatureSet.transcriptRoot
        case let .completeTransaction(transaction):
            transaction.transcriptRoot
        case .commitmentSet, .componentSet, .playerCommit,
             .authorizationResponseSet, .completeManifest:
            nil
        }
    }
}

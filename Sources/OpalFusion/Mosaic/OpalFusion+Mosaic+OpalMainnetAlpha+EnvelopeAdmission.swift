// OpalFusion+Mosaic+OpalMainnetAlpha+EnvelopeAdmission.swift

import OpalCrypto

typealias MainnetAlpha = OpalFusion.Mosaic.OpalMainnetAlpha

extension OpalFusion.Mosaic.OpalMainnetAlpha {
    struct AggregateReservationBinding: Sendable, Equatable {
        let sender: OpalFusion.Mosaic.Attempt.ControlIdentity
        let phase: OpalFusion.Mosaic.Attempt.Phase
        let reservationSequence: UInt64
        let reservation: AggregateReservation
    }

    struct ControlAdmissionContext: Sendable, Equatable {
        let roundIdentifier: [UInt8]
        let phase: OpalFusion.Mosaic.Attempt.Phase
        let roster: OpalFusion.Mosaic.Attempt.Roster
        let authenticatedOuterEventIdentity: [UInt8]
        let currentUnixSeconds: UInt64
        let activeReservation: AggregateReservationBinding?

        init(
            roundIdentifier: [UInt8],
            phase: OpalFusion.Mosaic.Attempt.Phase,
            roster: OpalFusion.Mosaic.Attempt.Roster,
            authenticatedOuterEventIdentity: [UInt8],
            currentUnixSeconds: UInt64,
            activeReservation: AggregateReservationBinding? = nil
        ) throws {
            try RoleSeedValidator.validateFixed(
                roundIdentifier,
                field: .roundIdentifier
            )
            try RoleSeedValidator.validateFixed(
                authenticatedOuterEventIdentity,
                field: .senderEventIdentity
            )
            self.roundIdentifier = Array(roundIdentifier)
            self.phase = phase
            self.roster = roster
            self.authenticatedOuterEventIdentity = Array(
                authenticatedOuterEventIdentity
            )
            self.currentUnixSeconds = currentUnixSeconds
            self.activeReservation = activeReservation
        }
    }

    enum AdmittedControlPayload: Sendable, Equatable {
        case aggregateReservation(AggregateReservationBinding)
        case aggregateFragment(AggregateFragment)
        case preSignAcknowledgement(PreSignAcknowledgementSubmission)
    }
}

extension MainnetAlpha.ControlEnvelope {
    func admit(
        against context: MainnetAlpha.ControlAdmissionContext
    ) throws -> MainnetAlpha.AdmittedControlPayload {
        try validateOuterEventIdentity(
            context.authenticatedOuterEventIdentity
        )
        guard expiryUnixSeconds >= context.currentUnixSeconds else {
            throw MainnetAlpha.ContractError.expiredEnvelope(
                expiryUnixSeconds: expiryUnixSeconds,
                currentUnixSeconds: context.currentUnixSeconds
            )
        }
        guard roundIdentifier == context.roundIdentifier else {
            throw MainnetAlpha.ContractError.aggregateRoundMismatch
        }
        guard phase == context.phase else {
            throw MainnetAlpha.ContractError.invalidPayloadPhase
        }
        guard context.roster.controlIdentities.contains(
            senderControlIdentity
        ) else {
            throw MainnetAlpha.ContractError.aggregatePublisherMismatch
        }

        switch payloadType {
        case .aggregateReservation:
            let reservation = try MainnetAlpha.CanonicalWireCodec
                .decodeAggregateReservation(from: payload)
            try Self.validatePublisher(
                senderControlIdentity,
                for: reservation.aggregateKind,
                phase: phase,
                roster: context.roster
            )
            return .aggregateReservation(
                .init(
                    sender: senderControlIdentity,
                    phase: phase,
                    reservationSequence: sequence,
                    reservation: reservation
                )
            )

        case .aggregateFragment:
            guard let active = context.activeReservation,
                  active.sender == senderControlIdentity,
                  active.phase == phase else {
                throw MainnetAlpha.ContractError.missingAggregateReservation
            }
            let fragment = try MainnetAlpha.CanonicalWireCodec
                .decodeAggregateFragment(
                    from: payload,
                    reservation: active.reservation
                )
            guard fragment.reservationSequence
                    == active.reservationSequence,
                  sequence == active.reservationSequence
                    + UInt64(fragment.fragmentIndex) + 1 else {
                throw MainnetAlpha.ContractError.missingAggregateReservation
            }
            return .aggregateFragment(fragment)

        case .preSignAcknowledgement:
            guard phase == .transcriptAgreement,
                  context.roster.contributors.contains(
                    senderControlIdentity
                  ) else {
                throw MainnetAlpha.ContractError.aggregatePublisherMismatch
            }
            let submission = try MainnetAlpha.CanonicalWireCodec
                .decodePreSignAcknowledgementSubmission(
                    from: payload,
                    contributor: senderControlIdentity
                )
            guard submission.acknowledgement.roundIdentifier
                == roundIdentifier else {
                throw MainnetAlpha.ContractError.aggregateRoundMismatch
            }
            return .preSignAcknowledgement(submission)
        }
    }

    private static func validatePublisher(
        _ sender: OpalFusion.Mosaic.Attempt.ControlIdentity,
        for kind: MainnetAlpha.AggregateKind,
        phase: OpalFusion.Mosaic.Attempt.Phase,
        roster: OpalFusion.Mosaic.Attempt.Roster
    ) throws {
        let expectedPhase: OpalFusion.Mosaic.Attempt.Phase
        let validPublisher: Bool
        switch kind {
        case .completeManifest:
            expectedPhase = .manifestAgreement
            validPublisher = sender == roster.conductor
        case .playerCommit:
            expectedPhase = .walletReservation
            validPublisher = roster.contributors.contains(sender)
        case .commitmentSet:
            expectedPhase = .groupedCommitment
            validPublisher = sender == roster.conductor
        case .componentSet:
            expectedPhase = .anonymousComponentSubmission
            validPublisher = sender == roster.conductor
        case .bchSignatureSet, .completeTransaction:
            expectedPhase = .bchSigning
            validPublisher = sender == roster.conductor
        }
        guard phase == expectedPhase else {
            throw MainnetAlpha.ContractError.invalidPayloadPhase
        }
        guard validPublisher else {
            throw MainnetAlpha.ContractError.aggregatePublisherMismatch
        }
    }
}

extension OpalFusion.Mosaic.OpalMainnetAlpha {
    struct AggregatePublicationContext: Sendable, Equatable {
        let roundIdentifier: [UInt8]
        let transcriptRoot: [UInt8]?
        let phase: OpalFusion.Mosaic.Attempt.Phase
        let sender: OpalFusion.Mosaic.Attempt.ControlIdentity
        let roster: OpalFusion.Mosaic.Attempt.Roster
        let expectedTranscript: OpalFusion.Mosaic.OpalV0
            .UnsignedTransactionTranscript?

        init(
            roundIdentifier: [UInt8],
            transcriptRoot: [UInt8]? = nil,
            phase: OpalFusion.Mosaic.Attempt.Phase,
            sender: OpalFusion.Mosaic.Attempt.ControlIdentity,
            roster: OpalFusion.Mosaic.Attempt.Roster,
            expectedTranscript: OpalFusion.Mosaic.OpalV0
                .UnsignedTransactionTranscript? = nil
        ) throws {
            try RoleSeedValidator.validateFixed(
                roundIdentifier,
                field: .roundIdentifier
            )
            if let transcriptRoot {
                try RoleSeedValidator.validateFixed(
                    transcriptRoot,
                    field: .transcriptRoot
                )
            }
            if let expectedTranscript {
                guard expectedTranscript.profile == .opalMainnetAlpha,
                      expectedTranscript.manifest.roundIdentifier
                        == roundIdentifier,
                      expectedTranscript.transcriptRoot.validatedBytes
                        == transcriptRoot else {
                    throw ContractError.aggregateTranscriptMismatch
                }
            }
            self.roundIdentifier = Array(roundIdentifier)
            self.transcriptRoot = transcriptRoot.map(Array.init)
            self.phase = phase
            self.sender = sender
            self.roster = roster
            self.expectedTranscript = expectedTranscript
        }
    }

    struct ValidatedAggregatePublication: Sendable, Equatable {
        let document: AggregateDocument

        init(
            document: AggregateDocument,
            context: AggregatePublicationContext
        ) throws {
            let conductor = context.roster.conductor
            switch document {
            case let .completeManifest(manifest):
                guard context.phase == .manifestAgreement,
                      context.sender == conductor,
                      manifest.binding.roundIdentifier
                        == context.roundIdentifier else {
                    throw ContractError.aggregatePublisherMismatch
                }
            case let .playerCommit(playerCommit):
                guard context.phase == .walletReservation,
                      context.roster.contributors.contains(context.sender),
                      playerCommit.contributor == context.sender else {
                    throw ContractError.aggregatePublisherMismatch
                }
                guard playerCommit.roundIdentifier
                    == context.roundIdentifier else {
                    throw ContractError.aggregateRoundMismatch
                }
            case let .commitmentSet(commitmentSet):
                guard context.phase == .groupedCommitment,
                      context.sender == conductor,
                      commitmentSet.profile == .opalMainnetAlpha else {
                    throw ContractError.aggregatePublisherMismatch
                }
            case let .componentSet(componentSet):
                guard context.phase == .anonymousComponentSubmission,
                      context.sender == conductor,
                      componentSet.profile == .opalMainnetAlpha else {
                    throw ContractError.aggregatePublisherMismatch
                }
            case let .bchSignatureSet(signatureSet):
                guard context.phase == .bchSigning,
                      context.sender == conductor else {
                    throw ContractError.aggregatePublisherMismatch
                }
                guard signatureSet.roundIdentifier
                    == context.roundIdentifier else {
                    throw ContractError.aggregateRoundMismatch
                }
                guard signatureSet.transcriptRoot
                    == context.transcriptRoot else {
                    throw ContractError.aggregateTranscriptMismatch
                }
            case let .completeTransaction(payload):
                guard context.phase == .bchSigning,
                      context.sender == conductor else {
                    throw ContractError.aggregatePublisherMismatch
                }
                guard payload.roundIdentifier
                    == context.roundIdentifier else {
                    throw ContractError.aggregateRoundMismatch
                }
                guard payload.transcriptRoot
                    == context.transcriptRoot else {
                    throw ContractError.aggregateTranscriptMismatch
                }
                guard let expectedTranscript = context.expectedTranscript else {
                    throw ContractError.missingCompleteTransactionTranscript
                }
                guard payload.matches(transcript: expectedTranscript) else {
                    throw ContractError.transactionMismatch
                }
            }
            self.document = document
        }
    }

    protocol AnonymousComponentAdmissionValidating: Sendable {
        func validateComponentAdmission(
            senderCommunicationPublicKey: [UInt8],
            payload: OpalFusion.Mosaic.OpalV0.AnonymousComponentPayload
        ) throws
    }

    struct AnonymousComponentAdmissionValidation: Sendable, Equatable {
        let senderCommunicationPublicKey: [UInt8]
        let payload: OpalFusion.Mosaic.OpalV0.AnonymousComponentPayload
        let authorizationSpentIdentifier: [UInt8]

        init<Validator: AnonymousComponentAdmissionValidating>(
            envelope: AnonymousEnvelope,
            roundIdentifier: [UInt8],
            authenticatedOuterEventIdentity: [UInt8],
            expectedRecipientEventIdentity: [UInt8],
            currentUnixSeconds: UInt64,
            blindSigningVerificationKey: OpalCrypto.RSABSSA.VerificationKey,
            using validator: Validator
        ) throws {
            try RoleSeedValidator.validateFixed(
                authenticatedOuterEventIdentity,
                field: .senderEventIdentity
            )
            try RoleSeedValidator.validateFixed(
                expectedRecipientEventIdentity,
                field: .recipientEventIdentity
            )
            try envelope.validateOuterEventIdentity(
                authenticatedOuterEventIdentity
            )
            guard envelope.recipientEventIdentity
                == expectedRecipientEventIdentity else {
                throw ContractError.recipientEventIdentityMismatch
            }
            guard envelope.expiryUnixSeconds >= currentUnixSeconds else {
                throw ContractError.expiredEnvelope(
                    expiryUnixSeconds: envelope.expiryUnixSeconds,
                    currentUnixSeconds: currentUnixSeconds
                )
            }
            guard envelope.payloadType == .anonymousComponent else {
                throw ContractError.unsupportedAnonymousPayloadType(
                    envelope.payloadType
                )
            }
            guard envelope.phase == .anonymousComponentSubmission,
                  envelope.roundIdentifier == roundIdentifier else {
                throw ContractError.anonymousComponentRoundMismatch
            }
            let payload = try OpalFusion.Mosaic.OpalV0.CanonicalWireCodec
                .decodeAnonymousComponent(
                    from: envelope.payload,
                    profile: .opalMainnetAlpha
                )
            guard payload.roundIdentifier == roundIdentifier,
                  payload.authorizationToken.input.profile
                    == .opalMainnetAlpha,
                  payload.authorizationToken.verify(
                    using: blindSigningVerificationKey
                  ) else {
                throw ContractError.invalidAuthorizationToken
            }
            do {
                try validator.validateComponentAdmission(
                    senderCommunicationPublicKey:
                        envelope.senderCommunicationPublicKey,
                    payload: payload
                )
            } catch {
                throw ContractError.anonymousComponentAdmissionRejected
            }
            self.senderCommunicationPublicKey =
                envelope.senderCommunicationPublicKey
            self.payload = payload
            self.authorizationSpentIdentifier =
                payload.authorizationToken.spentIdentifier
        }
    }
}

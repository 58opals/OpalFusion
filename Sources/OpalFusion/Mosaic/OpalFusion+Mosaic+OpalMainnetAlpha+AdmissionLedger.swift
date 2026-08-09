// OpalFusion+Mosaic+OpalMainnetAlpha+AdmissionLedger.swift

extension OpalFusion.Mosaic.OpalMainnetAlpha {
    /// A deterministic admission-only ledger for one mainnet-alpha attempt.
    ///
    /// The ledger authenticates no transport and performs no wallet work. Its phase can advance
    /// only to the immediate successor after an owning reducer has independently authorized that
    /// transition. Every roster identity starts a fresh per-round control sequence at zero.
    struct AdmissionLedger: Sendable {
        private struct ActiveAggregate: Sendable {
            let binding: AggregateReservationBinding
            var reassembler: AggregateReassembler
        }

        private struct AcceptedAnonymousComponent: Sendable {
            let messageIdentifier: OpalFusion.Mosaic.RuntimeSession
                .MessageIdentifier
            let envelope: AnonymousEnvelope
            let validation: AnonymousComponentAdmissionValidation
        }

        private let attemptIdentifier: AttemptIdentifier
        private let generationIdentifier: GenerationIdentifier
        private let localControlIdentity: ControlIdentity
        private let localRole: OpalFusion.Mosaic.Role
        private let proposalValidation: ManifestProposalValidation
        private let roster: OpalFusion.Mosaic.Attempt.Roster
        private let roundIdentifier: [UInt8]

        private(set) var state: State = .active(.manifestAgreement)
        private var nextControlSequenceBySender: [ControlIdentity: UInt64]
        private var acceptedControlDigests: [
            ControlIdentity: [UInt64: [UInt8]]
        ] = [:]
        private var activeAggregates: [ControlIdentity: ActiveAggregate] = [:]

        private var manifest: RoundManifest?
        private var playerCommits: [ControlIdentity: PlayerCommit] = [:]
        private var authorizationResponseSets: [
            ControlIdentity: AuthorizationResponseSet
        ] = [:]
        private var authorizationResponseValidation:
            AuthorizationResponseSetValidation?
        private var commitmentValidation: OpalFusion.Mosaic.Attempt
            .CommitmentSetValidation?
        private var transcript: Transcript?
        private var acknowledgements: [
            ControlIdentity: PreSignAcknowledgementSubmission
        ] = [:]
        private var acknowledgementSet: PreSignAcknowledgementSet?

        private var acceptedAnonymousComponents: [AcceptedAnonymousComponent] = []

        init(
            attemptIdentifier: AttemptIdentifier,
            generationIdentifier: GenerationIdentifier,
            localControlIdentity: ControlIdentity,
            proposalValidation: ManifestProposalValidation
        ) throws(InitializationError) {
            let roster = proposalValidation.core.roster
            guard let localMember = roster.members.first(where: {
                $0.controlIdentity == localControlIdentity
            }) else {
                throw .localControlIdentityNotInRoster(localControlIdentity)
            }
            self.attemptIdentifier = attemptIdentifier
            self.generationIdentifier = generationIdentifier
            self.localControlIdentity = localControlIdentity
            self.localRole = localMember.role
            self.proposalValidation = proposalValidation
            self.roster = roster
            self.roundIdentifier = proposalValidation.core.roundIdentifier
            self.nextControlSequenceBySender = Dictionary(
                uniqueKeysWithValues: roster.controlIdentities.map { ($0, 0) }
            )
        }

        mutating func apply(input: Input) -> [Effect] {
            if case .terminal = state {
                if case let .control(delivery) = input,
                   isExactRecordedControlDelivery(delivery) {
                    return [.exactDuplicateIgnored]
                }
                return [.inputRejected(.inputAfterTermination)]
            }

            switch input {
            case let .control(delivery):
                return receive(delivery)
            case let .authorizationResponseSetValidated(delivery):
                return receiveAuthorizationResponseValidation(delivery)
            case .cancel:
                let phase = currentPhase
                return terminate(with: .cancelled(during: phase))
            case .retryRequested:
                return terminate(with: .failed(.inPlaceRetryNotPermitted))
            }
        }

        func phaseTransitionRequest(
            to nextContext: PhaseContext
        ) -> PhaseTransitionRequest? {
            guard case let .active(currentContext) = state else {
                return nil
            }
            return .init(
                attemptIdentifier: attemptIdentifier,
                generationIdentifier: generationIdentifier,
                from: currentContext,
                to: nextContext
            )
        }

        /// Synchronizes one transition that an owning reducer or local host path validated.
        mutating func synchronize(
            using validation: PhaseTransitionValidation
        ) -> [Effect] {
            guard case let .active(currentContext) = state else {
                return [.inputRejected(.inputAfterTermination)]
            }
            let request = validation.request
            guard request.attemptIdentifier == attemptIdentifier else {
                return [.inputRejected(.attemptIdentifierMismatch)]
            }
            guard request.generationIdentifier == generationIdentifier else {
                return [.inputRejected(.generationIdentifierMismatch)]
            }
            guard request.from == currentContext else {
                return terminate(
                    with: .failed(.phaseTransitionValidationMismatch)
                )
            }
            guard activeAggregates.isEmpty else {
                return terminate(
                    with: .failed(.activeAggregateRunPreventsPhaseAdvance)
                )
            }
            let currentPhase = currentContext.phase
            let nextContext = request.to
            let nextPhase = nextContext.phase
            guard nextPhase.rawValue == currentPhase.rawValue + 1 else {
                return terminate(
                    with: .failed(
                        .invalidPhaseTransition(from: currentPhase, to: nextPhase)
                    )
                )
            }
            guard nextPhase != .bchSigning else {
                return terminate(with: .failed(.bchSigningAdmissionUnavailable))
            }
            guard phaseAdvancePrerequisiteIsSatisfied(nextContext) else {
                return terminate(
                    with: .failed(.phaseAdvancePrerequisiteMissing(nextPhase))
                )
            }
            state = .active(nextContext)
            return [.phaseAdvanced(nextContext)]
        }

        mutating func receiveAnonymousComponent<Validator>(
            _ delivery: AnonymousComponentDelivery,
            using validator: Validator
        ) -> [Effect] where Validator: AnonymousComponentAdmissionValidating {
            if case .terminal = state {
                if isExactRecordedAnonymousDelivery(delivery) {
                    return [.exactDuplicateIgnored]
                }
                return [.inputRejected(.inputAfterTermination)]
            }
            guard delivery.attemptIdentifier == attemptIdentifier else {
                return [.inputRejected(.attemptIdentifierMismatch)]
            }
            guard delivery.generationIdentifier == generationIdentifier else {
                return [.inputRejected(.generationIdentifierMismatch)]
            }
            if let accepted = acceptedAnonymousComponents.first(where: {
                $0.messageIdentifier == delivery.authenticatedMessageIdentifier
            }) {
                guard accepted.envelope == delivery.envelope,
                      Array(delivery.envelope.senderCommunicationPublicKey.dropFirst())
                        == delivery.authenticatedOuterEventIdentity,
                      delivery.envelope.recipientEventIdentity
                        == delivery.authenticatedRecipientEventIdentity else {
                    return terminate(with: .failed(.anonymousMessageConflict))
                }
                return [.exactDuplicateIgnored]
            }
            guard delivery.envelope.payloadType == .anonymousComponent else {
                return [.inputRejected(.unsupportedAnonymousBCHSignature)]
            }
            guard currentPhase == .anonymousComponentSubmission,
                  localRole == .conductor,
                  let manifest else {
                return [.inputRejected(.anonymousComponentAdmissionUnavailable)]
            }
            let validation: AnonymousComponentAdmissionValidation
            do {
                validation = try .init(
                    envelope: delivery.envelope,
                    roundIdentifier: roundIdentifier,
                    authenticatedOuterEventIdentity:
                        delivery.authenticatedOuterEventIdentity,
                    expectedRecipientEventIdentity:
                        delivery.authenticatedRecipientEventIdentity,
                    currentUnixSeconds: delivery.currentUnixSeconds,
                    blindSigningVerificationKey:
                        manifest.core.blindSigningVerificationKey,
                    using: validator
                )
            } catch let error as ContractError {
                return [.inputRejected(.anonymousComponentAdmissionRejected(error))]
            } catch {
                return [
                    .inputRejected(
                        .anonymousComponentAdmissionRejected(
                            .anonymousComponentAdmissionRejected
                        )
                    )
                ]
            }

            guard !acceptedAnonymousComponents.contains(where: {
                $0.validation.authorizationSpentIdentifier
                    == validation.authorizationSpentIdentifier
            }) else {
                return terminate(with: .failed(.anonymousAuthorizationConflict))
            }
            guard !acceptedAnonymousComponents.contains(where: {
                $0.validation.senderCommunicationPublicKey
                    == validation.senderCommunicationPublicKey
            }) else {
                return terminate(with: .failed(.anonymousCommunicationKeyReuse))
            }
            guard !acceptedAnonymousComponents.contains(where: {
                $0.envelope.recipientEventIdentity
                    == delivery.authenticatedRecipientEventIdentity
            }) else {
                return terminate(with: .failed(.anonymousRecipientIdentityReuse))
            }
            guard acceptedAnonymousComponents.count
                < expectedAnonymousComponentCount else {
                return terminate(with: .failed(.anonymousComponentLimitExceeded))
            }

            acceptedAnonymousComponents.append(
                .init(
                    messageIdentifier: delivery.authenticatedMessageIdentifier,
                    envelope: delivery.envelope,
                    validation: validation
                )
            )
            return [.anonymousComponentAdmitted(validation)]
        }

        private var currentContext: PhaseContext {
            guard case let .active(context) = state else {
                preconditionFailure("A terminal admission ledger has no active context.")
            }
            return context
        }

        private var currentPhase: OpalFusion.Mosaic.Attempt.Phase {
            currentContext.phase
        }

        private var expectedAnonymousComponentCount: Int {
            roster.contributors.count
                * OpalFusion.Mosaic.OpalMainnetAlpha.componentCountPerContributor
        }

        private mutating func receive(_ delivery: ControlDelivery) -> [Effect] {
            guard delivery.attemptIdentifier == attemptIdentifier else {
                return [.inputRejected(.attemptIdentifierMismatch)]
            }
            guard delivery.generationIdentifier == generationIdentifier else {
                return [.inputRejected(.generationIdentifierMismatch)]
            }
            let envelope = delivery.envelope
            guard envelope.roundIdentifier == roundIdentifier else {
                return [.inputRejected(.foreignRound)]
            }
            guard roster.controlIdentities.contains(
                envelope.senderControlIdentity
            ) else {
                return [.inputRejected(.senderNotInRoster)]
            }
            guard envelope.senderEventIdentity
                == delivery.authenticatedOuterEventIdentity else {
                return [.inputRejected(.outerEventIdentityMismatch)]
            }
            let sender = envelope.senderControlIdentity
            if let acceptedDigest = acceptedControlDigests[sender]?[envelope.sequence] {
                guard acceptedDigest == envelope.messageDigest else {
                    return terminate(
                        with: .failed(
                            .sequenceConflict(
                                sender: sender,
                                sequence: envelope.sequence
                            )
                        )
                    )
                }
                return [.exactDuplicateIgnored]
            }
            guard envelope.expiryUnixSeconds >= delivery.currentUnixSeconds else {
                return [.inputRejected(.expiredEnvelope)]
            }
            guard let expectedSequence = nextControlSequenceBySender[sender] else {
                return [.inputRejected(.senderNotInRoster)]
            }
            guard envelope.sequence == expectedSequence else {
                return terminate(
                    with: .failed(
                        .sequenceGap(
                            expected: expectedSequence,
                            received: envelope.sequence
                        )
                    )
                )
            }
            guard expectedSequence != UInt64.max else {
                return terminate(with: .failed(.sequenceExhausted(sender: sender)))
            }
            if activeAggregates[sender] != nil,
               envelope.payloadType != .aggregateFragment {
                return terminate(
                    with: .failed(.aggregateInterleaving(sender: sender))
                )
            }

            let admittedPayload: AdmittedControlPayload
            do {
                admittedPayload = try envelope.admit(
                    against: .init(
                        roundIdentifier: roundIdentifier,
                        phase: currentPhase,
                        roster: roster,
                        authenticatedOuterEventIdentity:
                            delivery.authenticatedOuterEventIdentity,
                        currentUnixSeconds: delivery.currentUnixSeconds,
                        activeReservation:
                            activeAggregates[sender]?.binding
                    )
                )
            } catch let error as ContractError {
                return terminate(with: .failed(.invalidControlEnvelope(error)))
            } catch {
                return terminate(
                    with: .failed(
                        .invalidControlEnvelope(.invalidPayloadPhase)
                    )
                )
            }

            acceptedControlDigests[sender, default: [:]][envelope.sequence]
                = envelope.messageDigest
            nextControlSequenceBySender[sender] = expectedSequence + 1

            switch admittedPayload {
            case let .aggregateReservation(binding):
                return beginAggregate(binding)
            case let .aggregateFragment(fragment):
                return receiveAggregateFragment(
                    fragment,
                    sender: sender,
                    controlSequence: envelope.sequence
                )
            case let .preSignAcknowledgement(submission):
                return receivePreSignAcknowledgement(submission)
            }
        }

        private mutating func beginAggregate(
            _ binding: AggregateReservationBinding
        ) -> [Effect] {
            guard activeAggregates[binding.sender] == nil else {
                return terminate(
                    with: .failed(.aggregateInterleaving(sender: binding.sender))
                )
            }
            let decodingContext: AggregateDecodingContext
            do {
                decodingContext = try aggregateDecodingContext(
                    for: binding.reservation.aggregateKind
                )
                activeAggregates[binding.sender] = try .init(
                    binding: binding,
                    reassembler: .init(
                        reservationSequence: binding.reservationSequence,
                        reservation: binding.reservation,
                        decodingContext: decodingContext
                    )
                )
            } catch let failure as Failure {
                return terminate(with: .failed(failure))
            } catch let error as ContractError {
                return terminate(with: .failed(.invalidControlEnvelope(error)))
            } catch {
                return terminate(
                    with: .failed(
                        .invalidControlEnvelope(.invalidPayloadPhase)
                    )
                )
            }
            return [
                .aggregateReservationAccepted(
                    sender: binding.sender,
                    kind: binding.reservation.aggregateKind,
                    fragmentCount: binding.reservation.fragmentCount
                )
            ]
        }

        private mutating func receiveAggregateFragment(
            _ fragment: AggregateFragment,
            sender: ControlIdentity,
            controlSequence: UInt64
        ) -> [Effect] {
            guard var active = activeAggregates[sender] else {
                return terminate(
                    with: .failed(
                        .invalidControlEnvelope(.missingAggregateReservation)
                    )
                )
            }
            switch active.reassembler.receive(
                fragment,
                at: controlSequence
            ) {
            case let .accepted(received, expected):
                activeAggregates[sender] = active
                return [
                    .aggregateFragmentAccepted(
                        sender: sender,
                        received: received,
                        expected: expected
                    )
                ]
            case .exactDuplicate:
                activeAggregates[sender] = active
                return [.exactDuplicateIgnored]
            case let .completed(document):
                activeAggregates.removeValue(forKey: sender)
                return admitCompletedDocument(document, sender: sender)
            case let .terminated(error):
                activeAggregates.removeValue(forKey: sender)
                return terminate(with: .failed(.aggregateReassemblyFailed(error)))
            case .inputAfterTermination:
                activeAggregates.removeValue(forKey: sender)
                return terminate(
                    with: .failed(
                        .aggregateReassemblyFailed(.missingAggregateReservation)
                    )
                )
            }
        }

        private func aggregateDecodingContext(
            for kind: AggregateKind
        ) throws -> AggregateDecodingContext {
            switch (currentPhase, kind) {
            case (.manifestAgreement, .completeManifest):
                return .manifest(proposalValidation.context)
            case (.walletReservation, .playerCommit),
                 (.walletReservation, .authorizationResponseSet),
                 (.groupedCommitment, .commitmentSet),
                 (.anonymousComponentSubmission, .componentSet):
                return .profileOnly
            case (.transcriptAgreement, .preSignAcknowledgementSet):
                return .preSignAcknowledgementSet(roster: roster)
            default:
                throw ContractError.aggregateDecodingContextMismatch(kind)
            }
        }

        private mutating func admitCompletedDocument(
            _ document: AggregateDocument,
            sender: ControlIdentity
        ) -> [Effect] {
            if case let .completeManifest(manifest) = document,
               manifest.core != proposalValidation.core {
                return terminate(with: .failed(.completeManifestCoreMismatch))
            }
            let expectedTranscript = currentContext.transcript
            let publication: ValidatedAggregatePublication
            do {
                publication = try .init(
                    document: document,
                    context: .init(
                        roundIdentifier: roundIdentifier,
                        transcriptRoot: expectedTranscript?.transcriptRoot
                            .validatedBytes,
                        phase: currentPhase,
                        sender: sender,
                        roster: roster,
                        expectedTranscript: expectedTranscript
                    )
                )
            } catch let error as ContractError {
                return terminate(with: .failed(.invalidControlEnvelope(error)))
            } catch {
                return terminate(
                    with: .failed(
                        .invalidControlEnvelope(.invalidPayloadPhase)
                    )
                )
            }

            switch publication.document {
            case let .completeManifest(manifest):
                return receiveManifest(manifest)
            case let .playerCommit(playerCommit):
                return receivePlayerCommit(playerCommit)
            case let .authorizationResponseSet(responseSet):
                return receiveAuthorizationResponseSet(responseSet)
            case let .commitmentSet(commitmentSet):
                return receiveCommitmentSet(commitmentSet)
            case let .componentSet(componentSet):
                return receiveComponentSet(componentSet)
            case let .preSignAcknowledgementSet(acknowledgementSet):
                return receivePreSignAcknowledgementSet(acknowledgementSet)
            case .bchSignatureSet, .completeTransaction:
                return terminate(with: .failed(.bchSigningAdmissionUnavailable))
            }
        }

        private mutating func receiveManifest(
            _ manifest: RoundManifest
        ) -> [Effect] {
            guard self.manifest == nil else {
                return terminate(
                    with: .failed(.conflictingDocument(.completeManifest))
                )
            }
            guard manifest.core == proposalValidation.core else {
                return terminate(with: .failed(.completeManifestCoreMismatch))
            }
            self.manifest = manifest
            return [.manifestAdmitted(manifest)]
        }

        private mutating func receivePlayerCommit(
            _ playerCommit: PlayerCommit
        ) -> [Effect] {
            guard localRole == .conductor
                || playerCommit.contributor == localControlIdentity else {
                return [.inputRejected(.playerCommitAdmissionUnavailable)]
            }
            let contributor = playerCommit.contributor
            guard playerCommits[contributor] == nil else {
                return terminate(
                    with: .failed(.conflictingDocument(.playerCommit(contributor)))
                )
            }
            playerCommits[contributor] = playerCommit
            var effects: [Effect] = [.playerCommitAdmitted(playerCommit)]
            if playerCommits.count == roster.contributors.count {
                effects.append(
                    .playerCommitUnanimityReached(sortedPlayerCommits)
                )
            }
            return effects
        }

        private mutating func receiveAuthorizationResponseSet(
            _ responseSet: AuthorizationResponseSet
        ) -> [Effect] {
            let contributor = responseSet.contributor
            guard authorizationResponseSets[contributor] == nil else {
                return terminate(
                    with: .failed(
                        .conflictingDocument(
                            .authorizationResponseSet(contributor)
                        )
                    )
                )
            }
            let playerCommit = playerCommits[contributor]
            if localRole == .conductor || contributor == localControlIdentity {
                guard let playerCommit,
                      responseSet.roundIdentifier == roundIdentifier,
                      responseSet.playerCommitDigest == playerCommit.digest else {
                    return terminate(
                        with: .failed(
                            .authorizationResponseSetPlayerCommitMismatch
                        )
                    )
                }
            }
            authorizationResponseSets[contributor] = responseSet
            var effects: [Effect] = [
                .authorizationResponseSetAdmitted(responseSet)
            ]
            if localRole == .contributor,
               contributor == localControlIdentity,
               let playerCommit {
                effects.append(
                    .authorizationResponseSetValidationRequired(
                        responseSet,
                        playerCommit: playerCommit
                    )
                )
            }
            return effects
        }

        private mutating func receiveAuthorizationResponseValidation(
            _ delivery: AuthorizationResponseValidationDelivery
        ) -> [Effect] {
            guard delivery.attemptIdentifier == attemptIdentifier else {
                return [.inputRejected(.attemptIdentifierMismatch)]
            }
            guard delivery.generationIdentifier == generationIdentifier else {
                return [.inputRejected(.generationIdentifierMismatch)]
            }
            guard currentPhase == .walletReservation,
                  localRole == .contributor,
                  authorizationResponseValidation == nil,
                  let manifest,
                  delivery.validation.verificationKeyIdentifier
                    == [UInt8](
                        manifest.core.blindSigningVerificationKey.keyIdentifier
                    ),
                  authorizationResponseSets[localControlIdentity]
                    == delivery.validation.responseSet,
                  delivery.validation.responseSet.contributor
                    == localControlIdentity else {
                return terminate(
                    with: .failed(.authorizationResponseSetValidationMismatch)
                )
            }
            authorizationResponseValidation = delivery.validation
            return [
                .authorizationResponsesValidated(
                    delivery.validation.authorizationTokens
                )
            ]
        }

        private mutating func receiveCommitmentSet(
            _ commitmentSet: OpalFusion.Mosaic.OpalV0.CommitmentSet
        ) -> [Effect] {
            guard commitmentValidation == nil else {
                return terminate(
                    with: .failed(.conflictingDocument(.commitmentSet))
                )
            }
            let validation: OpalFusion.Mosaic.Attempt.CommitmentSetValidation
            do {
                validation = try .init(
                    profile: .opalMainnetAlpha,
                    roster: roster,
                    commitmentSet: commitmentSet
                )
            } catch {
                return terminate(with: .failed(.commitmentSetInvalid(error)))
            }
            if localRole == .conductor {
                guard playerCommits.count == roster.contributors.count else {
                    return terminate(with: .failed(.playerCommitSetIncomplete))
                }
                let expectedCommitmentSet: OpalFusion.Mosaic.OpalV0.CommitmentSet
                do {
                    expectedCommitmentSet = try .init(
                        profile: .opalMainnetAlpha,
                        commitments: sortedPlayerCommits.flatMap {
                            $0.groupedCommitment.commitments
                        }
                    )
                } catch {
                    return terminate(
                        with: .failed(.commitmentSetDoesNotMatchPlayerCommits)
                    )
                }
                guard expectedCommitmentSet == commitmentSet else {
                    return terminate(
                        with: .failed(.commitmentSetDoesNotMatchPlayerCommits)
                    )
                }
            }
            commitmentValidation = validation
            return [.commitmentSetAdmitted(commitmentSet)]
        }

        private mutating func receiveComponentSet(
            _ componentSet: OpalFusion.Mosaic.OpalV0.ComponentSet
        ) -> [Effect] {
            guard transcript == nil else {
                return terminate(
                    with: .failed(.conflictingDocument(.componentSet))
                )
            }
            guard let manifest, let commitmentValidation else {
                return terminate(
                    with: .failed(
                        .phaseAdvancePrerequisiteMissing(
                            .anonymousComponentSubmission
                        )
                    )
                )
            }
            if localRole == .conductor {
                guard acceptedAnonymousComponents.count
                    == expectedAnonymousComponentCount else {
                    return terminate(with: .failed(.anonymousComponentSetIncomplete))
                }
                let expectedComponentSet: OpalFusion.Mosaic.OpalV0.ComponentSet
                do {
                    expectedComponentSet = try .init(
                        profile: .opalMainnetAlpha,
                        components: acceptedAnonymousComponents.map {
                            $0.validation.payload.component
                        }
                    )
                } catch {
                    return terminate(
                        with: .failed(.componentSetDoesNotMatchAnonymousAdmissions)
                    )
                }
                guard expectedComponentSet == componentSet else {
                    return terminate(
                        with: .failed(.componentSetDoesNotMatchAnonymousAdmissions)
                    )
                }
            }
            let transcript: Transcript
            do {
                transcript = try .init(
                    profile: .opalMainnetAlpha,
                    roster: roster,
                    manifest: manifest.binding,
                    commitmentSet: commitmentValidation,
                    componentSet: componentSet
                )
            } catch {
                return terminate(with: .failed(.unsignedTransactionInvalid(error)))
            }
            self.transcript = transcript
            return [.componentSetAdmitted(componentSet, transcript: transcript)]
        }

        private mutating func receivePreSignAcknowledgement(
            _ submission: PreSignAcknowledgementSubmission
        ) -> [Effect] {
            guard localRole == .conductor else {
                return [
                    .inputRejected(.preSignAcknowledgementAdmissionUnavailable)
                ]
            }
            guard case let .transcriptAgreement(transcript) = currentContext,
                  submission.acknowledgement.transcriptRoot
                    == transcript.transcriptRoot.validatedBytes,
                  submission.acknowledgement.roundIdentifier
                    == roundIdentifier else {
                return terminate(
                    with: .failed(.transcriptAcknowledgementMismatch)
                )
            }
            let contributor = submission.acknowledgement.contributor
            guard acknowledgements[contributor] == nil else {
                return terminate(
                    with: .failed(
                        .conflictingDocument(
                            .preSignAcknowledgement(contributor)
                        )
                    )
                )
            }
            acknowledgements[contributor] = submission
            var effects: [Effect] = [
                .preSignAcknowledgementAdmitted(submission)
            ]
            if acknowledgements.count == roster.contributors.count {
                effects.append(
                    .preSignAcknowledgementCollectionComplete(
                        sortedAcknowledgements
                    )
                )
            }
            return effects
        }

        private mutating func receivePreSignAcknowledgementSet(
            _ set: PreSignAcknowledgementSet
        ) -> [Effect] {
            guard acknowledgementSet == nil else {
                return terminate(
                    with: .failed(
                        .conflictingDocument(.preSignAcknowledgementSet)
                    )
                )
            }
            if localRole == .conductor {
                guard acknowledgements.count == roster.contributors.count,
                      set.submissions == sortedAcknowledgements else {
                    return terminate(
                        with: .failed(
                            .preSignAcknowledgementSetDoesNotMatchCollection
                        )
                    )
                }
            }
            acknowledgementSet = set
            return [.preSignAcknowledgementSetAdmitted(set)]
        }

        private func phaseAdvancePrerequisiteIsSatisfied(
            _ nextContext: PhaseContext
        ) -> Bool {
            switch nextContext {
            case .manifestAgreement:
                return false
            case .walletReservation:
                return manifest != nil
            case .groupedCommitment:
                if localRole == .conductor {
                    return playerCommits.count == roster.contributors.count
                        && authorizationResponseSets.count
                            == roster.contributors.count
                }
                return playerCommits[localControlIdentity] != nil
                    && authorizationResponseSets.count
                        == roster.contributors.count
                    && authorizationResponseSets[localControlIdentity] != nil
                    && authorizationResponseValidation != nil
            case .anonymousComponentSubmission:
                return commitmentValidation != nil
            case let .transcriptAgreement(expectedTranscript):
                return transcript == expectedTranscript
            case .bchSigning:
                return false
            }
        }

        private var sortedPlayerCommits: [PlayerCommit] {
            playerCommits.values.sorted {
                $0.contributor.validatedBytes.lexicographicallyPrecedes(
                    $1.contributor.validatedBytes
                )
            }
        }

        private var sortedAcknowledgements: [PreSignAcknowledgementSubmission] {
            acknowledgements.values.sorted {
                $0.acknowledgement.contributor.validatedBytes
                    .lexicographicallyPrecedes(
                        $1.acknowledgement.contributor.validatedBytes
                    )
            }
        }

        private func isExactRecordedControlDelivery(
            _ delivery: ControlDelivery
        ) -> Bool {
            delivery.attemptIdentifier == attemptIdentifier
                && delivery.generationIdentifier == generationIdentifier
                && delivery.envelope.roundIdentifier == roundIdentifier
                && delivery.envelope.senderEventIdentity
                    == delivery.authenticatedOuterEventIdentity
                && acceptedControlDigests[
                    delivery.envelope.senderControlIdentity
                ]?[delivery.envelope.sequence] == delivery.envelope.messageDigest
        }

        private func isExactRecordedAnonymousDelivery(
            _ delivery: AnonymousComponentDelivery
        ) -> Bool {
            delivery.attemptIdentifier == attemptIdentifier
                && delivery.generationIdentifier == generationIdentifier
                && acceptedAnonymousComponents.contains {
                    $0.messageIdentifier
                        == delivery.authenticatedMessageIdentifier
                        && $0.envelope == delivery.envelope
                }
                && Array(delivery.envelope.senderCommunicationPublicKey.dropFirst())
                    == delivery.authenticatedOuterEventIdentity
                && delivery.envelope.recipientEventIdentity
                    == delivery.authenticatedRecipientEventIdentity
        }

        private mutating func terminate(with outcome: Outcome) -> [Effect] {
            state = .terminal(outcome)
            activeAggregates.removeAll(keepingCapacity: false)
            return [.attemptTerminated(outcome)]
        }
    }
}

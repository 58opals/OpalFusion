// OpalFusion+MosaicPrivateAlphaRuntime+PostManifestExecution.swift

#if os(macOS)
import Foundation

extension OpalFusion.MosaicPrivateAlphaRuntime {
    /// Owns the existing proof-bound relay fan-in, ingress, role coordinator, and outbound drain.
    @_spi(MosaicPrivateAlpha)
    public actor PostManifestExecution {
        typealias FanIn = OpalFusion.Mosaic.OpalMainnetAlpha
            .PostManifestRelayFanIn
        typealias Journal = OpalFusion.Mosaic.OpalMainnetAlpha
            .PostManifestRelayPublicationJournal

        private let binding: Binding
        private let fanIn: FanIn
        private let publicationJournal: Journal
        private let privateManifest: OpalFusion.Mosaic.OpalMainnetAlpha
            .PrivateDeploymentManifestValidation
        private let completeManifest: OpalFusion.Mosaic.OpalMainnetAlpha
            .RoundManifest
        private let localControlIdentity: OpalFusion.Mosaic.Attempt
            .ControlIdentity
        private let loadAdmissionReadback: @Sendable () throws -> Data
        private let loadPublicationReadback: @Sendable () throws -> Data
        private let stopOutbound: @Sendable () async -> Void
        private let waitForOutboundDrain: @Sendable () async -> Bool
        private let terminalPersistence: PostManifestTerminalPersistence
        private let recoveredTerminalEvidence: PostManifestTerminalEvidence?
        private var terminationWasClaimed = false
        private var terminalRecord: PostManifestTerminalRecord?

        init(
            binding: Binding,
            fanIn: FanIn,
            publicationJournal: Journal,
            privateManifest: OpalFusion.Mosaic.OpalMainnetAlpha
                .PrivateDeploymentManifestValidation,
            completeManifest: OpalFusion.Mosaic.OpalMainnetAlpha.RoundManifest,
            localControlIdentity: OpalFusion.Mosaic.Attempt.ControlIdentity,
            recoveredTerminalEvidence: PostManifestTerminalEvidence?,
            loadAdmissionReadback: @escaping @Sendable () throws -> Data,
            loadPublicationReadback: @escaping @Sendable () throws -> Data,
            terminalPersistence: PostManifestTerminalPersistence,
            stopOutbound: @escaping @Sendable () async -> Void,
            waitForOutboundDrain: @escaping @Sendable () async -> Bool
        ) {
            self.binding = binding
            self.fanIn = fanIn
            self.publicationJournal = publicationJournal
            self.privateManifest = privateManifest
            self.completeManifest = completeManifest
            self.localControlIdentity = localControlIdentity
            self.recoveredTerminalEvidence = recoveredTerminalEvidence
            self.loadAdmissionReadback = loadAdmissionReadback
            self.loadPublicationReadback = loadPublicationReadback
            self.terminalPersistence = terminalPersistence
            self.stopOutbound = stopOutbound
            self.waitForOutboundDrain = waitForOutboundDrain
        }

        @_spi(MosaicPrivateAlpha)
        public func start() async throws {
            if let bytes = try terminalPersistence.load(binding) {
                let record = try PostManifestTerminalRecord.decode(
                    bytes,
                    expectedBinding: binding
                )
                if let recoveredTerminalEvidence {
                    guard recoveredTerminalEvidence.wasReceived
                            == record.wasReceived,
                          recoveredTerminalEvidence.event == record.event else {
                        throw Failure.contradictoryRecoverySnapshot
                    }
                }
                switch record {
                case .abort:
                    let abort = try validateTerminalAbortRecord(record)
                    guard case let .abort(_, phase, _, _) = record else {
                        throw Failure.malformedRecoverySnapshot
                    }
                    try await fanIn.start(recoveredAbort: (
                        phase,
                        abort.reason
                    ))
                case .completion:
                    try await fanIn.start(
                        expectRecoveredCompletion: true
                    )
                    guard let validation = await fanIn
                        .terminalCompletionValidation() else {
                        throw Failure.invalidStateTransition
                    }
                    try record.validateCompletion(.init(
                        manifest: privateManifest,
                        roundManifest: completeManifest,
                        completeTransactionValidation: validation
                    ))
                }
                terminalRecord = record
            } else if let recoveredTerminalEvidence {
                guard !recoveredTerminalEvidence.wasReceived else {
                    throw Failure.terminalEvidenceUnavailable
                }
                switch recoveredTerminalEvidence.reason {
                case .aborted:
                    let recoveredAbort = try validateRecoveredLocalAbort(
                        recoveredTerminalEvidence.event
                    )
                    guard recoveredAbort.reason != .timeout else {
                        // A locally produced timeout is signed and persisted
                        // before coordinator application. Evidence without
                        // that exact companion record is therefore partial.
                        throw Failure.terminalEvidenceUnavailable
                    }
                    try await fanIn.start(recoveredAbort: recoveredAbort)
                case .completed:
                    guard localControlIdentity
                            == completeManifest.core.roster.conductor else {
                        throw Failure.contradictoryRecoverySnapshot
                    }
                    try await fanIn.start(expectRecoveredCompletion: true)
                    guard let completion = await fanIn
                        .terminalCompletionValidation() else {
                        throw Failure.invalidStateTransition
                    }
                    let validation = try OpalFusion.Mosaic.OpalMainnetAlpha
                        .PrivateDeploymentCompletionValidation(
                            manifest: privateManifest,
                            roundManifest: completeManifest,
                            completeTransactionValidation: completion
                        )
                    let event = try recoveredTerminalEvidence.event
                        .decodeCanonicalNostrEvent()
                    _ = try OpalFusion.Mosaic.OpalMainnetAlpha
                        .PreManifestNostrCodec.decodeCompletion(
                            event,
                            validation: validation,
                            currentUnixSeconds: recoveredTerminalEvidence
                                .event.acceptedAtUnixSeconds
                        )
                }
            } else {
                try await fanIn.start()
            }
        }

        private func validateRecoveredLocalAbort(
            _ storedEvent: PrivateDeploymentEvent
        ) throws -> (
            phase: OpalFusion.Mosaic.Attempt.Phase,
            reason: OpalFusion.Mosaic.Attempt.AbortReason
        ) {
            let event = try storedEvent.decodeCanonicalNostrEvent()
            guard event.publicKey.rawRepresentation
                    == Data(localControlIdentity.validatedBytes) else {
                throw Failure.contradictoryRecoverySnapshot
            }
            let phases: [OpalFusion.Mosaic.Attempt.Phase] = [
                .walletReservation,
                .groupedCommitment,
                .anonymousComponentSubmission,
                .transcriptAgreement,
                .bchSigning,
            ]
            var matches: [(
                OpalFusion.Mosaic.Attempt.Phase,
                OpalFusion.Mosaic.Attempt.AbortReason
            )] = []
            for phase in phases {
                guard let authority = try? OpalFusion.Mosaic
                    .OpalMainnetAlpha.PrivateDeploymentAbortAuthority
                    .makePostManifestAuthority(
                        phase: phase,
                        participant: localControlIdentity,
                        manifest: privateManifest,
                        roundManifest: completeManifest
                    ), let document = try? OpalFusion.Mosaic
                    .OpalMainnetAlpha.PreManifestNostrCodec.decodeAbort(
                        event,
                        authority: authority,
                        currentUnixSeconds: storedEvent.acceptedAtUnixSeconds
                    ) else {
                    continue
                }
                matches.append((phase, document.reason))
            }
            guard matches.count == 1, let match = matches.first else {
                throw Failure.contradictoryRecoverySnapshot
            }
            return (match.0, match.1)
        }

        /// Validates and durably records one roster-signed abort before coordinator admission.
        @_spi(MosaicPrivateAlpha)
        public func acceptReceivedAbort(
            _ event: PrivateDeploymentEvent
        ) async throws {
            guard terminalRecord == nil else {
                throw Failure.invalidStateTransition
            }
            let binding = binding
            let persistence = terminalPersistence
            let manifest = privateManifest
            let roundManifest = completeManifest
            guard await fanIn.submitOrderedAuthenticatedAbort(
                deriving: { phase in
                    let validated = try PostManifestTerminalRecord
                        .abort(
                        binding: binding,
                        phase: phase,
                        event: event,
                        wasReceived: true,
                        manifest: manifest,
                        roundManifest: roundManifest
                    )
                    guard try persistence.load(binding) == nil else {
                        throw Failure.invalidStateTransition
                    }
                    let replacement = try validated.record.canonicalBytes()
                    let readback = try persistence.compareAndSwap(
                        binding,
                        nil,
                        replacement
                    )
                    guard readback == replacement,
                          try PostManifestTerminalRecord.decode(
                            readback,
                            expectedBinding: binding
                          ) == validated.record else {
                        throw Failure.exactReadbackMismatch
                    }
                    return validated.reason
                }
            ) else {
                throw Failure.invalidStateTransition
            }
            guard let readback = try terminalPersistence.load(binding) else {
                throw Failure.exactReadbackMismatch
            }
            terminalRecord = try PostManifestTerminalRecord.decode(
                readback,
                expectedBinding: binding
            )
        }

        /// Persists an exact conductor-signed completion only after runtime transaction proof.
        @_spi(MosaicPrivateAlpha)
        public func acceptReceivedCompletion(
            _ event: PrivateDeploymentEvent
        ) async throws {
            guard terminalRecord == nil,
                  localControlIdentity
                    != completeManifest.core.roster.conductor,
                  let completed = await fanIn
                    .terminalCompletionValidation() else {
                throw Failure.invalidStateTransition
            }
            let validation = try OpalFusion.Mosaic.OpalMainnetAlpha
                .PrivateDeploymentCompletionValidation(
                    manifest: privateManifest,
                    roundManifest: completeManifest,
                    completeTransactionValidation: completed
                )
            let record = try PostManifestTerminalRecord.completion(
                binding: binding,
                event: event,
                validation: validation
            )
            guard try terminalPersistence.load(binding) == nil else {
                throw Failure.invalidStateTransition
            }
            let replacement = try record.canonicalBytes()
            let readback = try terminalPersistence.compareAndSwap(
                binding,
                nil,
                replacement
            )
            guard readback == replacement,
                  try PostManifestTerminalRecord.decode(
                    readback,
                    expectedBinding: binding
                  ) == record else {
                throw Failure.exactReadbackMismatch
            }
            try record.validateCompletion(validation)
            terminalRecord = record
        }

        /// Freezes intake and derives a timeout abort from the exact queued runtime phase.
        @_spi(MosaicPrivateAlpha)
        public func requestTimeoutAbort(
            currentUnixSeconds: UInt64,
            signing: consuming PrivateDeploymentSigningCapability
        ) async throws {
            guard terminalRecord == nil,
                  signing.verificationKey.rawRepresentation
                    == Data(localControlIdentity.validatedBytes),
                  let observedPhase = await fanIn.currentPhase() else {
                throw Failure.invalidStateTransition
            }
            let deadlines = completeManifest.core.deadlines
            let boundary = try Self.timeoutBoundary(
                for: observedPhase,
                deadlines: deadlines
            )
            guard currentUnixSeconds >= boundary,
                  currentUnixSeconds <= deadlines.bchSigning else {
                throw Failure.invalidStateTransition
            }
            let authority = try OpalFusion.Mosaic.OpalMainnetAlpha
                .PrivateDeploymentAbortAuthority
                .makePostManifestAuthority(
                    phase: observedPhase,
                    participant: localControlIdentity,
                    manifest: privateManifest,
                    roundManifest: completeManifest
                )
            let payload = try OpalFusion.Mosaic.OpalMainnetAlpha
                .PreManifestNostrPayloadDocument.makeAbort(
                    .init(
                        discoveryEpochStartUnixSeconds:
                            authority.discoveryEpochStartUnixSeconds,
                        phase: authority.phase,
                        context: authority.context,
                        reason: .timeout
                    ),
                    authority: authority
                )
            let event = try PrivateDeploymentEvent.makeLocal(
                payload: payload,
                createdAtUnixSeconds: currentUnixSeconds,
                signing: signing
            )
            let validated = try PostManifestTerminalRecord.abort(
                binding: binding,
                phase: observedPhase,
                event: event,
                wasReceived: false,
                manifest: privateManifest,
                roundManifest: completeManifest
            )
            guard validated.reason == .timeout else {
                throw Failure.invalidStateTransition
            }
            let binding = binding
            let persistence = terminalPersistence
            let record = validated.record
            guard await fanIn.submitOrderedAuthenticatedAbort(
                deriving: { phase in
                    guard phase == observedPhase,
                          try persistence.load(binding) == nil else {
                        throw Failure.invalidStateTransition
                    }
                    let replacement = try record.canonicalBytes()
                    let readback = try persistence.compareAndSwap(
                        binding,
                        nil,
                        replacement
                    )
                    guard readback == replacement,
                          try PostManifestTerminalRecord.decode(
                            readback,
                            expectedBinding: binding
                          ) == record else {
                        throw Failure.exactReadbackMismatch
                    }
                    return .timeout
                }
            ) else {
                throw Failure.invalidStateTransition
            }
            guard let readback = try terminalPersistence.load(binding),
                  try PostManifestTerminalRecord.decode(
                    readback,
                    expectedBinding: binding
                  ) == record else {
                throw Failure.exactReadbackMismatch
            }
            terminalRecord = record
        }

        @_spi(MosaicPrivateAlpha)
        public func stop() async {
            await fanIn.stop()
            await stopOutbound()
        }

        /// Claims exactly one package-derived runtime disposition after exact durable readback.
        @_spi(MosaicPrivateAlpha)
        public func waitForTermination() async throws
            -> PostManifestTermination? {
            guard !terminationWasClaimed else {
                return nil
            }
            // Claim before the first suspension so actor reentrancy cannot
            // admit a second concurrent terminal owner. A failed or partial
            // claim intentionally requires a newly loaded recovery owner.
            terminationWasClaimed = true
            guard let termination = await fanIn.waitForTermination() else {
                return nil
            }

            var mapped = Self.map(termination)
            if case .runtime = termination,
               let abort = await fanIn.terminalProtocolAbort() {
                mapped = (
                    .aborted,
                    mapped.reference,
                    abort.phase,
                    abort.reason
                )
            }
            await stopOutbound()
            let outboundBridgeDrained = await waitForOutboundDrain()
            let outboundIsDrained = outboundBridgeDrained
                && publicationJournal.isDrained

            // Never substitute empty data for an absent, unreadable, or invalid snapshot.
            let admissionReadback = try loadAdmissionReadback()
            let publicationReadback = try loadPublicationReadback()
            let admissionDigest = RecoveryState.sha256(admissionReadback)
            let publicationDigest = RecoveryState.sha256(publicationReadback)
            let authority = try await makeAuthority(
                kind: mapped.kind,
                phase: mapped.phase,
                abortReason: mapped.abortReason
            )
            let receivedTerminalEvent = terminalRecord?.wasReceived == true
                ? terminalRecord?.event
                : nil
            let localTerminalEvent: PrivateDeploymentEvent?
            if terminalRecord?.wasReceived == false {
                localTerminalEvent = terminalRecord?.event
            } else if let recoveredTerminalEvidence,
                      !recoveredTerminalEvidence.wasReceived {
                localTerminalEvent = recoveredTerminalEvidence.event
            } else {
                localTerminalEvent = nil
            }
            let identity = try Self.makeTerminalIdentity(
                binding: binding,
                kind: mapped.kind,
                authority: authority,
                admissionSnapshotDigest: admissionDigest,
                publicationSnapshotDigest: publicationDigest,
                receivedTerminalEvent: receivedTerminalEvent
            )
            return .init(
                binding: binding,
                kind: mapped.kind,
                reservationReference: mapped.reference,
                terminalIdentity: identity,
                localControlIdentity: Data(
                    localControlIdentity.validatedBytes
                ),
                admissionSnapshotDigest: admissionDigest,
                publicationSnapshotDigest: publicationDigest,
                authority: authority,
                outboundIsDrained: outboundIsDrained,
                isLocalConductor:
                    localControlIdentity
                        == completeManifest.core.roster.conductor,
                receivedTerminalEvent: receivedTerminalEvent,
                localTerminalEvent: localTerminalEvent
            )
        }

        private func makeAuthority(
            kind: PostManifestExecutionOutcomeKind,
            phase: OpalFusion.Mosaic.Attempt.Phase?,
            abortReason: OpalFusion.Mosaic.Attempt.AbortReason? = nil
        ) async throws -> PostManifestTerminalAuthority {
            switch kind {
            case .completed:
                guard let validation = await fanIn
                    .terminalCompletionValidation() else {
                    return .unavailable
                }
                let completion = try OpalFusion.Mosaic.OpalMainnetAlpha
                    .PrivateDeploymentCompletionValidation(
                    manifest: privateManifest,
                    roundManifest: completeManifest,
                    completeTransactionValidation: validation
                )
                if let terminalRecord {
                    guard terminalRecord.wasReceived,
                          case .completion = terminalRecord else {
                        return .unavailable
                    }
                    try terminalRecord.validateCompletion(completion)
                }
                return .completion(completion)
            case .aborted:
                if let terminalRecord {
                    guard case let .abort(
                        _,
                        receivedPhase,
                        _,
                        _
                    ) = terminalRecord,
                          receivedPhase == phase else {
                        return .unavailable
                    }
                    let validated = try validateTerminalAbortRecord(
                        terminalRecord
                    )
                    guard validated.reason == abortReason else {
                        return .unavailable
                    }
                    return .abort(
                        validated.authority,
                        reason: validated.reason
                    )
                }
                guard let phase, let abortReason else { return .unavailable }
                return .abort(
                    try .makePostManifestAuthority(
                        phase: phase,
                        participant: localControlIdentity,
                        manifest: privateManifest,
                        roundManifest: completeManifest
                    ),
                    reason: abortReason
                )
            case .failed, .recoveryRequired, .transportFailed:
                return .unavailable
            }
        }

        private func validateTerminalAbortRecord(
            _ record: PostManifestTerminalRecord
        ) throws -> (
            authority: OpalFusion.Mosaic.OpalMainnetAlpha
                .PrivateDeploymentAbortAuthority,
            reason: OpalFusion.Mosaic.Attempt.AbortReason
        ) {
            let validated = try record.validateAbort(
                manifest: privateManifest,
                roundManifest: completeManifest
            )
            guard !record.wasReceived else { return validated }
            guard case let .abort(_, phase, storedEvent, false) = record,
                  validated.reason == .timeout else {
                throw Failure.contradictoryRecoverySnapshot
            }
            let event = try storedEvent.decodeCanonicalNostrEvent()
            let boundary = try Self.timeoutBoundary(
                for: phase,
                deadlines: completeManifest.core.deadlines
            )
            guard event.publicKey.rawRepresentation
                    == Data(localControlIdentity.validatedBytes),
                  event.template.createdAt
                    == storedEvent.acceptedAtUnixSeconds,
                  event.template.createdAt >= boundary,
                  event.template.createdAt
                    <= completeManifest.core.deadlines.bchSigning else {
                throw Failure.contradictoryRecoverySnapshot
            }
            return validated
        }

        static func timeoutBoundary(
            for phase: OpalFusion.Mosaic.Attempt.Phase,
            deadlines: OpalFusion.Mosaic.OpalMainnetAlpha.DeadlineSchedule
        ) throws -> UInt64 {
            switch phase {
            case .walletReservation:
                deadlines.walletReservation
            case .groupedCommitment:
                deadlines.groupedCommitment
            case .anonymousComponentSubmission:
                deadlines.anonymousComponentSubmission
            case .transcriptAgreement:
                deadlines.transcriptAgreement
            case .bchSigning:
                deadlines.bchSigning
            case .discovery, .candidateSetAgreement,
                 .controlRosterAgreement, .roleSelection,
                 .manifestAgreement:
                throw Failure.invalidStateTransition
            }
        }

        private static func map(
            _ termination: FanIn.Termination
        ) -> (
            kind: PostManifestExecutionOutcomeKind,
            reference: OpalFusion.Host.MosaicReservationReference?,
            phase: OpalFusion.Mosaic.Attempt.Phase?,
            abortReason: OpalFusion.Mosaic.Attempt.AbortReason?
        ) {
            guard case let .runtime(state) = termination else {
                return (.transportFailed, nil, nil, nil)
            }
            switch state {
            case let .contributor(state):
                switch state {
                case let .terminal(outcome):
                    switch outcome {
                    case .completed:
                        return (.completed, nil, .bchSigning, nil)
                    case .cancelled:
                        return (.failed, nil, nil, nil)
                    case let .failed(failure):
                        return Self.mapContributorFailure(failure)
                    }
                case let .recoveryRequired(recovery):
                    return (
                        .recoveryRequired,
                        recovery.reservationReference,
                        nil,
                        nil
                    )
                case .idle, .running, .stopping:
                    return (.transportFailed, nil, nil, nil)
                }
            case let .conductor(state):
                switch state {
                case let .terminal(outcome):
                    switch outcome {
                    case .completed:
                        return (.completed, nil, .bchSigning, nil)
                    case .cancelled:
                        return (.failed, nil, nil, nil)
                    case let .failed(failure):
                        return Self.mapConductorFailure(failure)
                    }
                case .idle, .running, .stopping:
                    return (.transportFailed, nil, nil, nil)
                }
            }
        }

        private static func mapContributorFailure(
            _ failure: OpalFusion.Mosaic.OpalMainnetAlpha
                .ReservationCoordinator.Failure
        ) -> (
            PostManifestExecutionOutcomeKind,
            OpalFusion.Host.MosaicReservationReference?,
            OpalFusion.Mosaic.Attempt.Phase?,
            OpalFusion.Mosaic.Attempt.AbortReason?
        ) {
            guard case let .runtime(.localAttempt(
                .aborted(phase, reason)
            )) = failure else {
                return (.failed, nil, nil, nil)
            }
            return (.aborted, nil, phase, reason)
        }

        private static func mapConductorFailure(
            _ failure: OpalFusion.Mosaic.OpalMainnetAlpha
                .ConductorCoordinator.Failure
        ) -> (
            PostManifestExecutionOutcomeKind,
            OpalFusion.Host.MosaicReservationReference?,
            OpalFusion.Mosaic.Attempt.Phase?,
            OpalFusion.Mosaic.Attempt.AbortReason?
        ) {
            guard case let .runtime(.localAttempt(
                .aborted(phase, reason)
            )) = failure else {
                return (.failed, nil, nil, nil)
            }
            return (.aborted, nil, phase, reason)
        }

        static func makeTerminalIdentity(
            binding: Binding,
            kind: PostManifestExecutionOutcomeKind,
            authority: PostManifestTerminalAuthority,
            admissionSnapshotDigest: Data,
            publicationSnapshotDigest: Data,
            receivedTerminalEvent: PrivateDeploymentEvent?
        ) throws -> Data {
            try makeTerminalIdentity(
                binding: binding,
                kind: kind,
                authorityIdentityBytes:
                    try terminalAuthorityIdentityBytes(authority),
                admissionSnapshotDigest: admissionSnapshotDigest,
                publicationSnapshotDigest: publicationSnapshotDigest,
                receivedTerminalEvent: receivedTerminalEvent
            )
        }

        static func makeTerminalIdentity(
            binding: Binding,
            kind: PostManifestExecutionOutcomeKind,
            authorityIdentityBytes: Data,
            admissionSnapshotDigest: Data,
            publicationSnapshotDigest: Data,
            receivedTerminalEvent: PrivateDeploymentEvent?
        ) throws -> Data {
            var encoder = OpalFusion.Mosaic.CanonicalEncoder()
            try encoder.writeText(
                "OpalFusion/MosaicPrivateAlpha/terminal-identity/3"
            )
            try encoder.writeFixedBytes(
                Array(binding.attemptIdentifier), byteCount: 32
            )
            try encoder.writeFixedBytes(
                Array(binding.generationIdentifier), byteCount: 32
            )
            try encoder.writeFixedBytes(
                Array(binding.materialIdentifier), byteCount: 32
            )
            switch kind {
            case .completed: encoder.writeUInt8(0)
            case .aborted: encoder.writeUInt8(1)
            case .failed: encoder.writeUInt8(2)
            case .recoveryRequired: encoder.writeUInt8(3)
            case .transportFailed: encoder.writeUInt8(4)
            }
            try encoder.writeBytes(Array(authorityIdentityBytes))
            try encoder.writeFixedBytes(
                Array(admissionSnapshotDigest), byteCount: 32
            )
            try encoder.writeFixedBytes(
                Array(publicationSnapshotDigest), byteCount: 32
            )
            try encoder.writeOptional(receivedTerminalEvent) {
                encoder,
                event in
                try encoder.writeBytes(Array(
                    try event.canonicalRecoveryBytes()
                ))
            }
            return RecoveryState.sha256(Data(encoder.encodedBytes))
        }

        static func terminalAuthorityIdentityBytes(
            _ authority: PostManifestTerminalAuthority
        ) throws -> Data {
            var encoder = OpalFusion.Mosaic.CanonicalEncoder()
            switch authority {
            case let .completion(validation):
                encoder.writeUInt8(0)
                try encoder.writeBytes(
                    OpalFusion.Mosaic.OpalMainnetAlpha
                        .PrivateDeploymentCompletionDocument(
                            validation: validation
                        ).canonicalBytes
                )
            case let .abort(authority, reason):
                encoder.writeUInt8(1)
                encoder.writeUInt64(
                    authority.discoveryEpochStartUnixSeconds
                )
                encoder.writeUInt8(try OpalFusion
                    .MosaicPrivateAlphaRuntime.postManifestRecoveryTag(
                        for: authority.phase
                    ))
                try encoder.writeBytes(authority.context.canonicalBytes)
                try encoder.writeFixedBytes(
                    Array(authority.signerIdentity.rawRepresentation),
                    byteCount: 32
                )
                encoder.writeUInt64(authority.expiryUnixSeconds)
                switch reason {
                case .timeout: encoder.writeUInt8(0)
                case .equivocation: encoder.writeUInt8(1)
                case .invalidAuthenticatedMessage: encoder.writeUInt8(2)
                case .missingRequiredParticipant: encoder.writeUInt8(3)
                }
            case .unavailable:
                encoder.writeUInt8(2)
            }
            return Data(encoder.encodedBytes)
        }
    }
}
#endif

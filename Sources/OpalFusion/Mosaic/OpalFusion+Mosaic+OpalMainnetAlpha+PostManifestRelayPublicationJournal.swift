// OpalFusion+Mosaic+OpalMainnetAlpha+PostManifestRelayPublicationJournal.swift

import Foundation
import Synchronization

extension OpalFusion.Mosaic.OpalMainnetAlpha {
    /// One attempt-bound write-ahead authority for post-manifest relay publication.
    ///
    /// The journal records every canonical signed event in a complete publication batch through
    /// one compare-and-swap append before a route can be opened. It then records each relay attempt
    /// and matching NIP-01 acknowledgement before transport success is reported. Canonical
    /// encrypted events plus attempt, generation, material, recipient, endpoint, expiry, and batch
    /// fields are nonsecret but privacy-sensitive correlation data. Keep them in app-owned,
    /// attempt-scoped private persistence; never log or externally expose them. Records never
    /// contain signing keys or other secret material.
    final class PostManifestRelayPublicationJournal: Sendable {
        typealias ControlContext = PostManifestControlPublicationBridge.Context
        typealias Endpoint = PostManifestRelayEndpoint
        typealias Nostr = OpalFusion.Mosaic.NostrNamespace

        struct Context: Sendable, Equatable {
            let attemptIdentifier: OpalFusion.Mosaic.LocalAttempt
                .AttemptIdentifier
            let generationIdentifier: OpalFusion.Mosaic.LocalAttempt
                .GenerationIdentifier
            let materialIdentifier: OpalFusion.Mosaic.LocalAttempt
                .MaterialIdentifier
            let localControlIdentity: OpalFusion.Mosaic.Attempt.ControlIdentity
            let roundIdentifier: Data
            let manifestRelaySetDigest: Data
            let endpoints: [Endpoint]

            init(
                publicationContext: ControlContext,
                relaySelection: PostManifestRelaySelectionValidation
            ) throws(InitializationError) {
                guard relaySelection.manifestRelaySetDigest
                        == publicationContext.manifest.core.relaySetDigest else {
                    throw .publicationContextMismatch
                }
                attemptIdentifier = publicationContext.attemptIdentifier
                generationIdentifier = publicationContext.generationIdentifier
                materialIdentifier = publicationContext.materialIdentifier
                localControlIdentity = publicationContext.localControlIdentity
                roundIdentifier = Data(publicationContext.roundIdentifier)
                manifestRelaySetDigest = Data(
                    relaySelection.manifestRelaySetDigest
                )
                endpoints = relaySelection.endpoints.sorted {
                    $0.validatedIdentifier < $1.validatedIdentifier
                }
            }
        }

        enum ChannelPurpose: Sendable, Equatable, Hashable {
            case control
            case anonymousComponents
            case anonymousBCHSignatures
        }

        struct PublicationBinding: Sendable, Equatable, Hashable {
            let channelPurpose: ChannelPurpose
            let recipientEventIdentity: Data
            let expiryUnixSeconds: UInt64

            init(
                channelPurpose: ChannelPurpose,
                recipientEventIdentity: Data,
                expiryUnixSeconds: UInt64
            ) throws(RecordingError) {
                guard recipientEventIdentity.count == 32,
                      expiryUnixSeconds > 0 else {
                    throw .invalidPublication
                }
                self.channelPurpose = channelPurpose
                self.recipientEventIdentity = Data(recipientEventIdentity)
                self.expiryUnixSeconds = expiryUnixSeconds
            }
        }

        struct Publication: Sendable, Equatable {
            let binding: PublicationBinding
            let eventIdentifier: Data
            let canonicalEventBytes: Data
            let endpoints: [Endpoint]

            init(
                binding: PublicationBinding,
                eventIdentifier: Data,
                canonicalEventBytes: Data,
                endpoints: [Endpoint]
            ) {
                self.binding = binding
                self.eventIdentifier = Data(eventIdentifier)
                self.canonicalEventBytes = Data(canonicalEventBytes)
                self.endpoints = endpoints
            }
        }

        struct PublicationPreparation: Sendable {
            let giftWrap: PostManifestRelayPublisher.GiftWrap
            let binding: PublicationBinding

            init(
                giftWrap: PostManifestRelayPublisher.GiftWrap,
                binding: PublicationBinding
            ) {
                self.giftWrap = giftWrap
                self.binding = binding
            }
        }

        struct PublicationBatch: Sendable, Equatable {
            let channelPurpose: ChannelPurpose
            let publications: [Publication]

            init(
                channelPurpose: ChannelPurpose,
                publications: [Publication]
            ) {
                self.channelPurpose = channelPurpose
                self.publications = publications
            }
        }

        enum RelayAcknowledgement: Sendable, Equatable, Hashable {
            case accepted
            case rejected
        }

        enum Completion: Sendable, Equatable, Hashable {
            case transportAccepted
            case transportRejected
            case cancelled
        }

        enum Record: Sendable, Equatable {
            case prepared(PublicationBatch)
            case publicationPermitted(eventIdentifier: Data)
            case attempted(eventIdentifier: Data, endpoint: Endpoint)
            case acknowledged(
                eventIdentifier: Data,
                endpoint: Endpoint,
                RelayAcknowledgement
            )
            case completed(eventIdentifier: Data, Completion)
        }

        struct Snapshot: Sendable, Equatable {
            let context: Context
            let records: [Record]

            init(context: Context, records: [Record]) {
                self.context = context
                self.records = records
            }
        }

        struct Persistence: Sendable {
            /// Loads the last complete snapshot for this exact attempt context.
            let loadSnapshot: @Sendable (Context) throws -> Snapshot?

            /// Atomically compares the durable record count and appends one record.
            ///
            /// A persistent implementation must commit before returning, reject a count
            /// mismatch, and must not synchronously re-enter this journal. If it throws after
            /// committing, `loadSnapshot` must immediately expose the last complete snapshot so
            /// the journal can reconcile the indeterminate result.
            let appendRecord: @Sendable (Context, Int, Record) throws -> Void

            init(
                loadSnapshot: @escaping @Sendable (Context) throws -> Snapshot?,
                appendRecord: @escaping @Sendable (
                    Context,
                    Int,
                    Record
                ) throws -> Void
            ) {
                self.loadSnapshot = loadSnapshot
                self.appendRecord = appendRecord
            }
        }

        struct Continuation: Sendable, Equatable {
            let publication: Publication
            let hasPublicationPermit: Bool
            let attemptedEndpoints: Set<Endpoint>
            let relayAcknowledgements: [Endpoint: RelayAcknowledgement]
            let completion: Completion?

            fileprivate init(entry: Entry) {
                publication = entry.publication
                hasPublicationPermit = entry.hasPublicationPermit
                attemptedEndpoints = entry.attemptedEndpoints
                relayAcknowledgements = entry.relayAcknowledgements
                completion = entry.completion
            }

            var status: Status {
                if let completion {
                    return .completed(completion)
                }
                let acceptedCount = relayAcknowledgements.values.reduce(0) {
                    $1 == .accepted ? $0 + 1 : $0
                }
                if acceptedCount >= 2 { return .transportAccepted }
                let unresolvedCount = publication.endpoints.count
                    - relayAcknowledgements.count
                if acceptedCount + unresolvedCount < 2 {
                    return .transportRejected
                }
                return .awaitingAcknowledgements
            }

            var unresolvedEndpoints: [Endpoint] {
                publication.endpoints.filter {
                    relayAcknowledgements[$0] == nil
                }
            }
        }

        struct BatchContinuation: Sendable, Equatable {
            let batch: PublicationBatch
            let continuations: [Continuation]

            fileprivate init(
                batch: PublicationBatch,
                entriesByEventIdentifier: [Data: Entry]
            ) {
                self.batch = batch
                continuations = batch.publications.map { publication in
                    guard let entry = entriesByEventIdentifier[
                        publication.eventIdentifier
                    ] else {
                        preconditionFailure(
                            "A validated publication batch lost one of its members."
                        )
                    }
                    return Continuation(entry: entry)
                }
            }

            var pendingContinuations: [Continuation] {
                continuations.filter { $0.completion == nil }
            }
        }

        enum Status: Sendable, Equatable {
            case awaitingAcknowledgements
            case transportAccepted
            case transportRejected
            case completed(Completion)
        }

        enum InitializationError: Error, Sendable, Equatable {
            case loadFailed
            case contextMismatch
            case publicationContextMismatch
            case invalidSnapshot
        }

        enum RecordingError: Error, Sendable, Equatable {
            case appendFailed
            case staleOrCorruptSnapshot
            case invalidPublication
            case invalidPublicationBatch
            case duplicateActivePublication
            case unknownPublication
            case invalidTransition
            case staleContinuation
        }

        fileprivate struct Entry: Sendable {
            let publication: Publication
            var hasPublicationPermit = false
            var attemptedEndpoints: Set<Endpoint> = []
            var relayAcknowledgements: [Endpoint: RelayAcknowledgement] = [:]
            var completion: Completion?
        }

        private struct State: Sendable {
            var records: [Record]
            var batches: [PublicationBatch]
            var entriesByEventIdentifier: [Data: Entry]
        }

        private let context: Context
        private let persistence: Persistence
        private let state: Mutex<State>

        var recoveryContext: Context { context }

        init(
            context: Context,
            persistence: Persistence
        ) throws(InitializationError) {
            let snapshot: Snapshot?
            do {
                snapshot = try persistence.loadSnapshot(context)
            } catch {
                throw .loadFailed
            }
            guard snapshot?.context == nil || snapshot?.context == context else {
                throw .contextMismatch
            }

            do {
                state = Mutex(try Self.replay(
                    snapshot?.records ?? [],
                    context: context
                ))
            } catch {
                throw .invalidSnapshot
            }
            self.context = context
            self.persistence = persistence
        }

        func isBound(
            to publicationContext: ControlContext,
            relaySelection: PostManifestRelaySelectionValidation
        ) -> Bool {
            guard let expected = try? Context(
                publicationContext: publicationContext,
                relaySelection: relaySelection
            ) else {
                return false
            }
            return context == expected
        }

        func isBound(
            to relaySelection: PostManifestRelaySelectionValidation
        ) -> Bool {
            context.manifestRelaySetDigest
                    == Data(relaySelection.manifestRelaySetDigest)
                && context.endpoints == relaySelection.endpoints.sorted {
                    $0.validatedIdentifier < $1.validatedIdentifier
                }
        }

        /// Persists one event as a one-member batch before returning its continuation.
        func prepare(
            _ giftWrap: PostManifestRelayPublisher.GiftWrap,
            binding: PublicationBinding
        ) throws(RecordingError) -> Continuation {
            let batch = try prepareBatch([
                .init(giftWrap: giftWrap, binding: binding),
            ])
            guard let continuation = batch.continuations.first else {
                preconditionFailure("A one-member batch returned no continuation.")
            }
            return continuation
        }

        /// Atomically persists every canonical event in one complete publication batch.
        ///
        /// All preparations must have one channel purpose and distinct recipient and event
        /// identities. The persistence callback is invoked exactly once for a new batch. A
        /// returned continuation is the only authority for opening a route for that member.
        func prepareBatch(
            _ preparations: [PublicationPreparation]
        ) throws(RecordingError) -> BatchContinuation {
            let batch = try makeBatch(from: preparations)
            return try update { state in
                if let existing = state.batches.first(where: { $0 == batch }) {
                    return .init(
                        batch: existing,
                        entriesByEventIdentifier:
                            state.entriesByEventIdentifier
                    )
                }
                guard batch.publications.allSatisfy({
                    state.entriesByEventIdentifier[$0.eventIdentifier] == nil
                }) else {
                    throw RecordingError.invalidPublicationBatch
                }
                guard !state.batches.contains(where: { existing in
                    existing.channelPurpose == batch.channelPurpose
                        && existing.publications.contains { publication in
                            state.entriesByEventIdentifier[
                                publication.eventIdentifier
                            ]?.completion == nil
                        }
                }) else {
                    throw RecordingError.duplicateActivePublication
                }

                try append(.prepared(batch), to: &state)
                return .init(
                    batch: batch,
                    entriesByEventIdentifier: state.entriesByEventIdentifier
                )
            }
        }

        /// Persists one caller-granted anonymous publication permit before route use.
        func recordPublicationPermit(
            eventIdentifier: Data
        ) throws(RecordingError) {
            try update { state in
                guard let entry = state.entriesByEventIdentifier[
                    eventIdentifier
                ] else {
                    throw RecordingError.unknownPublication
                }
                guard entry.completion == nil,
                      entry.publication.binding.channelPurpose != .control,
                      entry.attemptedEndpoints.isEmpty else {
                    throw RecordingError.invalidTransition
                }
                guard !entry.hasPublicationPermit else { return }
                try append(
                    .publicationPermitted(
                        eventIdentifier: Data(eventIdentifier)
                    ),
                    to: &state
                )
            }
        }

        /// Persists intent for one endpoint before the route is opened.
        func recordAttempt(
            eventIdentifier: Data,
            endpoint: Endpoint
        ) throws(RecordingError) {
            try update { state in
                guard let entry = state.entriesByEventIdentifier[
                    eventIdentifier
                ] else {
                    throw RecordingError.unknownPublication
                }
                guard entry.completion == nil,
                      entry.publication.binding.channelPurpose == .control
                        || entry.hasPublicationPermit,
                      entry.publication.endpoints.contains(endpoint) else {
                    throw RecordingError.invalidTransition
                }
                guard !entry.attemptedEndpoints.contains(endpoint) else {
                    return
                }
                try append(
                    .attempted(
                        eventIdentifier: Data(eventIdentifier),
                        endpoint: endpoint
                    ),
                    to: &state
                )
            }
        }

        /// Persists one matching relay acknowledgement before it affects transport success.
        func recordAcknowledgement(
            _ acknowledgement: RelayAcknowledgement,
            eventIdentifier: Data,
            endpoint: Endpoint
        ) throws(RecordingError) {
            try update { state in
                guard let entry = state.entriesByEventIdentifier[
                    eventIdentifier
                ] else {
                    throw RecordingError.unknownPublication
                }
                guard entry.completion == nil,
                      entry.attemptedEndpoints.contains(endpoint) else {
                    throw RecordingError.invalidTransition
                }
                if let existing = entry.relayAcknowledgements[endpoint] {
                    guard existing == acknowledgement else {
                        throw RecordingError.invalidTransition
                    }
                    return
                }
                try append(
                    .acknowledged(
                        eventIdentifier: Data(eventIdentifier),
                        endpoint: endpoint,
                        acknowledgement
                    ),
                    to: &state
                )
            }
        }

        /// Persists the terminal transport result before the publisher reports it.
        func recordCompletion(
            _ completion: Completion,
            eventIdentifier: Data
        ) throws(RecordingError) {
            try update { state in
                guard let entry = state.entriesByEventIdentifier[
                    eventIdentifier
                ] else {
                    throw RecordingError.unknownPublication
                }
                if let existing = entry.completion {
                    guard existing == completion else {
                        throw RecordingError.invalidTransition
                    }
                    return
                }
                guard Self.permits(completion, for: entry) else {
                    throw RecordingError.invalidTransition
                }
                try append(
                    .completed(
                        eventIdentifier: Data(eventIdentifier),
                        completion
                    ),
                    to: &state
                )
            }
        }

        func currentContinuation(
            matching continuation: Continuation
        ) throws(RecordingError) -> Continuation {
            try update { state in
                guard let entry = state.entriesByEventIdentifier[
                    continuation.publication.eventIdentifier
                ], entry.publication == continuation.publication,
                !continuation.hasPublicationPermit
                    || entry.hasPublicationPermit,
                continuation.attemptedEndpoints.isSubset(
                    of: entry.attemptedEndpoints
                ), continuation.relayAcknowledgements.allSatisfy({
                    entry.relayAcknowledgements[$0.key] == $0.value
                }) else {
                    throw RecordingError.staleContinuation
                }
                return .init(entry: entry)
            }
        }

        func pendingContinuations(
            for channelPurpose: ChannelPurpose
        ) -> [Continuation] {
            pendingBatchContinuation(for: channelPurpose)?
                .pendingContinuations ?? []
        }

        /// True only when every write-ahead publication has a durable terminal completion.
        var isDrained: Bool {
            state.withLock { state in
                state.entriesByEventIdentifier.values.allSatisfy {
                    $0.completion != nil
                }
            }
        }

        /// Restores the complete durable membership of the active batch for one purpose.
        func pendingBatchContinuation(
            for channelPurpose: ChannelPurpose
        ) -> BatchContinuation? {
            state.withLock { state in
                guard let batch = state.batches.first(where: { batch in
                    batch.channelPurpose == channelPurpose
                        && batch.publications.contains { publication in
                            state.entriesByEventIdentifier[
                                publication.eventIdentifier
                            ]?.completion == nil
                        }
                }) else {
                    return nil
                }
                return .init(
                    batch: batch,
                    entriesByEventIdentifier: state.entriesByEventIdentifier
                )
            }
        }

        /// Persists every acknowledgement-derived terminal result in one current batch.
        ///
        /// Recovery owners call this before provisioning routes. The supplied continuation must
        /// exactly match the journal's current batch state. A positive quorum becomes transport
        /// accepted, while an impossible positive quorum becomes transport rejected.
        func reconcileAcknowledgementDerivedCompletions(
            matching batchContinuation: BatchContinuation
        ) throws(RecordingError) -> BatchContinuation {
            try update { state in
                guard let batch = state.batches.first(where: {
                    $0 == batchContinuation.batch
                }) else {
                    throw RecordingError.staleContinuation
                }
                let current = BatchContinuation(
                    batch: batch,
                    entriesByEventIdentifier: state.entriesByEventIdentifier
                )
                guard current == batchContinuation else {
                    throw RecordingError.staleContinuation
                }

                for continuation in current.continuations {
                    let completion: Completion
                    switch continuation.status {
                    case .transportAccepted:
                        completion = .transportAccepted
                    case .transportRejected:
                        completion = .transportRejected
                    case .awaitingAcknowledgements, .completed:
                        continue
                    }
                    try append(
                        .completed(
                            eventIdentifier: Data(
                                continuation.publication.eventIdentifier
                            ),
                            completion
                        ),
                        to: &state
                    )
                }

                return .init(
                    batch: batch,
                    entriesByEventIdentifier: state.entriesByEventIdentifier
                )
            }
        }

        private func update<Value>(
            _ body: (inout State) throws -> Value
        ) throws(RecordingError) -> Value {
            let outcome: Result<Value, RecordingError> = state.withLock {
                state in
                do {
                    return .success(try body(&state))
                } catch let error as RecordingError {
                    return .failure(error)
                } catch {
                    preconditionFailure(
                        "A journal state transition threw an undeclared error."
                    )
                }
            }
            return try outcome.get()
        }

        private func append(
            _ record: Record,
            to state: inout State
        ) throws(RecordingError) {
            let priorRecords = state.records
            var expectedState = state
            do {
                try Self.apply(
                    record,
                    context: context,
                    to: &expectedState
                )
            } catch {
                preconditionFailure(
                    "A record reached persistence without a valid state transition."
                )
            }
            expectedState.records.append(record)

            do {
                try persistence.appendRecord(
                    context,
                    priorRecords.count,
                    record
                )
                state = expectedState
                return
            } catch {
                // A failed persistence call may have committed before reporting its error.
            }

            let snapshot: Snapshot?
            do {
                snapshot = try persistence.loadSnapshot(context)
            } catch {
                throw .staleOrCorruptSnapshot
            }
            guard snapshot?.context == nil || snapshot?.context == context else {
                throw .staleOrCorruptSnapshot
            }
            let durableRecords = snapshot?.records ?? []
            let durableState: State
            do {
                durableState = try Self.replay(
                    durableRecords,
                    context: context
                )
            } catch {
                throw .staleOrCorruptSnapshot
            }

            if durableRecords == expectedState.records {
                state = durableState
                return
            }
            if durableRecords == priorRecords {
                state = durableState
                throw .appendFailed
            }
            throw .staleOrCorruptSnapshot
        }

        private static func replay(
            _ records: [Record],
            context: Context
        ) throws(RecordingError) -> State {
            var restored = State(
                records: [],
                batches: [],
                entriesByEventIdentifier: [:]
            )
            for record in records {
                try apply(record, context: context, to: &restored)
                restored.records.append(record)
            }
            return restored
        }

        private static func apply(
            _ record: Record,
            context: Context,
            to state: inout State
        ) throws(RecordingError) {
            switch record {
            case let .prepared(batch):
                try validate(batch, context: context)
                guard batch.publications.allSatisfy({
                    state.entriesByEventIdentifier[$0.eventIdentifier] == nil
                }), !state.batches.contains(where: { existing in
                    existing.channelPurpose == batch.channelPurpose
                        && existing.publications.contains { publication in
                            state.entriesByEventIdentifier[
                                publication.eventIdentifier
                            ]?.completion == nil
                        }
                }) else {
                    throw .duplicateActivePublication
                }
                for publication in batch.publications {
                    state.entriesByEventIdentifier[
                        publication.eventIdentifier
                    ] = .init(publication: publication)
                }
                state.batches.append(batch)

            case let .publicationPermitted(eventIdentifier):
                guard var entry = state.entriesByEventIdentifier[
                    eventIdentifier
                ], entry.completion == nil,
                entry.publication.binding.channelPurpose != .control,
                entry.attemptedEndpoints.isEmpty,
                !entry.hasPublicationPermit else {
                    throw .invalidTransition
                }
                entry.hasPublicationPermit = true
                state.entriesByEventIdentifier[eventIdentifier] = entry

            case let .attempted(eventIdentifier, endpoint):
                guard var entry = state.entriesByEventIdentifier[
                    eventIdentifier
                ], entry.completion == nil,
                entry.publication.binding.channelPurpose == .control
                    || entry.hasPublicationPermit,
                entry.publication.endpoints.contains(endpoint),
                entry.attemptedEndpoints.insert(endpoint).inserted else {
                    throw .invalidTransition
                }
                state.entriesByEventIdentifier[eventIdentifier] = entry

            case let .acknowledged(
                eventIdentifier,
                endpoint,
                acknowledgement
            ):
                guard var entry = state.entriesByEventIdentifier[
                    eventIdentifier
                ], entry.completion == nil,
                entry.attemptedEndpoints.contains(endpoint),
                entry.relayAcknowledgements.updateValue(
                    acknowledgement,
                    forKey: endpoint
                ) == nil else {
                    throw .invalidTransition
                }
                state.entriesByEventIdentifier[eventIdentifier] = entry

            case let .completed(eventIdentifier, completion):
                guard var entry = state.entriesByEventIdentifier[
                    eventIdentifier
                ], entry.completion == nil,
                permits(completion, for: entry) else {
                    throw .invalidTransition
                }
                entry.completion = completion
                state.entriesByEventIdentifier[eventIdentifier] = entry
            }
        }

        private static func validate(
            _ publication: Publication,
            context: Context
        ) throws(RecordingError) {
            guard publication.eventIdentifier.count == 32,
                  publication.binding.recipientEventIdentity.count == 32,
                  publication.binding.expiryUnixSeconds > 0,
                  publication.endpoints == context.endpoints else {
                throw .invalidPublication
            }
            do {
                let limits = try PostManifestNIP59Transport.codingLimits
                let event = try Nostr.EventCodec.decode(
                    publication.canonicalEventBytes,
                    limits: limits.event
                )
                let reencoded = try Nostr.EventCodec.encode(
                    event,
                    limits: limits.event
                )
                let giftWrap = try PostManifestRelayPublisher.GiftWrap(
                    validating: event
                )
                guard reencoded == publication.canonicalEventBytes,
                      giftWrap.event.identifier.rawRepresentation
                        == publication.eventIdentifier,
                      event.template.tags == [[
                        "p",
                        Nostr.EventCodec.hexadecimal(
                            publication.binding.recipientEventIdentity
                        ),
                      ]] else {
                    throw RecordingError.invalidPublication
                }
            } catch let error as RecordingError {
                throw error
            } catch {
                throw .invalidPublication
            }
        }

        private func makeBatch(
            from preparations: [PublicationPreparation]
        ) throws(RecordingError) -> PublicationBatch {
            guard let channelPurpose = preparations.first?.binding
                .channelPurpose else {
                throw .invalidPublicationBatch
            }
            var publications: [Publication] = []
            do {
                let limits = try PostManifestNIP59Transport.codingLimits
                for preparation in preparations {
                    let giftWrap = preparation.giftWrap
                    let binding = preparation.binding
                    guard binding.channelPurpose == channelPurpose,
                          giftWrap.event.template.tags == [[
                            "p",
                            Nostr.EventCodec.hexadecimal(
                                binding.recipientEventIdentity
                            ),
                          ]] else {
                        throw RecordingError.invalidPublicationBatch
                    }
                    let publication = Publication(
                        binding: binding,
                        eventIdentifier:
                            giftWrap.event.identifier.rawRepresentation,
                        canonicalEventBytes: try Nostr.EventCodec.encode(
                            giftWrap.event,
                            limits: limits.event
                        ),
                        endpoints: context.endpoints
                    )
                    try Self.validate(publication, context: context)
                    publications.append(publication)
                }
            } catch let error as RecordingError {
                throw error
            } catch {
                throw .invalidPublication
            }

            publications.sort(by: Self.precedes)
            let batch = PublicationBatch(
                channelPurpose: channelPurpose,
                publications: publications
            )
            try Self.validate(batch, context: context)
            return batch
        }

        private static func validate(
            _ batch: PublicationBatch,
            context: Context
        ) throws(RecordingError) {
            guard !batch.publications.isEmpty,
                  batch.publications.allSatisfy({
                    $0.binding.channelPurpose == batch.channelPurpose
                  }), batch.publications == batch.publications.sorted(
                    by: precedes
                  ), Set(batch.publications.map(\.eventIdentifier)).count
                    == batch.publications.count,
                  Set(batch.publications.map {
                    $0.binding.recipientEventIdentity
                  }).count == batch.publications.count else {
                throw .invalidPublicationBatch
            }
            for publication in batch.publications {
                try validate(publication, context: context)
            }
        }

        private static func precedes(
            _ lhs: Publication,
            _ rhs: Publication
        ) -> Bool {
            if lhs.binding.recipientEventIdentity
                != rhs.binding.recipientEventIdentity {
                return lhs.binding.recipientEventIdentity
                    .lexicographicallyPrecedes(
                        rhs.binding.recipientEventIdentity
                    )
            }
            return lhs.eventIdentifier.lexicographicallyPrecedes(
                rhs.eventIdentifier
            )
        }

        private static func permits(
            _ completion: Completion,
            for entry: Entry
        ) -> Bool {
            switch completion {
            case .transportAccepted:
                return entry.relayAcknowledgements.values.filter {
                    $0 == .accepted
                }.count >= 2
            case .transportRejected:
                let acceptedCount = entry.relayAcknowledgements.values.filter {
                    $0 == .accepted
                }.count
                let unresolvedCount = entry.publication.endpoints.count
                    - entry.relayAcknowledgements.count
                return acceptedCount + unresolvedCount < 2
            case .cancelled:
                let acceptedCount = entry.relayAcknowledgements.values.filter {
                    $0 == .accepted
                }.count
                let unresolvedCount = entry.publication.endpoints.count
                    - entry.relayAcknowledgements.count
                return acceptedCount < 2
                    && acceptedCount + unresolvedCount >= 2
            }
        }
    }
}

// OpalFusion+Mosaic+OpalMainnetAlpha+PostManifestAdmissionJournal.swift

import Synchronization

extension OpalFusion.Mosaic.OpalMainnetAlpha {
    /// One attempt-bound write-ahead authority for authenticated inbound replay facts.
    ///
    /// The admission ledger remains the semantic validator. Coordinators stage a candidate
    /// runtime value, record only inputs that consumed admission state, and publish the staged
    /// effects only after this journal's synchronous append boundary succeeds. A restored
    /// nonempty journal is evidence that the complete runtime also needs recovery. Recovery must
    /// replay the exact authenticated deliveries in journal order before live ingress can resume.
    final class PostManifestAdmissionJournal: Sendable {
        typealias Driver = OpalFusion.Mosaic.OpalMainnetAlpha
            .PostManifestRuntimeDriver
        typealias Ledger = OpalFusion.Mosaic.OpalMainnetAlpha.AdmissionLedger
        typealias Transport = OpalFusion.Mosaic.OpalMainnetAlpha
            .PostManifestNIP59Transport
        typealias RecoveryAdmission = OpalFusion.Mosaic.OpalMainnetAlpha
            .PostManifestTransportIngress.RecoveredAdmission

        struct RecipientBinding: Sendable, Equatable {
            let channel: Transport.Channel
            let eventIdentity: [UInt8]

            init(
                channel: Transport.Channel,
                eventIdentity: [UInt8]
            ) {
                self.channel = channel
                self.eventIdentity = eventIdentity
            }
        }

        struct Context: Sendable, Equatable {
            let attemptIdentifier: Driver.Session.AttemptIdentifier
            let generationIdentifier: Driver.Session.GenerationIdentifier
            let materialIdentifier: Driver.Session.MaterialIdentifier
            let localControlIdentity: Driver.Session.ControlIdentity
            let roundIdentifier: [UInt8]
            let recipientBindings: [RecipientBinding]

            init(
                bootstrap: Driver.Bootstrap,
                recipientBindings: [RecipientBinding]
            ) {
                attemptIdentifier = bootstrap.attemptIdentifier
                generationIdentifier = bootstrap.generationIdentifier
                materialIdentifier = bootstrap.materialIdentifier
                localControlIdentity = bootstrap.localControlIdentity
                roundIdentifier = bootstrap.proposalValidation.core
                    .roundIdentifier
                self.recipientBindings = recipientBindings.sorted {
                    $0.eventIdentity.lexicographicallyPrecedes(
                        $1.eventIdentity
                    )
                }
            }
        }

        /// Existing profile replay facts, recorded only after semantic admission.
        enum AcceptedRecord: Sendable, Equatable, Hashable {
            case control(
                sender: Ledger.ControlIdentity,
                sequence: UInt64,
                messageDigest: [UInt8],
                source: RecoveryAdmission
            )
            case anonymous(
                messageIdentifier: OpalFusion.Mosaic.RuntimeSession
                    .MessageIdentifier,
                senderEventIdentity: [UInt8],
                recipientEventIdentity: [UInt8],
                sequence: UInt64,
                payloadType: UInt16,
                payloadDigest: [UInt8],
                source: RecoveryAdmission
            )

            init(
                control delivery: Ledger.ControlDelivery,
                source: RecoveryAdmission
            ) {
                self = .control(
                    sender: delivery.envelope.senderControlIdentity,
                    sequence: delivery.envelope.sequence,
                    messageDigest: delivery.envelope.messageDigest,
                    source: source
                )
            }

            init(
                anonymous delivery: Ledger.AnonymousDelivery,
                source: RecoveryAdmission
            ) {
                self = .anonymous(
                    messageIdentifier:
                        delivery.authenticatedMessageIdentifier,
                    senderEventIdentity:
                        delivery.authenticatedOuterEventIdentity,
                    recipientEventIdentity:
                        delivery.authenticatedRecipientEventIdentity,
                    sequence: delivery.envelope.sequence,
                    payloadType: delivery.envelope.payloadType.rawValue,
                    payloadDigest: delivery.envelope.payloadDigest,
                    source: source
                )
            }

            var recoveryAdmission: RecoveryAdmission {
                switch self {
                case let .control(_, _, _, source),
                     let .anonymous(_, _, _, _, _, _, source):
                    source
                }
            }

            fileprivate func conflicts(with other: Self) -> Bool {
                switch (self, other) {
                case let (
                    .control(sender, sequence, _, _),
                    .control(otherSender, otherSequence, _, _)
                ):
                    sender == otherSender && sequence == otherSequence

                case let (
                    .anonymous(
                        identifier,
                        _,
                        recipient,
                        sequence,
                        _,
                        _,
                        _
                    ),
                    .anonymous(
                        otherIdentifier,
                        _,
                        otherRecipient,
                        otherSequence,
                        _,
                        _,
                        _
                    )
                ):
                    identifier == otherIdentifier
                        || (recipient == otherRecipient
                            && sequence == otherSequence)

                case (.control, .anonymous), (.anonymous, .control):
                    false
                }
            }
        }

        struct Snapshot: Sendable, Equatable {
            let context: Context
            let acceptedRecords: [AcceptedRecord]

            init(
                context: Context,
                acceptedRecords: [AcceptedRecord]
            ) {
                self.context = context
                self.acceptedRecords = acceptedRecords
            }
        }

        struct Store: Sendable {
            /// Loads the last complete snapshot for this exact attempt context.
            let load: @Sendable (Context) throws -> Snapshot?
            /// Compares the current count and appends one record at the injected store boundary.
            ///
            /// A persistent implementation must perform both operations atomically, durably commit
            /// before returning, fail on a count mismatch, and avoid re-entering this journal.
            let append: @Sendable (
                Context,
                Int,
                AcceptedRecord
            ) throws -> Void

            init(
                load: @escaping @Sendable (Context) throws -> Snapshot?,
                append: @escaping @Sendable (
                    Context,
                    Int,
                    AcceptedRecord
                ) throws -> Void
            ) {
                self.load = load
                self.append = append
            }

            /// Keeps replay state only in the live journal; it supplies no restart persistence.
            static var volatile: Self {
                .init(load: { _ in nil }, append: { _, _, _ in })
            }
        }

        enum InitializationError: Error, Sendable, Equatable {
            case loadFailed
            case contextMismatch
            case duplicateRecord
            case conflictingRecord
        }

        enum RecordingError: Error, Sendable, Equatable {
            case appendFailed
            case conflictingRecord
            case recoveryRecordMismatch
        }

        enum Classification: Sendable, Equatable {
            case unseen
            case exactDuplicate
            case conflict
        }

        private struct State: Sendable {
            var acceptedRecords: [AcceptedRecord]
            var recoveryCursor: Int?
        }

        private let context: Context
        private let store: Store
        private let state: Mutex<State>

        var recoveryContext: Context { context }

        var requiresRuntimeRecovery: Bool {
            state.withLock { $0.recoveryCursor != nil }
        }

        var recoveredAdmissions: [RecoveryAdmission] {
            state.withLock { state in
                guard state.recoveryCursor != nil else { return [] }
                return state.acceptedRecords.map(\.recoveryAdmission)
            }
        }

        var recoveredRecords: [AcceptedRecord] {
            state.withLock { state in
                guard state.recoveryCursor != nil else { return [] }
                return state.acceptedRecords
            }
        }

        init(
            context: Context,
            store: Store
        ) throws(InitializationError) {
            let snapshot: Snapshot?
            do {
                snapshot = try store.load(context)
            } catch {
                throw .loadFailed
            }
            if let snapshot, snapshot.context != context {
                throw .contextMismatch
            }
            let records = snapshot?.acceptedRecords ?? []
            var accepted: [AcceptedRecord] = []
            for record in records {
                switch Self.classify(record, against: accepted) {
                case .unseen:
                    accepted.append(record)
                case .exactDuplicate:
                    throw .duplicateRecord
                case .conflict:
                    throw .conflictingRecord
                }
            }
            self.context = context
            self.store = store
            state = Mutex(
                .init(
                    acceptedRecords: accepted,
                    recoveryCursor: accepted.isEmpty ? nil : 0
                )
            )
        }

        func classify(_ record: AcceptedRecord) -> Classification {
            state.withLock {
                Self.classify(record, against: $0.acceptedRecords)
            }
        }

        /// Appends before installing the record in live state.
        ///
        /// Calls are synchronous so a coordinator cannot be re-entered between durable append
        /// and installation of the staged runtime value.
        func record(_ record: AcceptedRecord) throws(RecordingError) {
            let recordingError: RecordingError? = state.withLock { state in
                if let recoveryCursor = state.recoveryCursor {
                    guard recoveryCursor < state.acceptedRecords.count,
                          state.acceptedRecords[recoveryCursor] == record else {
                        return .recoveryRecordMismatch
                    }
                    state.recoveryCursor = recoveryCursor + 1
                    return nil
                }
                switch Self.classify(
                    record,
                    against: state.acceptedRecords
                ) {
                case .exactDuplicate:
                    return nil
                case .conflict:
                    return .conflictingRecord
                case .unseen:
                    do {
                        try store.append(
                            context,
                            state.acceptedRecords.count,
                            record
                        )
                    } catch {
                        return .appendFailed
                    }
                    state.acceptedRecords.append(record)
                    return nil
                }
            }
            if let recordingError {
                throw recordingError
            }
        }

        /// Ends replay only after every durable admission record was reproduced exactly once and
        /// in its original order. A partial or contradictory replay leaves recovery required.
        func completeRuntimeRecovery() -> Bool {
            state.withLock { state in
                guard let recoveryCursor = state.recoveryCursor,
                      recoveryCursor == state.acceptedRecords.count else {
                    return false
                }
                state.recoveryCursor = nil
                return true
            }
        }

        private static func classify(
            _ record: AcceptedRecord,
            against acceptedRecords: [AcceptedRecord]
        ) -> Classification {
            if acceptedRecords.contains(record) {
                return .exactDuplicate
            }
            if acceptedRecords.contains(where: { $0.conflicts(with: record) }) {
                return .conflict
            }
            return .unseen
        }
    }
}

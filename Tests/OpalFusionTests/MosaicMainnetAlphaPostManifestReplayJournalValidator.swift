// MosaicMainnetAlphaPostManifestReplayJournalValidator.swift

import Foundation
import OpalCrypto
import Testing
@_spi(MosaicPrivateAlpha) @testable import OpalFusion

@Suite("Mosaic mainnet-alpha post-manifest replay journal")
struct MosaicMainnetAlphaPostManifestReplayJournalValidator {
    typealias Alpha = OpalFusion.Mosaic.OpalMainnetAlpha
    typealias Driver = Alpha.PostManifestRuntimeDriver
    typealias Fixture = MosaicMainnetAlphaAdmissionLedgerFixtures
    typealias Ingress = Alpha.PostManifestTransportIngress
    typealias Journal = Alpha.PostManifestAdmissionJournal
    typealias Ledger = Alpha.AdmissionLedger
    typealias Runtime = OpalFusion.MosaicPrivateAlphaRuntime

    private final class StoreProbe: @unchecked Sendable {
        private let lock = NSLock()
        private var loadedSnapshot: Journal.Snapshot?
        private var appendedRecords: [Journal.AcceptedRecord] = []
        private var shouldFailAppend = false

        init(snapshot: Journal.Snapshot? = nil) {
            loadedSnapshot = snapshot
        }

        var records: [Journal.AcceptedRecord] {
            withLock { appendedRecords }
        }

        var store: Journal.Store {
            .init(
                load: { [self] _ in withLock { loadedSnapshot } },
                append: { [self] _, expectedCount, record in
                    try withLock {
                        guard !shouldFailAppend else {
                            throw ProbeFailure.appendFailed
                        }
                        guard appendedRecords.count == expectedCount else {
                            throw ProbeFailure.appendFailed
                        }
                        appendedRecords.append(record)
                    }
                }
            )
        }

        func failAppend() {
            withLock { shouldFailAppend = true }
        }

        private func withLock<Result>(
            _ operation: () throws -> Result
        ) rethrows -> Result {
            lock.lock()
            defer { lock.unlock() }
            return try operation()
        }
    }

    @Test("Persist control replay once and restore exact duplicate classification")
    func persistAndRestoreControlReplay() throws {
        let construction = try makeContext()
        let accepted = Journal.AcceptedRecord.control(
            sender: construction.harness.election.result.roster.conductor,
            sequence: 0,
            messageDigest: [UInt8](repeating: 0xA1, count: 32),
            source: source(0xA1, acceptedAt: 100)
        )
        let conflict = Journal.AcceptedRecord.control(
            sender: construction.harness.election.result.roster.conductor,
            sequence: 0,
            messageDigest: [UInt8](repeating: 0xB1, count: 32),
            source: source(0xB1, acceptedAt: 100)
        )
        let probe = StoreProbe()
        let journal = try Journal(
            context: construction.context,
            store: probe.store
        )

        #expect(journal.classify(accepted) == .unseen)
        try journal.record(accepted)
        try journal.record(accepted)
        #expect(probe.records == [accepted])
        #expect(journal.classify(accepted) == .exactDuplicate)
        #expect(journal.classify(conflict) == .conflict)

        let restored = try Journal(
            context: construction.context,
            store: StoreProbe(
                snapshot: .init(
                    context: construction.context,
                    acceptedRecords: probe.records
                )
            ).store
        )
        #expect(restored.requiresRuntimeRecovery)
        #expect(restored.classify(accepted) == .exactDuplicate)
        #expect(restored.classify(conflict) == .conflict)
    }

    @Test("Merge anonymous wrapper and mailbox replay identities")
    func mergeAnonymousReplayIdentities() throws {
        let construction = try makeContext()
        let accepted = try anonymousRecord(
            messageByte: 0x11,
            senderByte: 0x21,
            recipientByte: 0x31,
            sequence: 0,
            payloadByte: 0x41
        )
        let sameWrapperConflict = try anonymousRecord(
            messageByte: 0x11,
            senderByte: 0x22,
            recipientByte: 0x32,
            sequence: 0,
            payloadByte: 0x42
        )
        let sameMailboxConflict = try anonymousRecord(
            messageByte: 0x12,
            senderByte: 0x22,
            recipientByte: 0x31,
            sequence: 0,
            payloadByte: 0x42
        )
        let nextMailboxSequence = try anonymousRecord(
            messageByte: 0x13,
            senderByte: 0x23,
            recipientByte: 0x31,
            sequence: 1,
            payloadByte: 0x43
        )
        let journal = try Journal(
            context: construction.context,
            store: .volatile
        )

        try journal.record(accepted)
        #expect(journal.classify(accepted) == .exactDuplicate)
        #expect(journal.classify(sameWrapperConflict) == .conflict)
        #expect(journal.classify(sameMailboxConflict) == .conflict)
        #expect(journal.classify(nextMailboxSequence) == .unseen)
    }

    @Test("Fail append without installing replay state")
    func failAppendBeforeInstallation() throws {
        let construction = try makeContext()
        let record = Journal.AcceptedRecord.control(
            sender: construction.harness.election.result.roster.conductor,
            sequence: 0,
            messageDigest: [UInt8](repeating: 0xA1, count: 32),
            source: source(0xA1, acceptedAt: 100)
        )
        let probe = StoreProbe()
        probe.failAppend()
        let journal = try Journal(
            context: construction.context,
            store: probe.store
        )

        #expect(throws: Journal.RecordingError.appendFailed) {
            try journal.record(record)
        }
        #expect(journal.classify(record) == .unseen)
        #expect(probe.records.isEmpty)
    }

    @Test("Record only a delivery that consumed semantic admission state")
    func ignoreRejectedAndDuplicateDeliveries() throws {
        let construction = try makeContext()
        let run = try Fixture.aggregateRun(
            canonicalBytes: construction.harness.manifest.canonicalBytes,
            kind: .completeManifest,
            sender: construction.harness.election.result.roster.conductor,
            phase: .manifestAgreement,
            sequence: 0,
            harness: construction.harness
        )
        let delivery = run.reservation
        let expired = Ledger.ControlDelivery(
            attemptIdentifier: delivery.attemptIdentifier,
            generationIdentifier: delivery.generationIdentifier,
            envelope: delivery.envelope,
            authenticatedOuterEventIdentity:
                delivery.authenticatedOuterEventIdentity,
            currentUnixSeconds: delivery.envelope.expiryUnixSeconds + 1
        )
        var ledger = construction.harness.ledger

        let rejected = ledger.applyAuthenticatedControl(expired)
        let accepted = ledger.applyAuthenticatedControl(delivery)
        let duplicate = ledger.applyAuthenticatedControl(delivery)

        #expect(!rejected.didConsumeReplayState)
        #expect(accepted.didConsumeReplayState)
        #expect(!duplicate.didConsumeReplayState)
        #expect(rejected.effects == [.inputRejected(.expiredEnvelope)])
        #expect(duplicate.effects == [.exactDuplicateIgnored])
    }

    @Test("Require exact recovery envelope bytes time order and cardinality")
    func requireExactRecoveryEnvelopeSequence() throws {
        let construction = try makeContext()
        let sender = construction.harness.election.result.roster.conductor
        let first = Journal.AcceptedRecord.control(
            sender: sender,
            sequence: 0,
            messageDigest: [UInt8](repeating: 0xA1, count: 32),
            source: source(0xC1, acceptedAt: 100)
        )
        let second = Journal.AcceptedRecord.control(
            sender: sender,
            sequence: 1,
            messageDigest: [UInt8](repeating: 0xA2, count: 32),
            source: source(0xC2, acceptedAt: 101)
        )
        func restored() throws -> Journal {
            try Journal(
                context: construction.context,
                store: StoreProbe(snapshot: .init(
                    context: construction.context,
                    acceptedRecords: [first, second]
                )).store
            )
        }

        let alteredTime = Journal.AcceptedRecord.control(
            sender: sender,
            sequence: 0,
            messageDigest: [UInt8](repeating: 0xA1, count: 32),
            source: source(0xC1, acceptedAt: 102)
        )
        #expect(throws: Journal.RecordingError.recoveryRecordMismatch) {
            try restored().record(alteredTime)
        }
        let alteredBytes = Journal.AcceptedRecord.control(
            sender: sender,
            sequence: 0,
            messageDigest: [UInt8](repeating: 0xA1, count: 32),
            source: source(0xCF, acceptedAt: 100)
        )
        #expect(throws: Journal.RecordingError.recoveryRecordMismatch) {
            try restored().record(alteredBytes)
        }
        #expect(throws: Journal.RecordingError.recoveryRecordMismatch) {
            try restored().record(second)
        }

        let missing = try restored()
        try missing.record(first)
        #expect(!missing.completeRuntimeRecovery())

        let extra = try restored()
        try extra.record(first)
        try extra.record(second)
        #expect(throws: Journal.RecordingError.recoveryRecordMismatch) {
            try extra.record(second)
        }

        let exact = try restored()
        try exact.record(first)
        try exact.record(second)
        #expect(exact.completeRuntimeRecovery())
        #expect(!exact.requiresRuntimeRecovery)
    }

    @Test("Reject a snapshot from another attempt context")
    func rejectForeignContext() throws {
        let construction = try makeContext()
        let foreignContext = Journal.Context(
            bootstrap: Driver.Bootstrap(
                validatedAttempt: Fixture.makeValidatedAttempt(
                    election: construction.harness.election
                ),
                attemptIdentifier: .init(
                    validatedBytes: [UInt8](repeating: 0xFF, count: 32)
                ),
                generationIdentifier:
                    construction.harness.generationIdentifier,
                materialIdentifier: construction.harness.materialIdentifier,
                localControlIdentity:
                    construction.harness.localControlIdentity,
                proposalValidation: construction.harness.proposalValidation
            ),
            recipientBindings: [
                .init(
                    channel: .control,
                    eventIdentity: [UInt8](repeating: 0x51, count: 32)
                ),
            ]
        )
        let probe = StoreProbe(
            snapshot: .init(
                context: foreignContext,
                acceptedRecords: []
            )
        )

        #expect(throws: Journal.InitializationError.contextMismatch) {
            _ = try Journal(
                context: construction.context,
                store: probe.store
            )
        }
    }

    @Test("Reject canonical duplicate or conflicting terminal readback")
    func rejectSemanticallyInvalidTerminalReadback() throws {
        let construction = try makeContext()
        let binding = try makeBinding(construction.context)
        let persistenceStore = MosaicPrivateAlphaRuntimePersistenceStore()
        let persistence = Runtime.PostManifestAdmissionPersistence(
            load: persistenceStore.load,
            compareAndSwap: persistenceStore.compareAndSwap
        )
        try Journal.initializeRecoverySnapshot(
            binding: binding,
            persistence: persistence,
            context: construction.context,
            requireExisting: false
        )
        let recoveryStore = Journal.recoveryStore(
            binding: binding,
            persistence: persistence
        )
        let accepted = Journal.AcceptedRecord.control(
            sender: construction.harness.election.result.roster.conductor,
            sequence: 0,
            messageDigest: [UInt8](repeating: 0xA1, count: 32),
            source: source(0xA1, acceptedAt: 100)
        )
        try recoveryStore.append(construction.context, 0, accepted)
        #expect(throws: Journal.InitializationError.duplicateRecord) {
            try recoveryStore.append(construction.context, 1, accepted)
        }
        let duplicateBytes = try #require(persistenceStore.load(binding))
        #expect(throws: Journal.InitializationError.duplicateRecord) {
            try Journal.validateRecoveryReadback(
                duplicateBytes,
                expectedContext: construction.context
            )
        }
        #expect(throws: Journal.InitializationError.duplicateRecord) {
            try Journal.initializeRecoverySnapshot(
                binding: binding,
                persistence: persistence,
                context: construction.context,
                requireExisting: true
            )
        }

        let conflictStore = MosaicPrivateAlphaRuntimePersistenceStore()
        let conflictPersistence = Runtime.PostManifestAdmissionPersistence(
            load: conflictStore.load,
            compareAndSwap: conflictStore.compareAndSwap
        )
        try Journal.initializeRecoverySnapshot(
            binding: binding,
            persistence: conflictPersistence,
            context: construction.context,
            requireExisting: false
        )
        let conflictingRecoveryStore = Journal.recoveryStore(
            binding: binding,
            persistence: conflictPersistence
        )
        let conflict = Journal.AcceptedRecord.control(
            sender: construction.harness.election.result.roster.conductor,
            sequence: 0,
            messageDigest: [UInt8](repeating: 0xB1, count: 32),
            source: source(0xB1, acceptedAt: 101)
        )
        try conflictingRecoveryStore.append(
            construction.context,
            0,
            accepted
        )
        #expect(throws: Journal.InitializationError.conflictingRecord) {
            try conflictingRecoveryStore.append(
                construction.context,
                1,
                conflict
            )
        }
        let conflictBytes = try #require(conflictStore.load(binding))
        #expect(throws: Journal.InitializationError.conflictingRecord) {
            try Journal.validateRecoveryReadback(
                conflictBytes,
                expectedContext: construction.context
            )
        }
        #expect(throws: Journal.InitializationError.conflictingRecord) {
            try Journal.initializeRecoverySnapshot(
                binding: binding,
                persistence: conflictPersistence,
                context: construction.context,
                requireExisting: true
            )
        }
    }

    @Test("Bound admission recovery counts and total bytes before decoding")
    func boundAdmissionRecoveryDecoding() throws {
        let construction = try makeContext()
        let binding = try makeBinding(construction.context)
        let persistenceStore = MosaicPrivateAlphaRuntimePersistenceStore()
        let persistence = Runtime.PostManifestAdmissionPersistence(
            load: persistenceStore.load,
            compareAndSwap: persistenceStore.compareAndSwap
        )
        try Journal.initializeRecoverySnapshot(
            binding: binding,
            persistence: persistence,
            context: construction.context,
            requireExisting: false
        )
        var hugeCount = try #require(persistenceStore.load(binding))
        hugeCount.replaceSubrange(
            (hugeCount.count - 4) ..< hugeCount.count,
            with: [0xFF, 0xFF, 0xFF, 0xFF]
        )
        #expect(throws: (any Error).self) {
            try Journal.validateRecoveryReadback(
                hugeCount,
                expectedContext: construction.context
            )
        }
        #expect(throws: (any Error).self) {
            try Journal.validateRecoveryReadback(
                Data(repeating: 0, count: 32_000_001),
                expectedContext: construction.context
            )
        }
    }

    private func makeContext() throws -> (
        context: Journal.Context,
        harness: Fixture.Harness
    ) {
        let harness = try Fixture.makeHarness(
            localRole: .conductor,
            verificationKey: try MosaicMainnetAlphaFixtures
                .rsaVerificationKey(),
            bchSignatureVerificationKey: try MosaicMainnetAlphaFixtures
                .bchSignatureRSAVerificationKey()
        )
        let bootstrap = Driver.Bootstrap(
            validatedAttempt: Fixture.makeValidatedAttempt(
                election: harness.election
            ),
            attemptIdentifier: harness.attemptIdentifier,
            generationIdentifier: harness.generationIdentifier,
            materialIdentifier: harness.materialIdentifier,
            localControlIdentity: harness.localControlIdentity,
            proposalValidation: harness.proposalValidation
        )
        return (
            .init(
                bootstrap: bootstrap,
                recipientBindings: [
                    .init(
                        channel: .control,
                        eventIdentity: [UInt8](repeating: 0x51, count: 32)
                    ),
                ]
            ),
            harness
        )
    }

    private func makeBinding(
        _ context: Journal.Context
    ) throws -> Runtime.Binding {
        try .init(
            attemptIdentifier: Data(
                context.attemptIdentifier.validatedBytes
            ),
            generationIdentifier: Data(
                context.generationIdentifier.opaqueBytes
            ),
            materialIdentifier: Data(
                context.materialIdentifier.opaqueBytes
            )
        )
    }

    private func anonymousRecord(
        messageByte: UInt8,
        senderByte: UInt8,
        recipientByte: UInt8,
        sequence: UInt64,
        payloadByte: UInt8
    ) throws -> Journal.AcceptedRecord {
        .anonymous(
            messageIdentifier: try .init(
                bytes: [UInt8](repeating: messageByte, count: 32)
            ),
            senderEventIdentity: [UInt8](repeating: senderByte, count: 32),
            recipientEventIdentity: [UInt8](
                repeating: recipientByte,
                count: 32
            ),
            sequence: sequence,
            payloadType: Alpha.AnonymousPayloadType.anonymousComponent.rawValue,
            payloadDigest: [UInt8](repeating: payloadByte, count: 32),
            source: source(messageByte, acceptedAt: UInt64(sequence + 100))
        )
    }

    private func source(
        _ byte: UInt8,
        acceptedAt: UInt64
    ) -> Ingress.RecoveredAdmission {
        .init(
            canonicalGiftWrapBytes: Data(repeating: byte, count: 32),
            acceptedAtUnixSeconds: acceptedAt
        )
    }

    private enum ProbeFailure: Error {
        case appendFailed
    }
}

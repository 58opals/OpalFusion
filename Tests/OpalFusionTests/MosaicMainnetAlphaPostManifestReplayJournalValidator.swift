// MosaicMainnetAlphaPostManifestReplayJournalValidator.swift

import Foundation
import OpalCrypto
import Testing
@testable import OpalFusion

@Suite("Mosaic mainnet-alpha post-manifest replay journal")
struct MosaicMainnetAlphaPostManifestReplayJournalValidator {
    typealias Alpha = OpalFusion.Mosaic.OpalMainnetAlpha
    typealias Driver = Alpha.PostManifestRuntimeDriver
    typealias Fixture = MosaicMainnetAlphaAdmissionLedgerFixtures
    typealias Journal = Alpha.PostManifestAdmissionJournal
    typealias Ledger = Alpha.AdmissionLedger

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
            messageDigest: [UInt8](repeating: 0xA1, count: 32)
        )
        let conflict = Journal.AcceptedRecord.control(
            sender: construction.harness.election.result.roster.conductor,
            sequence: 0,
            messageDigest: [UInt8](repeating: 0xB1, count: 32)
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
            messageDigest: [UInt8](repeating: 0xA1, count: 32)
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
            payloadDigest: [UInt8](repeating: payloadByte, count: 32)
        )
    }

    private enum ProbeFailure: Error {
        case appendFailed
    }
}

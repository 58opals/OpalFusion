// MosaicMainnetAlphaRelayPublicationJournalFixture.swift

import Synchronization
@testable import OpalFusion

final class MosaicMainnetAlphaRelayPublicationJournalFixture: Sendable {
    typealias Journal = OpalFusion.Mosaic.OpalMainnetAlpha
        .PostManifestRelayPublicationJournal

    enum AppendKind: Sendable, Equatable {
        case prepared
        case publicationPermitted
        case attempted
        case acknowledged
        case completed
    }

    enum AppendFailureDurability: Sendable, Equatable {
        case priorSnapshot
        case appendedRecord
        case duplicatedRecord
    }

    enum Failure: Error, Sendable {
        case injected
        case recordCountMismatch
    }

    private struct State: Sendable {
        var snapshot: Journal.Snapshot?
        var appendCallCount = 0
        var failingAppend: (
            kind: AppendKind,
            durability: AppendFailureDurability
        )?
    }

    private let state = Mutex(State())

    var persistence: Journal.Persistence {
        .init(
            loadSnapshot: { [self] context in
                try state.withLock { state in
                    guard state.snapshot?.context == nil
                            || state.snapshot?.context == context else {
                        throw Failure.injected
                    }
                    return state.snapshot
                }
            },
            appendRecords: { [self] context, expectedCount, newRecords in
                try state.withLock { state in
                    state.appendCallCount += 1
                    let records = state.snapshot?.records ?? []
                    guard records.count == expectedCount else {
                        throw Failure.recordCountMismatch
                    }
                    if let failure = state.failingAppend,
                       newRecords.contains(where: {
                           failure.kind == Self.kind(of: $0)
                       }) {
                        state.failingAppend = nil
                        switch failure.durability {
                        case .priorSnapshot:
                            throw Failure.injected
                        case .appendedRecord:
                            state.snapshot = .init(
                                context: context,
                                records: records + newRecords
                            )
                            throw Failure.injected
                        case .duplicatedRecord:
                            state.snapshot = .init(
                                context: context,
                                records: records + newRecords + newRecords
                            )
                            throw Failure.injected
                        }
                    }
                    state.snapshot = .init(
                        context: context,
                        records: records + newRecords
                    )
                }
            }
        )
    }

    var snapshot: Journal.Snapshot? {
        state.withLock { $0.snapshot }
    }

    var appendCallCount: Int {
        state.withLock { $0.appendCallCount }
    }

    var preparedBatches: [Journal.PublicationBatch] {
        state.withLock { state in
            state.snapshot?.records.compactMap { record in
                guard case let .prepared(batch) = record else { return nil }
                return batch
            } ?? []
        }
    }

    func failNextAppend(
        of kind: AppendKind,
        leaving durability: AppendFailureDurability
    ) {
        state.withLock {
            $0.failingAppend = (kind, durability)
        }
    }

    func replaceSnapshot(_ snapshot: Journal.Snapshot?) {
        state.withLock { $0.snapshot = snapshot }
    }

    private static func kind(of record: Journal.Record) -> AppendKind {
        switch record {
        case .prepared:
            .prepared
        case .publicationPermitted:
            .publicationPermitted
        case .attempted:
            .attempted
        case .acknowledged:
            .acknowledged
        case .completed:
            .completed
        }
    }
}

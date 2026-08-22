// OpalFusion+Mosaic+OpalMainnetAlpha+PostManifestRelayPublicationJournal+TerminalRecovery.swift

import Foundation

extension OpalFusion.Mosaic.OpalMainnetAlpha
    .PostManifestRelayPublicationJournal
{
    /// Replays only the durable outcomes of an already-terminal publication journal.
    ///
    /// Terminal runtime reconstruction must reproduce coordinator decisions without minting new
    /// NIP-59 events, asking for publication permits, or provisioning Tor routes. The enclosing
    /// terminal evidence separately binds the exact canonical journal bytes; this actor consumes
    /// their immutable structural projection in original batch order.
    actor TerminalRecovery {
        enum Failure: Error, Sendable, Equatable {
            case journalNotDrained
            case invalidExpectation
            case journalMismatch
            case recordedTransportFailure
            case cancelled
        }

        private let batches: [DrainedRecoveryBatch]
        private var nextBatchIndex = 0

        init(
            journal: OpalFusion.Mosaic.OpalMainnetAlpha
                .PostManifestRelayPublicationJournal
        ) throws(Failure) {
            guard let batches = journal.makeDrainedRecoveryBatches() else {
                throw .journalNotDrained
            }
            self.batches = batches
        }

        /// Consumes prior batches matching one coordinator publication operation.
        ///
        /// A recorded rejection or cancellation is replayed as a thrown transport failure after
        /// consuming that exact terminal batch. Missing, extra, partial, or structurally different
        /// batches fail closed as a journal mismatch.
        func replay(
            batchCount: Int,
            on channelPurpose: ChannelPurpose,
            to recipientEventIdentities: [Data],
            expiringAt expiryUnixSeconds: UInt64
        ) throws(Failure) {
            let expectedRecipients = Set(recipientEventIdentities)
            guard batchCount > 0,
                  expiryUnixSeconds > 0,
                  !recipientEventIdentities.isEmpty,
                  expectedRecipients.count == recipientEventIdentities.count,
                  recipientEventIdentities.allSatisfy({ $0.count == 32 }) else {
                throw .invalidExpectation
            }

            for _ in 0 ..< batchCount {
                guard !Task.isCancelled else { throw .cancelled }
                guard batches.indices.contains(nextBatchIndex) else {
                    throw .journalMismatch
                }
                let batch = batches[nextBatchIndex]
                let bindings = batch.publicationBindings
                guard batch.channelPurpose == channelPurpose,
                      bindings.count == recipientEventIdentities.count,
                      batch.completions.count == bindings.count,
                      bindings.allSatisfy({ binding in
                          binding.channelPurpose == channelPurpose
                              && binding.expiryUnixSeconds
                                == expiryUnixSeconds
                      }), Set(bindings.map(\.recipientEventIdentity))
                        == expectedRecipients else {
                    throw .journalMismatch
                }

                nextBatchIndex += 1
                guard batch.completions.allSatisfy({
                    $0 == .transportAccepted
                }) else {
                    throw .recordedTransportFailure
                }
            }
        }

        /// True only when the reconstructed coordinator consumed every durable publication batch.
        var isComplete: Bool {
            nextBatchIndex == batches.count
        }
    }
}

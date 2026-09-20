// OpalFusion+Mosaic+OpalMainnetAlpha+PostManifestRelayPublicationJournal~Acknowledgements.swift

extension OpalFusion.Mosaic.OpalMainnetAlpha.PostManifestRelayPublicationJournal {
    actor AcknowledgementRecorder {
        typealias Journal = OpalFusion.Mosaic.OpalMainnetAlpha
            .PostManifestRelayPublicationJournal

        private struct Pending {
            let observation: AcknowledgementObservation
            let completion: CheckedContinuation<Result<Continuation, RecordingError>, Never>
        }

        private var pending: [Pending] = []

        func record(
            _ observation: AcknowledgementObservation,
            in journal: Journal
        ) async throws(RecordingError) -> Continuation {
            guard pending.count < 256 else { throw .invalidTransition }
            let result: Result<Continuation, RecordingError> = await withCheckedContinuation { completion in
                pending.append(.init(observation: observation, completion: completion))
                if pending.count == 1 {
                    Task {
                        await Task.yield()
                        flush(to: journal)
                    }
                }
            }
            return try result.get()
        }

        private func flush(to journal: Journal) {
            let batch = pending
            pending.removeAll(keepingCapacity: true)
            do {
                let results = try journal.recordAcknowledgementsAndDerivedCompletions(
                    batch.map(\.observation)
                )
                for (item, result) in zip(batch, results) {
                    item.completion.resume(returning: .success(result))
                }
            } catch {
                for item in batch {
                    item.completion.resume(returning: .failure(error))
                }
            }
        }
    }
}

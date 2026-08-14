// OpalFusion+Mosaic+OpalMainnetAlpha+PostManifestRelayPublisher~Recovery.swift

extension OpalFusion.Mosaic.OpalMainnetAlpha.PostManifestRelayPublisher {
    /// Publishes one journal-prepared event without accepting caller-supplied event bytes.
    ///
    /// Batch owners use this operation only after one atomic complete-batch preparation. The
    /// publisher verifies that the continuation is current and decodes the exact durable bytes
    /// before any route is opened.
    func publish(
        _ continuation: Journal.Continuation
    ) async throws {
        let current = try currentStoredContinuation(matching: continuation)
        try await resumePrepared(
            current.event,
            continuation: current.continuation
        )
    }

    /// Retransmits only byte-identical journaled bytes through the injected fresh routes.
    ///
    /// This operation performs one bounded continuation attempt. It defines no reconnect,
    /// scheduling, or retry policy; the caller owns when a continuation is attempted.
    func resume(
        _ continuation: Journal.Continuation
    ) async throws {
        try await publish(continuation)
    }

    private func currentStoredContinuation(
        matching continuation: Journal.Continuation
    ) throws -> (
        event: Nostr.Event,
        continuation: Journal.Continuation
    ) {
        let current: Journal.Continuation
        do {
            current = try publicationJournal.currentContinuation(
                matching: continuation
            )
        } catch {
            throw Failure.continuationMismatch
        }

        let event: Nostr.Event
        do {
            event = try Nostr.EventCodec.decode(
                current.publication.canonicalEventBytes,
                limits: codingLimits.event
            )
            let canonicalBytes = try Nostr.EventCodec.encode(
                event,
                limits: codingLimits.event
            )
            let giftWrap = try GiftWrap(validating: event)
            guard canonicalBytes == current.publication.canonicalEventBytes,
                  giftWrap.event.identifier.rawRepresentation
                    == current.publication.eventIdentifier else {
                throw Failure.continuationMismatch
            }
        } catch let failure as Failure {
            throw failure
        } catch {
            throw Failure.continuationMismatch
        }
        return (event, current)
    }
}

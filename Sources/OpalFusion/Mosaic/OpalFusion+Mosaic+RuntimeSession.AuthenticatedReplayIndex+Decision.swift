// OpalFusion+Mosaic+RuntimeSession.AuthenticatedReplayIndex+Decision.swift

extension OpalFusion.Mosaic.RuntimeSession.AuthenticatedReplayIndex {
    enum Decision: Sendable, Equatable {
        case accepted
        case duplicate
        case stale(greatestAcceptedSequence: UInt64)
        case conflict
    }
}

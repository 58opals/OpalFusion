// OpalFusion+Mosaic+RuntimeSession.AuthenticatedReplayIndex+Decision.swift

extension OpalFusion.Mosaic.RuntimeSession.AuthenticatedReplayIndex {
    enum Decision: Sendable, Equatable {
        case accepted
        case duplicate
        case gap(expectedSequence: UInt64, receivedSequence: UInt64)
        case stale(greatestAcceptedSequence: UInt64)
        case conflict
    }
}

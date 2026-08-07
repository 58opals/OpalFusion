// OpalFusion+Mosaic+AnonymousReplayIndex+Decision.swift

extension OpalFusion.Mosaic.AnonymousReplayIndex {
    enum Decision: Sendable, Equatable {
        case accepted
        case duplicate
        case conflict
    }
}

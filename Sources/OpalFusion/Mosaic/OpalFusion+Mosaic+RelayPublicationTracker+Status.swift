// OpalFusion+Mosaic+RelayPublicationTracker+Status.swift

extension OpalFusion.Mosaic.RelayPublicationTracker {
    enum Status: Sendable, Equatable {
        case awaitingResponses
        case accepted
        case failed
    }
}

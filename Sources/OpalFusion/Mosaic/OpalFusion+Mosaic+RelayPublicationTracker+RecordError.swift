// OpalFusion+Mosaic+RelayPublicationTracker+RecordError.swift

extension OpalFusion.Mosaic.RelayPublicationTracker {
    enum RecordError: Swift.Error, Sendable, Equatable {
        case unknownRelay(Endpoint)
        case relayNotAttempted(Endpoint)
        case conflictingResponse(Endpoint)
    }
}

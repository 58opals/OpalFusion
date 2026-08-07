// OpalFusion+Mosaic+RelayPublicationTracker+ValidationError.swift

extension OpalFusion.Mosaic.RelayPublicationTracker {
    enum ValidationError: Swift.Error, Sendable, Equatable {
        case fewerThanThreeRelays(actual: Int)
        case duplicateRelay(Endpoint)
    }
}

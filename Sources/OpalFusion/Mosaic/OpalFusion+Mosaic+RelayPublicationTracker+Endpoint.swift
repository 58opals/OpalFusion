// OpalFusion+Mosaic+RelayPublicationTracker+Endpoint.swift

extension OpalFusion.Mosaic.RelayPublicationTracker {
    struct Endpoint: Sendable, Hashable {
        let validatedIdentifier: String

        init(validatedIdentifier: String) {
            self.validatedIdentifier = validatedIdentifier
        }
    }
}

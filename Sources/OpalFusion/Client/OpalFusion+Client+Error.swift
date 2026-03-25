// OpalFusion+Client+Error.swift

public extension OpalFusion.Client {
    enum Error: Swift.Error, Sendable, Equatable {
        case invalidConfiguration
        case transportUnavailable
        case hostRejected
        case notImplemented
    }
}

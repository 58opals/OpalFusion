// OpalFusion+Client+Error.swift

public extension OpalFusion.Client {
    /// A coarse client-visible failure category for CashFusion lifecycle work.
    enum Error: Swift.Error, Sendable, Equatable {
        case invalidConfiguration
        case transportUnavailable
        case coordinatorRejected
        case hostRejected
        case protocolIncompatible
        case blameRequired
        case notImplemented
    }
}

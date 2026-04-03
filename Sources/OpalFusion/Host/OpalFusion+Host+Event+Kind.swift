// OpalFusion+Host+Event+Kind.swift

public extension OpalFusion.Host.Event {
    /// A coarse event category for host-facing observation of round progress.
    enum Kind: String, Sendable, Equatable {
        case status
        case warning
        case failure
        case completed
    }
}

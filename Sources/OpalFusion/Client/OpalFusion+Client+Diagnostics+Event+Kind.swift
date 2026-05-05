// OpalFusion+Client+Diagnostics+Event+Kind.swift

public extension OpalFusion.Client.Diagnostics.Event {
    enum Kind: String, Sendable, Equatable {
        case lifecycle
        case outboundMessage
        case inboundMessage
        case retry
        case failure
    }
}

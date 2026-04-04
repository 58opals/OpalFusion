// OpalFusion+ProtocolModel+Ping.swift

public extension OpalFusion.ProtocolModel {
    /// A keepalive payload sent over the covert channel.
    struct Ping: Sendable, Equatable {
        public init() {}
    }
}

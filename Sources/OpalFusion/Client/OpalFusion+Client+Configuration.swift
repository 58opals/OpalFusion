// OpalFusion+Client+Configuration.swift

public extension OpalFusion.Client {
    struct Configuration: Sendable, Equatable {
        public let coordinatorHost: String
        public let coordinatorPort: UInt16
        public let covertChannel: OpalFusion.Transport.CovertChannelConfiguration
        public let torSocks5: OpalFusion.Transport.TorSocks5Configuration?

        public init(
            coordinatorHost: String,
            coordinatorPort: UInt16,
            covertChannel: OpalFusion.Transport.CovertChannelConfiguration,
            torSocks5: OpalFusion.Transport.TorSocks5Configuration? = nil
        ) {
            self.coordinatorHost = coordinatorHost
            self.coordinatorPort = coordinatorPort
            self.covertChannel = covertChannel
            self.torSocks5 = torSocks5
        }
    }
}

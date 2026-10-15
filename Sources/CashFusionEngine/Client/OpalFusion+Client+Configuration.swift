import OpalFusionCore

// OpalFusion+Client+Configuration.swift

public extension OpalFusion.Client {
    struct Configuration: Sendable, Equatable {
        public let coordinatorHost: String
        public let coordinatorPort: UInt16
        public let coordinatorRequiresTLS: Bool
        public let covertChannel: OpalFusion.Transport.CovertChannelConfiguration
        public let torSocks5: OpalFusion.Transport.TorSocks5Configuration?

        public init(
            coordinatorHost: String,
            coordinatorPort: UInt16,
            coordinatorRequiresTLS: Bool = false,
            covertChannel: OpalFusion.Transport.CovertChannelConfiguration,
            torSocks5: OpalFusion.Transport.TorSocks5Configuration? = nil
        ) {
            self.coordinatorHost = coordinatorHost
            self.coordinatorPort = coordinatorPort
            self.coordinatorRequiresTLS = coordinatorRequiresTLS
            self.covertChannel = covertChannel
            self.torSocks5 = torSocks5
        }

        /// Checks transport configuration before the host reserves funds or creates a session.
        /// A configured SOCKS endpoint with remote DNS is mandatory. This check does not
        /// establish that the endpoint is Tor or that its deployment provides anonymity.
        public func validate() throws {
            guard OpalFusion.Runtime.validateConfiguration(self) == nil else {
                throw OpalFusion.Client.Error.invalidConfiguration
            }
        }
    }
}

// OpalFusion+Transport+TorSocks5Configuration.swift

public extension OpalFusion.Transport {
    struct TorSocks5Configuration: Sendable, Equatable {
        public let host: String
        public let port: UInt16
        public let resolvesCoordinatorHostNameRemotely: Bool

        public init(
            host: String,
            port: UInt16,
            resolvesCoordinatorHostNameRemotely: Bool = true
        ) {
            self.host = host
            self.port = port
            self.resolvesCoordinatorHostNameRemotely = resolvesCoordinatorHostNameRemotely
        }
    }
}

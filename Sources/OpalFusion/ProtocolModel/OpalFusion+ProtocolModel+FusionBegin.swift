// OpalFusion+ProtocolModel+FusionBegin.swift

public extension OpalFusion.ProtocolModel {
    /// The server's transition from queue state into a fusion attempt.
    struct FusionBegin: Sendable, Equatable {
        /// `fusion.proto` `FusionBegin.tier`.
        public let tier: UInt64
        /// `fusion.proto` `FusionBegin.covert_domain`.
        public let covertDomain: String
        /// `fusion.proto` `FusionBegin.covert_port`.
        public let covertPort: UInt32
        /// `fusion.proto` `FusionBegin.covert_ssl`.
        public let covertSsl: Bool?
        /// `fusion.proto` `FusionBegin.server_time`.
        public let serverTimeUnixSeconds: UInt64

        public init(
            tier: UInt64,
            covertDomain: String,
            covertPort: UInt32,
            covertSsl: Bool? = nil,
            serverTimeUnixSeconds: UInt64
        ) {
            self.tier = tier
            self.covertDomain = covertDomain
            self.covertPort = covertPort
            self.covertSsl = covertSsl
            self.serverTimeUnixSeconds = serverTimeUnixSeconds
        }
    }
}

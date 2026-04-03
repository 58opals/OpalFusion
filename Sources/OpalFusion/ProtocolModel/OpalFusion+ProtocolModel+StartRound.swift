// OpalFusion+ProtocolModel+StartRound.swift

public extension OpalFusion.ProtocolModel {
    /// The server's message that opens a concrete round attempt.
    struct StartRound: Sendable, Equatable {
        /// `fusion.proto` `StartRound.round_pubkey`.
        public let roundPublicKey: [UInt8]
        /// `fusion.proto` `StartRound.blind_nonce_points`.
        public let blindNoncePoints: [[UInt8]]
        /// `fusion.proto` `StartRound.server_time`.
        public let serverTimeUnixSeconds: UInt64

        public init(
            roundPublicKey: [UInt8],
            blindNoncePoints: [[UInt8]],
            serverTimeUnixSeconds: UInt64
        ) {
            self.roundPublicKey = roundPublicKey
            self.blindNoncePoints = blindNoncePoints
            self.serverTimeUnixSeconds = serverTimeUnixSeconds
        }
    }
}

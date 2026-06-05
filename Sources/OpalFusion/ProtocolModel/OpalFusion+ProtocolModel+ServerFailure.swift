// OpalFusion+ProtocolModel+ServerFailure.swift

public extension OpalFusion.ProtocolModel {
    /// A fatal server error message delivered on the primary channel.
    struct ServerFailure: Sendable, Equatable {
        /// `fusion.proto` `Error.message`.
        public let message: String?

        public init(
            message: String? = nil
        ) {
            self.message = message
        }

        public var sanitizedProtocolErrorIdentifier: String {
            guard let message,
                  message.contains(where: { $0.isWhitespace == false }) else {
                return "server_failure_missing_message"
            }

            let tokens = Self.sanitizedIdentifierTokens(from: message)
            if tokens.contains("version") {
                return "server_failure_version_rejected"
            }
            if tokens.contains("genesis") {
                return "server_failure_genesis_rejected"
            }
            if tokens.contains("join") || tokens.contains("joinpool") || tokens.contains("joinpools") {
                return "server_failure_join_rejected"
            }
            if tokens.contains("pool") || tokens.contains("pools") || tokens.contains("tier") {
                return "server_failure_pool_rejected"
            }
            if tokens.contains("component") || tokens.contains("components") {
                return "server_failure_component_rejected"
            }
            if tokens.contains("signature") || tokens.contains("signatures") {
                return "server_failure_signature_rejected"
            }
            if tokens.contains("blame") {
                return "server_failure_blame_rejected"
            }
            if tokens.contains("timeout") {
                return "server_failure_timeout"
            }
            if tokens.contains("busy") || tokens.contains("full") {
                return "server_failure_coordinator_busy"
            }
            if tokens.contains("protocol") {
                return "server_failure_protocol_rejected"
            }

            return "server_failure_coordinator_rejected"
        }

        private static func sanitizedIdentifierTokens(
            from message: String
        ) -> Set<String> {
            Set(
                message
                    .lowercased()
                    .split { character in
                        character.isLetter == false && character.isNumber == false
                    }
                    .map(String.init)
            )
        }
    }
}

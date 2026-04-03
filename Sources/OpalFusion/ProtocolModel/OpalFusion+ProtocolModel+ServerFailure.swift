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
    }
}

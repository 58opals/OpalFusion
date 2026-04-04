// OpalFusion+ProtocolModel+ShareCovertComponents.swift

public extension OpalFusion.ProtocolModel {
    /// The coordinator's shared covert component payload set for the round.
    struct ShareCovertComponents: Sendable, Equatable {
        public let serializedComponents: [[UInt8]]
        public let skipSignatures: Bool?
        public let sessionHash: [UInt8]?

        public init(
            serializedComponents: [[UInt8]],
            skipSignatures: Bool? = nil,
            sessionHash: [UInt8]? = nil
        ) {
            self.serializedComponents = serializedComponents
            self.skipSignatures = skipSignatures
            self.sessionHash = sessionHash
        }
    }
}

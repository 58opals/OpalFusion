// OpalFusion+Transport+CovertChannelConfiguration.swift

public extension OpalFusion.Transport {
    struct CovertChannelConfiguration: Sendable, Equatable {
        public let entryPath: String
        public let maxPayloadBytes: Int
        public let requestTimeoutMilliseconds: UInt64

        public init(
            entryPath: String,
            maxPayloadBytes: Int,
            requestTimeoutMilliseconds: UInt64
        ) {
            self.entryPath = entryPath
            self.maxPayloadBytes = maxPayloadBytes
            self.requestTimeoutMilliseconds = requestTimeoutMilliseconds
        }
    }
}

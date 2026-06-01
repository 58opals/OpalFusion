// OpalFusion+Client+Session+Snapshot+CoordinatorStatus.swift

public extension OpalFusion.Client.Session.Snapshot {
    struct CoordinatorStatus: Sendable, Equatable {
            @available(*, deprecated, renamed: "TierQueue")
            public typealias TierQueueStatus = TierQueue

            @available(*, deprecated, renamed: "TierQueue")
            public typealias QueueStatus = TierQueue

            public let updateSequence: UInt64
            public let latestInboundMessageKind: String?
            public let latestInboundPayloadByteCount: Int?
            public let queueStatus: TierQueue?

            public init(
                updateSequence: UInt64 = 0,
                latestInboundMessageKind: String? = nil,
                latestInboundPayloadByteCount: Int? = nil,
                queueStatus: TierQueue? = nil
            ) {
                self.updateSequence = updateSequence
                self.latestInboundMessageKind = latestInboundMessageKind
                self.latestInboundPayloadByteCount = latestInboundPayloadByteCount
                self.queueStatus = queueStatus
            }
    }
}

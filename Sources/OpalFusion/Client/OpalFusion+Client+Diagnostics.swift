// OpalFusion+Client+Diagnostics.swift

public extension OpalFusion.Client {
    struct Diagnostics: Sendable, Equatable {
        public static let recentEventLimit = 12
        public let activity: Activity
        public let retryAttempt: Int?
        public let nextRetryDelayMilliseconds: Int?
        public let primaryFailureCategory: OpalFusion.Client.Error?
        public let primaryFailureSummary: String?
        public let handshakeStage: HandshakeStage
        public let recentEvents: [Event]

        public init(
            activity: Activity = .idle,
            retryAttempt: Int? = nil,
            nextRetryDelayMilliseconds: Int? = nil,
            primaryFailureCategory: OpalFusion.Client.Error? = nil,
            primaryFailureSummary: String? = nil,
            handshakeStage: HandshakeStage = .notStarted,
            recentEvents: [Event] = []
        ) {
            self.activity = activity
            self.retryAttempt = retryAttempt
            self.nextRetryDelayMilliseconds = nextRetryDelayMilliseconds
            self.primaryFailureCategory = primaryFailureCategory
            self.primaryFailureSummary = primaryFailureSummary
            self.handshakeStage = handshakeStage
            self.recentEvents = Self.cappedRecentEvents(recentEvents)
        }
    }
}

extension OpalFusion.Client.Diagnostics {
    func withActivity(
        _ activity: OpalFusion.Client.Diagnostics.Activity
    ) -> Self {
        .init(
            activity: activity,
            retryAttempt: retryAttempt,
            nextRetryDelayMilliseconds: nextRetryDelayMilliseconds,
            primaryFailureCategory: primaryFailureCategory,
            primaryFailureSummary: primaryFailureSummary,
            handshakeStage: handshakeStage,
            recentEvents: recentEvents
        )
    }

    func withRetry(
        attempt: Int?,
        delay: Duration?
    ) -> Self {
        .init(
            activity: delay == nil ? activity : .retrying,
            retryAttempt: attempt,
            nextRetryDelayMilliseconds: delay.map(\.opalFusionMillisecondsRoundedUp),
            primaryFailureCategory: primaryFailureCategory,
            primaryFailureSummary: primaryFailureSummary,
            handshakeStage: handshakeStage,
            recentEvents: recentEvents
        )
    }

    func withoutFailure() -> Self {
        .init(
            activity: activity,
            retryAttempt: retryAttempt,
            nextRetryDelayMilliseconds: nextRetryDelayMilliseconds,
            primaryFailureCategory: nil,
            primaryFailureSummary: nil,
            handshakeStage: handshakeStage,
            recentEvents: recentEvents
        )
    }

    func withHandshakeStage(
        _ handshakeStage: OpalFusion.Client.Diagnostics.HandshakeStage
    ) -> Self {
        .init(
            activity: activity,
            retryAttempt: retryAttempt,
            nextRetryDelayMilliseconds: nextRetryDelayMilliseconds,
            primaryFailureCategory: primaryFailureCategory,
            primaryFailureSummary: primaryFailureSummary,
            handshakeStage: handshakeStage,
            recentEvents: recentEvents
        )
    }

    func appending(
        _ event: OpalFusion.Client.Diagnostics.Event
    ) -> Self {
        .init(
            activity: activity,
            retryAttempt: retryAttempt,
            nextRetryDelayMilliseconds: nextRetryDelayMilliseconds,
            primaryFailureCategory: primaryFailureCategory,
            primaryFailureSummary: primaryFailureSummary,
            handshakeStage: handshakeStage,
            recentEvents: Self.cappedRecentEvents(recentEvents + [event])
        )
    }

    static func cappedRecentEvents(
        _ events: [OpalFusion.Client.Diagnostics.Event]
    ) -> [OpalFusion.Client.Diagnostics.Event] {
        guard events.count > recentEventLimit else {
            return events
        }

        return Array(events.suffix(recentEventLimit))
    }
}

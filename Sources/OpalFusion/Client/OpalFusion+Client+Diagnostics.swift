// OpalFusion+Client+Diagnostics.swift

public extension OpalFusion.Client {
    struct Diagnostics: Sendable, Equatable {
        public static let recentEventLimit = 12

        public enum Activity: String, Sendable, Equatable {
            case idle
            case connecting
            case running
            case retrying
            case failed
            case stopped
        }

        public enum HandshakeStage: String, Sendable, Equatable {
            case notStarted
            case awaitingServerHello
            case awaitingFusionBegin
            case inRound
            case terminal
        }

        public struct Event: Sendable, Equatable {
            public enum Kind: String, Sendable, Equatable {
                case lifecycle
                case outboundMessage
                case inboundMessage
                case retry
                case failure
            }

            public let kind: Kind
            public let summary: String
            public let messageKind: String?
            public let payloadByteCount: Int?
            public let retryAttempt: Int?
            public let retryDelayMilliseconds: Int?
            public let handshakeStage: OpalFusion.Client.Diagnostics.HandshakeStage

            public init(
                kind: Kind,
                summary: String,
                messageKind: String? = nil,
                payloadByteCount: Int? = nil,
                retryAttempt: Int? = nil,
                retryDelayMilliseconds: Int? = nil,
                handshakeStage: OpalFusion.Client.Diagnostics.HandshakeStage = .notStarted
            ) {
                self.kind = kind
                self.summary = summary
                self.messageKind = messageKind
                self.payloadByteCount = payloadByteCount
                self.retryAttempt = retryAttempt
                self.retryDelayMilliseconds = retryDelayMilliseconds
                self.handshakeStage = handshakeStage
            }
        }

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

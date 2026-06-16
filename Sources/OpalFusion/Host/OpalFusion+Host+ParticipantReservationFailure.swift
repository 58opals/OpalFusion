// OpalFusion+Host+ParticipantReservationFailure.swift

public extension OpalFusion.Host {
    enum ParticipantReservationFailure: Swift.Error, Sendable, Equatable {
        case reservationUnavailable(reason: Reason, summary: String)
        case hostPolicyRejected(reason: Reason, summary: String)

        public var reason: Reason {
            switch self {
            case let .reservationUnavailable(reason, _):
                reason
            case let .hostPolicyRejected(reason, _):
                reason
            }
        }

        public var summary: String {
            switch self {
            case let .reservationUnavailable(_, summary):
                summary
            case let .hostPolicyRejected(_, summary):
                summary
            }
        }

        public var clientError: OpalFusion.Client.Error {
            .hostRejected
        }

        public var completionStatus: OpalFusion.Round.CompletionStatus {
            .hostRejected
        }
    }
}

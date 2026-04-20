// SessionRoundOutcomeKind.swift

enum SessionRoundOutcomeKind: String, Sendable, Equatable {
    case success
    case blameRequired
    case restarted
    case coordinatorRejected
    case hostRejected
    case protocolIncompatible
    case transportFailed
}

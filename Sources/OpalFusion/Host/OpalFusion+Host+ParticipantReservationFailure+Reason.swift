// OpalFusion+Host+ParticipantReservationFailure+Reason.swift

public extension OpalFusion.Host.ParticipantReservationFailure {
    enum Reason: String, Sendable, Equatable {
        case noEligibleInputs = "no_eligible_inputs"
        case insufficientFunds = "insufficient_funds"
        case walletLocked = "wallet_locked"
        case unsupportedInput = "unsupported_input"
        case policyRejected = "policy_rejected"
        case userCancelled = "user_cancelled"
        case unknown = "unknown"
    }
}

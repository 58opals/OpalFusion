// OpalFusion+Round+CompletionStatus.swift

public extension OpalFusion.Round {
    /// A coarse terminal outcome for a publicly observable CashFusion round snapshot.
    enum CompletionStatus: String, Sendable, Equatable {
        case success
        case coordinatorRejected
        case hostRejected
        case protocolIncompatible
        case transportFailed
        case blameRequired
    }
}

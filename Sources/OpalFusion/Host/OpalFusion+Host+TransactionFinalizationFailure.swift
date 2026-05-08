// OpalFusion+Host+TransactionFinalizationFailure.swift

public extension OpalFusion.Host {
    enum TransactionFinalizationFailure: Swift.Error, Sendable, Equatable {
        case transactionAssemblyFailed(summary: String)
        case hostPolicyRejected(summary: String)

        public var summary: String {
            switch self {
            case let .transactionAssemblyFailed(summary):
                summary
            case let .hostPolicyRejected(summary):
                summary
            }
        }

        public var clientError: OpalFusion.Client.Error {
            switch self {
            case .transactionAssemblyFailed:
                .notImplemented
            case .hostPolicyRejected:
                .hostRejected
            }
        }

        public var completionStatus: OpalFusion.Round.CompletionStatus {
            .hostRejected
        }
    }
}

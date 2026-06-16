// OpalFusion+Host+FinalizedTransaction.swift

import OpalDiagnostics

public extension OpalFusion.Host {
    /// The host-owned, signed CashFusion transaction bytes returned after wallet-side validation and signing.
    ///
    /// OpalFusion consumes these bytes to extract the local covert signatures required by the protocol. Broadcast, persistence, and wallet transaction ownership remain outside this package.
    struct FinalizedTransaction: Sendable, Equatable {
        /// The full BCH wire-format signed fusion transaction bytes returned by the host.
        public let signedFusionTransactionBytes: [UInt8]
        public var isDiagnosticsSafe: Bool { false }
        public var diagnosticsPrivacy: OpalDiagnostics.FieldPrivacy { .private }

        public init(signedFusionTransactionBytes: [UInt8]) {
            self.signedFusionTransactionBytes = signedFusionTransactionBytes
        }

        @available(
            *,
            deprecated,
            renamed: "signedFusionTransactionBytes",
            message: "Use signedFusionTransactionBytes to keep host-owned raw fusion transaction bytes explicit."
        )
        public var transactionBytes: [UInt8] {
            signedFusionTransactionBytes
        }

        @available(
            *,
            deprecated,
            message: "Use init(signedFusionTransactionBytes:) to keep host-owned raw fusion transaction bytes explicit."
        )
        public init(transactionBytes: [UInt8]) {
            self.init(signedFusionTransactionBytes: transactionBytes)
        }
    }
}

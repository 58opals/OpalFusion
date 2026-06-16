// OpalFusion+Host+TransactionFinalizationProposal.swift

import OpalDiagnostics

public extension OpalFusion.Host {
    /// A host-facing proposal describing the unsigned CashFusion transaction OpalFusion expects the host to validate and sign.
    ///
    /// The raw bytes are wallet-owned transaction material. They are never display-safe or diagnostics-safe by default.
    struct TransactionFinalizationProposal: Sendable, Equatable {
        /// The full BCH wire-format unsigned fusion transaction bytes derived from the current round.
        public let unsignedFusionTransactionBytes: [UInt8]
        /// The server-provided session hash, when available for cross-checking.
        public let sessionHash: [UInt8]?
        /// The expected transaction input count implied by the shared round components.
        public let expectedInputCount: Int?
        /// The expected transaction output count implied by the shared round components.
        public let expectedOutputCount: Int?
        /// The participant count known for the round, when available.
        public let participantCount: Int?
        public var isDiagnosticsSafe: Bool { false }
        public var diagnosticsPrivacy: OpalDiagnostics.FieldPrivacy { .private }

        public init(
            unsignedFusionTransactionBytes: [UInt8],
            sessionHash: [UInt8]? = nil,
            expectedInputCount: Int? = nil,
            expectedOutputCount: Int? = nil,
            participantCount: Int? = nil
        ) {
            self.unsignedFusionTransactionBytes = unsignedFusionTransactionBytes
            self.sessionHash = sessionHash
            self.expectedInputCount = expectedInputCount
            self.expectedOutputCount = expectedOutputCount
            self.participantCount = participantCount
        }

        @available(
            *,
            deprecated,
            renamed: "unsignedFusionTransactionBytes",
            message: "Use unsignedFusionTransactionBytes to keep raw fusion transaction byte ownership explicit."
        )
        public var unsignedTransactionBytes: [UInt8] {
            unsignedFusionTransactionBytes
        }

        @available(
            *,
            deprecated,
            message: "Use init(unsignedFusionTransactionBytes:sessionHash:expectedInputCount:expectedOutputCount:participantCount:) to keep raw fusion transaction byte ownership explicit."
        )
        public init(
            unsignedTransactionBytes: [UInt8],
            sessionHash: [UInt8]? = nil,
            expectedInputCount: Int? = nil,
            expectedOutputCount: Int? = nil,
            participantCount: Int? = nil
        ) {
            self.init(
                unsignedFusionTransactionBytes: unsignedTransactionBytes,
                sessionHash: sessionHash,
                expectedInputCount: expectedInputCount,
                expectedOutputCount: expectedOutputCount,
                participantCount: participantCount
            )
        }
    }
}

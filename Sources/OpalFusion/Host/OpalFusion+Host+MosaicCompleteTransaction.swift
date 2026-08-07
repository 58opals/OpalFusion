// OpalFusion+Host+MosaicCompleteTransaction.swift

import OpalDiagnostics

public extension OpalFusion.Host {
    /// Fully assembled BCH transaction bytes presented to the wallet for independent verification and commit.
    ///
    /// Construction validates only that bytes are present. The wallet host remains responsible for parsing the
    /// transaction, verifying every input and transcript-bound policy rule, and persisting it before commit.
    struct MosaicCompleteTransaction: Sendable, Equatable {
        /// Complete BCH wire-format transaction bytes, including every contributor signature.
        public let transactionBytes: [UInt8]
        public var isDiagnosticsSafe: Bool { false }
        public var diagnosticsPrivacy: OpalDiagnostics.FieldPrivacy { .private }

        public init(transactionBytes: [UInt8]) throws {
            guard !transactionBytes.isEmpty else {
                throw MosaicHostContractError.emptyCompleteTransaction
            }
            self.transactionBytes = transactionBytes
        }
    }
}

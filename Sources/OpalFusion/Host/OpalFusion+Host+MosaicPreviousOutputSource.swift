// OpalFusion+Host+MosaicPreviousOutputSource.swift

import OpalDiagnostics

public extension OpalFusion.Host {
    /// One transcript-committed outpoint whose previous output must be resolved before signing.
    ///
    /// An outpoint and amount can identify wallet activity. Treat this value as diagnostics-private.
    struct MosaicPreviousOutputRequest: Sendable, Equatable, Hashable {
        /// The 32-byte transaction identifier in standard display order.
        public let transactionHashBytes: [UInt8]
        public let outputIndex: UInt32
        public let expectedAmountSatoshis: UInt64
        public var isDiagnosticsSafe: Bool { false }
        public var diagnosticsPrivacy: OpalDiagnostics.FieldPrivacy { .private }

        public init(
            transactionHashBytes: [UInt8],
            outputIndex: UInt32,
            expectedAmountSatoshis: UInt64
        ) throws {
            guard transactionHashBytes.count == 32 else {
                throw MosaicHostContractError
                    .invalidPreviousOutputHashLength(
                        actual: transactionHashBytes.count
                    )
            }
            guard expectedAmountSatoshis > 0 else {
                throw MosaicHostContractError.zeroExpectedPreviousOutputAmount
            }
            self.transactionHashBytes = Array(transactionHashBytes)
            self.outputIndex = outputIndex
            self.expectedAmountSatoshis = expectedAmountSatoshis
        }
    }

    /// Whether a resolved previous output carries CashToken data.
    enum MosaicPreviousOutputTokenState: Sendable, Equatable {
        case absent
        case present
    }

    /// Source-asserted previous-output data obtained from an authoritative transaction reader.
    ///
    /// Transaction bytes, scripts, and amounts can identify wallet activity. Treat this whole
    /// value as diagnostics-private. The transcript resolver accepts only `.absent` token state.
    struct MosaicPreviousOutput: Sendable, Equatable {
        /// The 32-byte transaction identifier in standard display order.
        public let transactionHashBytes: [UInt8]
        public let outputIndex: UInt32
        public let amountSatoshis: UInt64
        public let lockingScriptBytes: [UInt8]
        public let tokenState: MosaicPreviousOutputTokenState
        public var isDiagnosticsSafe: Bool { false }
        public var diagnosticsPrivacy: OpalDiagnostics.FieldPrivacy { .private }

        public init(
            transactionHashBytes: [UInt8],
            outputIndex: UInt32,
            amountSatoshis: UInt64,
            lockingScriptBytes: [UInt8],
            tokenState: MosaicPreviousOutputTokenState
        ) throws {
            guard transactionHashBytes.count == 32 else {
                throw MosaicHostContractError
                    .invalidPreviousOutputHashLength(
                        actual: transactionHashBytes.count
                    )
            }
            guard amountSatoshis > 0 else {
                throw MosaicHostContractError.zeroResolvedPreviousOutputAmount
            }
            guard !lockingScriptBytes.isEmpty else {
                throw MosaicHostContractError
                    .emptyResolvedPreviousOutputLockingScript
            }
            self.transactionHashBytes = Array(transactionHashBytes)
            self.outputIndex = outputIndex
            self.amountSatoshis = amountSatoshis
            self.lockingScriptBytes = Array(lockingScriptBytes)
            self.tokenState = tokenState
        }
    }

    /// Resolves transcript-committed outpoints without granting signing or broadcast authority.
    ///
    /// Implementations must use an authoritative transaction reader, validate the fetched
    /// transaction identifier and output index, and report token presence exactly. The wallet
    /// host must independently repeat those checks at signing time.
    protocol MosaicPreviousOutputSource: Sendable {
        func resolvePreviousOutputs(
            for requests: [MosaicPreviousOutputRequest]
        ) async throws -> [MosaicPreviousOutput]
    }
}

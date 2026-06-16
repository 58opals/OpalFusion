// OpalFusion+Host+ParticipantInput.swift

import OpalDiagnostics

public extension OpalFusion.Host {
    /// Wallet-owned input reservation material for one CashFusion participant component.
    ///
    /// Outpoints, locking scripts, and public keys can identify wallet activity. Treat this whole value as host-owned and diagnostics-private.
    struct ParticipantInput: Sendable, Equatable {
        /// The 32-byte transaction identifier in standard display order.
        /// Reverse these bytes only when encoding BCH wire or protobuf fields.
        public let outpointTransactionHashBytes: [UInt8]
        public let outpointIndex: UInt32
        public let amountSatoshis: UInt64
        /// The full serialized BCH locking script bytecode for the reserved input. This is not display-safe or diagnostics-safe.
        public let lockingScriptBytes: [UInt8]
        /// The compressed public key for the reserved input when the host can provide it. This can be participant-identifying.
        public let publicKey: [UInt8]?
        public var isDiagnosticsSafe: Bool { false }
        public var diagnosticsPrivacy: OpalDiagnostics.FieldPrivacy { .private }

        public init(
            outpointTransactionHashBytes: [UInt8],
            outpointIndex: UInt32,
            amountSatoshis: UInt64,
            lockingScriptBytes: [UInt8],
            publicKey: [UInt8]? = nil
        ) {
            self.outpointTransactionHashBytes = outpointTransactionHashBytes
            self.outpointIndex = outpointIndex
            self.amountSatoshis = amountSatoshis
            self.lockingScriptBytes = lockingScriptBytes
            self.publicKey = publicKey
        }
    }
}

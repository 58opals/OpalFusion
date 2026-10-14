// OpalFusion+Host+ParticipantOutput.swift

import OpalDiagnostics

public extension OpalFusion.Host {
    /// Wallet-owned output reservation material for one collaborative-fusion participant component.
    ///
    /// Locking scripts can encode addresses or address-equivalent material. Treat this value as host-owned and diagnostics-private.
    struct ParticipantOutput: Sendable, Equatable {
        /// The full serialized BCH locking script bytecode for the reserved output. This is not display-safe or diagnostics-safe.
        public let lockingScriptBytes: [UInt8]
        public let amountSatoshis: UInt64
        public var isDiagnosticsSafe: Bool { false }
        public var diagnosticsPrivacy: OpalDiagnostics.FieldPrivacy { .private }

        public init(
            lockingScriptBytes: [UInt8],
            amountSatoshis: UInt64
        ) {
            self.lockingScriptBytes = lockingScriptBytes
            self.amountSatoshis = amountSatoshis
        }
    }
}

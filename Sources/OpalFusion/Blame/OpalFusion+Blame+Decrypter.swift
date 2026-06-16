// OpalFusion+Blame+Decrypter.swift

import OpalDiagnostics

public extension OpalFusion.Blame {
    /// Secret material a client reveals only when substantiating a CashFusion blame claim.
    ///
    /// Decrypters carry session keys or private keys and are never display-safe or diagnostics-safe by default.
    enum Decrypter: Sendable, Equatable {
        case sessionKey(secretBytes: [UInt8])
        case privateKey(secretBytes: [UInt8])

        public var secretMaterialByteCount: Int {
            switch self {
            case let .sessionKey(secretBytes), let .privateKey(secretBytes):
                secretBytes.count
            }
        }

        public var isDiagnosticsSafe: Bool { false }
        public var diagnosticsPrivacy: OpalDiagnostics.FieldPrivacy { .private }
    }
}

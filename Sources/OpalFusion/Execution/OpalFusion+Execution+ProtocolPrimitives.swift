// OpalFusion+Execution+ProtocolPrimitives.swift

import Foundation
import OpalCrypto
import Security

extension OpalFusion.Execution {
    enum ProtocolPrimitives {
        static let pedersenAlternateBasePoint = Data([0x02]) + Data(
            "CashFusion gives us fungibility.".utf8
        )
        static let pedersenAlternateBasePublicKey = try! OpalCrypto.Secp256k1.PublicKey(
            rawRepresentation: pedersenAlternateBasePoint
        )
        static let supportedParticipantInputSummary =
            "Only standard compressed-key P2PKH participant inputs are supported"
        static let supportedUnlockingScriptSummary =
            "Only standard compressed-key Schnorr P2PKH unlocking scripts are supported"
        static let maximumMoneySatoshis: UInt64 = 2_100_000_000_000_000



















    }
}

// OpalFusion+Execution+ProtocolPrimitives.swift

import Foundation
import OpalCrypto

package extension OpalFusion.Execution {
    enum ProtocolPrimitives {
        package static let maximumMoneySatoshis: UInt64 = 2_100_000_000_000_000
    }
}

package extension OpalFusion.Execution.ProtocolPrimitives {
    static func sha256(_ bytes: [UInt8]) -> [UInt8] {
        Array(OpalCrypto.Hashing.sha256(Data(bytes)))
    }

    static func hash256(_ bytes: [UInt8]) -> [UInt8] {
        Array(OpalCrypto.Hashing.hash256(Data(bytes)))
    }

    static func hash160(_ bytes: [UInt8]) -> [UInt8] {
        Array(OpalCrypto.Hashing.hash160(Data(bytes)))
    }

    static func isCompressedSecp256k1PublicKey(
        _ publicKey: [UInt8]
    ) -> Bool {
        guard publicKey.count == 33 && (publicKey.first == 0x02 || publicKey.first == 0x03) else {
            return false
        }

        return (try? OpalCrypto.Secp256k1.PublicKey(rawRepresentation: Data(publicKey))) != nil
    }

    static func isStandardP2PKHLockingScript(
        _ lockingScript: [UInt8],
        publicKey: [UInt8]
    ) -> Bool {
        guard lockingScript.count == 25 else {
            return false
        }
        guard lockingScript[0] == 0x76,
              lockingScript[1] == 0xA9,
              lockingScript[2] == 0x14,
              lockingScript[23] == 0x88,
              lockingScript[24] == 0xAC else {
            return false
        }

        let publicKeyHash = hash160(publicKey)
        return Array(lockingScript[3..<23]) == publicKeyHash
    }
}

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

        static func randomBytes(count: Int) throws -> [UInt8] {
            var bytes = [UInt8](repeating: 0x00, count: count)
            guard SecRandomCopyBytes(kSecRandomDefault, count, &bytes) == errSecSuccess else {
                throw OpalFusion.Execution.WorkflowFailure.unsupportedExecution(
                    "Secure random generation failed"
                )
            }
            return bytes
        }

        static func sha256(_ bytes: [UInt8]) -> [UInt8] {
            Array(OpalCrypto.Hashing.sha256(Data(bytes)))
        }

        static func hash256(_ bytes: [UInt8]) -> [UInt8] {
            Array(OpalCrypto.Hashing.hash256(Data(bytes)))
        }

        static func hash160(_ bytes: [UInt8]) -> [UInt8] {
            Array(OpalCrypto.Hashing.hash160(Data(bytes)))
        }

        static func listHash(_ items: [[UInt8]]) -> [UInt8] {
            var buffer = [UInt8]()
            for item in items {
                buffer.append(contentsOf: UInt32(item.count).bigEndianBytes)
                buffer.append(contentsOf: item)
            }
            return sha256(buffer)
        }

        static func calculateInitialHash(
            fusionBegin: OpalFusion.ProtocolModel.FusionBegin,
            baseline: OpalFusion.Transport.BaselineConfiguration
        ) -> [UInt8] {
            listHash(
                [
                    Array("Cash Fusion Session".utf8),
                    baseline.protocolIdentity.versionBytes,
                    fusionBegin.tier.bigEndianBytes,
                    Array(fusionBegin.covertDomain.utf8),
                    fusionBegin.covertPort.bigEndianBytes,
                    [fusionBegin.covertSsl == true ? 0x01 : 0x00],
                    fusionBegin.serverTimeUnixSeconds.bigEndianBytes
                ]
            )
        }

        static func calculateRoundHash(
            previousHash: [UInt8],
            startRound: OpalFusion.ProtocolModel.StartRound,
            allCommitmentBytes: [[UInt8]],
            allComponentBytes: [[UInt8]]
        ) -> [UInt8] {
            listHash(
                [
                    Array("Cash Fusion Round".utf8),
                    previousHash,
                    startRound.roundPublicKey,
                    startRound.serverTimeUnixSeconds.bigEndianBytes,
                    listHash(allCommitmentBytes),
                    listHash(allComponentBytes)
                ]
            )
        }

        static func inputSize(for publicKey: [UInt8]) -> Int {
            108 + publicKey.count
        }

        static func outputSize(for lockingScript: [UInt8]) -> Int {
            9 + lockingScript.count
        }

        static func componentFee(
            sizeBytes: Int,
            feeRateSatoshisPerKb: UInt64
        ) -> UInt64 {
            guard sizeBytes >= 0 else {
                return UInt64.max
            }

            let product = UInt64(sizeBytes)
                .multipliedReportingOverflow(by: feeRateSatoshisPerKb)
            guard product.overflow == false else {
                return UInt64.max
            }

            let rounded = product.partialValue.addingReportingOverflow(999)
            guard rounded.overflow == false else {
                return UInt64.max
            }

            return rounded.partialValue / 1_000
        }

        static func dustLimit(lockingScriptLength: Int) -> UInt64 {
            UInt64(3 * (lockingScriptLength + 148))
        }

        static func minimumOutputAmount(
            for lockingScript: [UInt8],
            baseline: OpalFusion.Transport.BaselineConfiguration
        ) -> UInt64 {
            max(
                baseline.protocolIdentity.minimumOutputAmountSatoshis,
                dustLimit(lockingScriptLength: lockingScript.count)
            )
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

        static func validateSupportedParticipantInput(
            _ input: OpalFusion.Host.ParticipantInput,
            inputIndex: Int
        ) throws -> [UInt8] {
            guard let publicKey = input.publicKey else {
                throw OpalFusion.Execution.WorkflowFailure.missingParticipantInputPublicKey(
                    index: inputIndex
                )
            }
            guard isCompressedSecp256k1PublicKey(publicKey) else {
                throw OpalFusion.Execution.WorkflowFailure.invalidParticipantReservation(
                    "Participant input at index \(inputIndex) must provide the compressed public key required for standard P2PKH support"
                )
            }
            guard isStandardP2PKHLockingScript(
                input.lockingScriptBytes,
                publicKey: publicKey
            ) else {
                throw OpalFusion.Execution.WorkflowFailure.unsupportedExecution(
                    supportedParticipantInputSummary
                )
            }
            return publicKey
        }

        static func makeSessionHashLockingScript(
            sessionHash: [UInt8],
            baseline: OpalFusion.Transport.BaselineConfiguration
        ) -> [UInt8] {
            var script = [UInt8]()
            script.append(0x6A)

            let lokad = baseline.protocolIdentity.fusionLokadId
            if lokad.isEmpty == false {
                appendPushData(lokad, to: &script)
            }

            appendPushData(sessionHash, to: &script)
            return script
        }

        private static func appendPushData(
            _ bytes: [UInt8],
            to script: inout [UInt8]
        ) {
            if bytes.count <= 75 {
                script.append(UInt8(bytes.count))
            } else if bytes.count <= Int(UInt8.max) {
                script.append(0x4C)
                script.append(UInt8(bytes.count))
            } else if bytes.count <= Int(UInt16.max) {
                script.append(0x4D)
                script.append(contentsOf: UInt16(bytes.count).littleEndianBytes)
            } else {
                script.append(0x4E)
                script.append(contentsOf: UInt32(bytes.count).littleEndianBytes)
            }

            script.append(contentsOf: bytes)
        }

        static func randPosition(
            seed: [UInt8],
            numberOfPositions: Int,
            counter: Int
        ) -> Int {
            precondition(numberOfPositions > 0)
            let digest = sha256(seed + UInt32(counter).bigEndianBytes)
            let upper64 = UInt64(bigEndianBytes: Array(digest.prefix(8)))
            let scaled = upper64.multipliedFullWidth(by: UInt64(numberOfPositions))
            return Int(scaled.high)
        }

        static func sumNoncesModOrder(
            _ nonces: [[UInt8]]
        ) throws -> [UInt8] {
            var accumulator = Scalar256Value.zero
            for nonce in nonces {
                accumulator = try accumulator.addingModuloOrder(bytes: nonce)
            }

            guard accumulator.isZero == false else {
                throw OpalFusion.Execution.WorkflowFailure.protocolValidationFailed(
                    "Pedersen total nonce resolved to zero"
                )
            }
            return accumulator.bytes32
        }
    }
}
private extension UInt16 {
    var littleEndianBytes: [UInt8] {
        withUnsafeBytes(of: self.littleEndian) { Array($0) }
    }
}

private extension UInt32 {
    var bigEndianBytes: [UInt8] {
        withUnsafeBytes(of: self.bigEndian) { Array($0) }
    }

    var littleEndianBytes: [UInt8] {
        withUnsafeBytes(of: self.littleEndian) { Array($0) }
    }
}

private extension UInt64 {
    var bigEndianBytes: [UInt8] {
        withUnsafeBytes(of: self.bigEndian) { Array($0) }
    }

    init(bigEndianBytes: [UInt8]) {
        precondition(bigEndianBytes.count == 8)
        self = bigEndianBytes.reduce(0) { ($0 << 8) | UInt64($1) }
    }
}

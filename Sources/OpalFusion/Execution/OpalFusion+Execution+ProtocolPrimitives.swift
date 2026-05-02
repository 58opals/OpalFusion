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
            ((UInt64(sizeBytes) * feeRateSatoshisPerKb) + 999) / 1_000
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
                script.append(UInt8(lokad.count))
                script.append(contentsOf: lokad)
            }

            script.append(UInt8(sessionHash.count))
            script.append(contentsOf: sessionHash)
            return script
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
            var accumulator = Scalar256.zero
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

private struct Scalar256 {
    static let zero = Scalar256(limbs: (0, 0, 0, 0))
    static let order = Scalar256(
        limbs: (
            0xBFD25E8CD0364141,
            0xBAAEDCE6AF48A03B,
            0xFFFFFFFFFFFFFFFE,
            0xFFFFFFFFFFFFFFFF
        )
    )
    static let twoTo256MinusOrder = Scalar256(
        limbs: (
            0x402DA1732FC9BEBF,
            0x4551231950B75FC4,
            0x0000000000000001,
            0x0000000000000000
        )
    )

    let limbs: (UInt64, UInt64, UInt64, UInt64)

    var isZero: Bool {
        limbs.0 == 0 && limbs.1 == 0 && limbs.2 == 0 && limbs.3 == 0
    }

    var bytes32: [UInt8] {
        limbs.3.bigEndianBytes
            + limbs.2.bigEndianBytes
            + limbs.1.bigEndianBytes
            + limbs.0.bigEndianBytes
    }

    func addingModuloOrder(bytes: [UInt8]) throws -> Scalar256 {
        let other = try Scalar256(bytes32: bytes)
        let (sum, carried) = adding(other)
        if carried {
            return sum.adding(Scalar256.twoTo256MinusOrder).sum
        }
        if sum.compare(to: .order) != .orderedAscending {
            return sum.subtracting(.order)
        }
        return sum
    }

    func compare(to other: Scalar256) -> ComparisonResult {
        let lhs = [limbs.3, limbs.2, limbs.1, limbs.0]
        let rhs = [other.limbs.3, other.limbs.2, other.limbs.1, other.limbs.0]
        for (left, right) in zip(lhs, rhs) {
            if left < right {
                return .orderedAscending
            }
            if left > right {
                return .orderedDescending
            }
        }
        return .orderedSame
    }

    private func adding(_ other: Scalar256) -> (sum: Scalar256, carry: Bool) {
        let (l0, c0) = limbs.0.addingReportingOverflow(other.limbs.0)
        let (l1p, c1p) = limbs.1.addingReportingOverflow(other.limbs.1)
        let (l1, c1) = l1p.addingReportingOverflow(c0 ? 1 : 0)
        let (l2p, c2p) = limbs.2.addingReportingOverflow(other.limbs.2)
        let (l2, c2) = l2p.addingReportingOverflow((c1p || c1) ? 1 : 0)
        let (l3p, c3p) = limbs.3.addingReportingOverflow(other.limbs.3)
        let (l3, c3) = l3p.addingReportingOverflow((c2p || c2) ? 1 : 0)
        return (
            Scalar256(limbs: (l0, l1, l2, l3)),
            c3p || c3
        )
    }

    private func subtracting(_ other: Scalar256) -> Scalar256 {
        let (l0, b0) = limbs.0.subtractingReportingOverflow(other.limbs.0)
        let (l1p, b1p) = limbs.1.subtractingReportingOverflow(other.limbs.1)
        let (l1, b1) = l1p.subtractingReportingOverflow(b0 ? 1 : 0)
        let (l2p, b2p) = limbs.2.subtractingReportingOverflow(other.limbs.2)
        let (l2, b2) = l2p.subtractingReportingOverflow((b1p || b1) ? 1 : 0)
        let (l3p, b3p) = limbs.3.subtractingReportingOverflow(other.limbs.3)
        let (l3, b3) = l3p.subtractingReportingOverflow((b2p || b2) ? 1 : 0)
        precondition((b3p || b3) == false)
        return Scalar256(limbs: (l0, l1, l2, l3))
    }

    private init(limbs: (UInt64, UInt64, UInt64, UInt64)) {
        self.limbs = limbs
    }

    private init(bytes32: [UInt8]) throws {
        guard bytes32.count == 32 else {
            throw OpalFusion.Execution.WorkflowFailure.protocolValidationFailed(
                "Expected a 32-byte scalar"
            )
        }
        self.limbs = (
            UInt64(bigEndianBytes: Array(bytes32[24..<32])),
            UInt64(bigEndianBytes: Array(bytes32[16..<24])),
            UInt64(bigEndianBytes: Array(bytes32[8..<16])),
            UInt64(bigEndianBytes: Array(bytes32[0..<8]))
        )
    }
}

private extension UInt32 {
    var bigEndianBytes: [UInt8] {
        withUnsafeBytes(of: self.bigEndian) { Array($0) }
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

import OpalFusionCore

// OpalFusion+Execution+ProtocolPrimitives+ImplementationGroup1.swift

import Foundation
import OpalCrypto
import Security

extension OpalFusion.Execution.ProtocolPrimitives {
    static func randomBytes(count: Int) throws -> [UInt8] {
        guard count >= 0 else {
            throw OpalFusion.Execution.WorkflowFailure.unsupportedExecution(
                "Secure random byte count must not be negative"
            )
        }
        var bytes = [UInt8](repeating: 0x00, count: count)
        guard SecRandomCopyBytes(kSecRandomDefault, count, &bytes) == errSecSuccess else {
            throw OpalFusion.Execution.WorkflowFailure.unsupportedExecution(
                "Secure random generation failed"
            )
        }
        return bytes
    }

    static func listHash(_ items: [[UInt8]]) -> [UInt8] {
        var buffer = [UInt8]()
        for item in items {
            buffer.append(contentsOf: UInt32(item.count).opalFusionBigEndianBytes)
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
                fusionBegin.tier.opalFusionBigEndianBytes,
                Array(fusionBegin.covertDomain.utf8),
                fusionBegin.covertPort.opalFusionBigEndianBytes,
                [fusionBegin.covertSsl == true ? 0x01 : 0x00],
                fusionBegin.serverTimeUnixSeconds.opalFusionBigEndianBytes
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
                startRound.serverTimeUnixSeconds.opalFusionBigEndianBytes,
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
        guard lockingScriptLength >= 0 else {
            return UInt64.max
        }

        let inputSize = UInt64(lockingScriptLength)
            .addingReportingOverflow(148)
        guard inputSize.overflow == false else {
            return UInt64.max
        }

        let dustLimit = inputSize.partialValue
            .multipliedReportingOverflow(by: 3)
        guard dustLimit.overflow == false else {
            return UInt64.max
        }

        return dustLimit.partialValue
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

}

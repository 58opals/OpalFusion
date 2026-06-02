// OpalFusion+Execution+ProtocolPrimitives+ImplementationGroup2.swift

import Foundation
import OpalCrypto
import Security

extension OpalFusion.Execution.ProtocolPrimitives {
    static func validateSupportedParticipantInput(
        _ input: OpalFusion.Host.ParticipantInput,
        inputIndex: Int
    ) throws -> [UInt8] {
        guard let publicKey = input.publicKey else {
            throw OpalFusion.Execution.WorkflowFailure.missingParticipantInputPublicKey(
                index: inputIndex
            )
        }
        guard input.outpointTransactionHashBytes.count == 32 else {
            throw OpalFusion.Execution.WorkflowFailure.invalidParticipantReservation(
                "Participant input at index \(inputIndex) previous transaction hash must be 32 bytes"
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

    static func appendPushData(
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
            script.append(contentsOf: UInt16(bytes.count).opalFusionLittleEndianBytes)
        } else {
            script.append(0x4E)
            script.append(contentsOf: UInt32(bytes.count).opalFusionLittleEndianBytes)
        }

        script.append(contentsOf: bytes)
    }

    static func randPosition(
        seed: [UInt8],
        numberOfPositions: Int,
        counter: Int
    ) -> Int {
        precondition(numberOfPositions > 0)
        let digest = sha256(seed + UInt32(counter).opalFusionBigEndianBytes)
        let upper64 = UInt64(opalFusionBigEndianBytes: Array(digest.prefix(8)))
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

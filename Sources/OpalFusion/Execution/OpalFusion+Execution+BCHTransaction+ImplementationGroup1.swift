// OpalFusion+Execution+BCHTransaction+ImplementationGroup1.swift

import Foundation

extension OpalFusion.Execution.BCHTransaction {
    func serialize() throws -> [UInt8] {
        guard inputs.isEmpty == false else {
            throw OpalFusion.Execution.BCHTransactionError.malformed(
                "Transaction must contain at least one input"
            )
        }

        guard outputs.isEmpty == false else {
            throw OpalFusion.Execution.BCHTransactionError.malformed(
                "Transaction must contain at least one output"
            )
        }

        var bytes = [UInt8]()
        bytes.append(contentsOf: version.opalFusionLittleEndianBytes)
        bytes.append(contentsOf: try Self.encodeCompactSize(inputs.count))
        for input in inputs {
            guard input.previousTransactionHashLittleEndian.count == 32 else {
                throw OpalFusion.Execution.BCHTransactionError.malformed(
                    "Transaction input previous hash must be 32 bytes"
                )
            }
            bytes.append(contentsOf: input.previousTransactionHashLittleEndian)
            bytes.append(contentsOf: input.previousOutputIndex.opalFusionLittleEndianBytes)
            bytes.append(contentsOf: try Self.encodeCompactSize(input.unlockingScript.count))
            bytes.append(contentsOf: input.unlockingScript)
            bytes.append(contentsOf: input.sequence.opalFusionLittleEndianBytes)
        }

        bytes.append(contentsOf: try Self.encodeCompactSize(outputs.count))
        bytes.append(contentsOf: try serializeOutputs())
        bytes.append(contentsOf: lockTime.opalFusionLittleEndianBytes)
        return bytes
    }

    func settingUnlockingScript(
        _ unlockingScript: [UInt8],
        at inputIndex: Int
    ) throws -> OpalFusion.Execution.BCHTransaction {
        guard inputs.indices.contains(inputIndex) else {
            throw OpalFusion.Execution.BCHTransactionError.malformed(
                "Transaction input index \(inputIndex) is out of bounds"
            )
        }
        var copy = self
        copy.inputs[inputIndex].unlockingScript = unlockingScript
        return copy
    }

    func signatureHash(
        forInputAt inputIndex: Int,
        lockingScript: [UInt8],
        amountSatoshis: UInt64,
        sighashType: UInt32 = 0x41
    ) throws -> [UInt8] {
        guard sighashType == 0x41 else {
            throw OpalFusion.Execution.BCHTransactionError.malformed(
                "Unsupported BCH signature hash type"
            )
        }
        guard inputs.indices.contains(inputIndex) else {
            throw OpalFusion.Execution.BCHTransactionError.malformed(
                "Transaction input index \(inputIndex) is out of bounds"
            )
        }
        guard inputs.allSatisfy({ $0.previousTransactionHashLittleEndian.count == 32 }) else {
            throw OpalFusion.Execution.BCHTransactionError.malformed(
                "Transaction input previous hash must be 32 bytes"
            )
        }
        guard amountSatoshis <= OpalFusion.Execution.ProtocolPrimitives.maximumMoneySatoshis else {
            throw OpalFusion.Execution.BCHTransactionError.malformed(
                "Transaction input amount exceeds the maximum BCH money supply"
            )
        }
        guard outputs.isEmpty == false else {
            throw OpalFusion.Execution.BCHTransactionError.malformed(
                "Transaction must contain at least one output"
            )
        }

        let hashPrevouts = OpalFusion.Execution.ProtocolPrimitives.hash256(
            inputs.flatMap { input in
                input.previousTransactionHashLittleEndian
                    + input.previousOutputIndex.opalFusionLittleEndianBytes
            }
        )
        let hashSequence = OpalFusion.Execution.ProtocolPrimitives.hash256(
            inputs.flatMap { $0.sequence.opalFusionLittleEndianBytes }
        )
        let hashOutputs = OpalFusion.Execution.ProtocolPrimitives.hash256(
            try serializeOutputs()
        )
        let input = inputs[inputIndex]
        var preimage = [UInt8]()
        preimage.append(contentsOf: version.opalFusionLittleEndianBytes)
        preimage.append(contentsOf: hashPrevouts)
        preimage.append(contentsOf: hashSequence)
        preimage.append(contentsOf: input.previousTransactionHashLittleEndian)
        preimage.append(contentsOf: input.previousOutputIndex.opalFusionLittleEndianBytes)
        preimage.append(contentsOf: try Self.encodeCompactSize(lockingScript.count))
        preimage.append(contentsOf: lockingScript)
        preimage.append(contentsOf: amountSatoshis.opalFusionLittleEndianBytes)
        preimage.append(contentsOf: input.sequence.opalFusionLittleEndianBytes)
        preimage.append(contentsOf: hashOutputs)
        preimage.append(contentsOf: lockTime.opalFusionLittleEndianBytes)
        preimage.append(contentsOf: sighashType.opalFusionLittleEndianBytes)
        return OpalFusion.Execution.ProtocolPrimitives.hash256(preimage)
    }
}

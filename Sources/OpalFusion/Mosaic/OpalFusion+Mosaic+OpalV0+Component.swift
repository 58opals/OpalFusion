// OpalFusion+Mosaic+OpalV0+Component.swift

extension OpalFusion.Mosaic.OpalV0 {
    struct InputComponent: Sendable, Equatable, Hashable {
        let previousTransactionHash: [UInt8]
        let outputIndex: UInt32
        let amountSatoshis: UInt64

        init(
            previousTransactionHash: [UInt8],
            outputIndex: UInt32,
            amountSatoshis: UInt64
        ) throws {
            guard previousTransactionHash.count
                == OpalFusion.Mosaic.OpalV0.digestByteCount else {
                throw WireContractError.invalidInputTransactionHashLength(
                    actual: previousTransactionHash.count
                )
            }
            try OpalFusion.Mosaic.OpalV0.validateComponentAmount(
                amountSatoshis
            )
            self.previousTransactionHash = Array(previousTransactionHash)
            self.outputIndex = outputIndex
            self.amountSatoshis = amountSatoshis
        }
    }

    struct OutputComponent: Sendable, Equatable {
        let lockingScript: [UInt8]
        let amountSatoshis: UInt64

        init(lockingScript: [UInt8], amountSatoshis: UInt64) throws {
            guard OpalFusion.Mosaic.OpalV0.isStandardP2PKHLockingScript(
                lockingScript
            ) else {
                throw WireContractError.invalidP2PKHLockingScript
            }
            try OpalFusion.Mosaic.OpalV0.validateComponentAmount(
                amountSatoshis
            )
            self.lockingScript = Array(lockingScript)
            self.amountSatoshis = amountSatoshis
        }
    }

    enum ComponentPayload: Sendable, Equatable {
        case input(InputComponent)
        case output(OutputComponent)
        case blank
    }

    struct Component: Sendable, Equatable {
        let saltCommitment: [UInt8]
        let payload: ComponentPayload

        init(
            saltCommitment: [UInt8],
            payload: ComponentPayload
        ) throws {
            guard saltCommitment.count == OpalFusion.Mosaic.OpalV0.digestByteCount else {
                throw WireContractError.invalidSaltCommitmentLength(
                    actual: saltCommitment.count
                )
            }
            self.saltCommitment = Array(saltCommitment)
            self.payload = payload
        }
    }

    private static func validateComponentAmount(_ amountSatoshis: UInt64) throws {
        guard amountSatoshis > 0,
              amountSatoshis <= OpalFusion.Mosaic.OpalV0.maximumMoneySatoshis else {
            throw WireContractError.invalidComponentAmount(
                actual: amountSatoshis
            )
        }
    }

    private static func isStandardP2PKHLockingScript(
        _ lockingScript: [UInt8]
    ) -> Bool {
        lockingScript.count == OpalFusion.Mosaic.OpalV0.p2pkhLockingScriptByteCount
            && lockingScript[0] == 0x76
            && lockingScript[1] == 0xA9
            && lockingScript[2] == 0x14
            && lockingScript[23] == 0x88
            && lockingScript[24] == 0xAC
    }
}

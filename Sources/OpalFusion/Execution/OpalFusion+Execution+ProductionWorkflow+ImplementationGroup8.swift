// OpalFusion+Execution+ProductionWorkflow+ImplementationGroup8.swift

import Foundation
import OpalCrypto
import OpalDiagnostics

extension OpalFusion.Execution.ProductionWorkflow {
    func decodeComponent(
        bytes: [UInt8],
        componentIndex: Int
    ) throws -> OpalFusion.Execution.DecodedComponent {
        let message = try parseComponent(bytes: bytes)
        guard message.saltCommitment.count == 32 else {
            throw OpalFusion.Execution.WorkflowFailure.protocolValidationFailed(
                "Shared component at index \(componentIndex) salt commitment must be 32 bytes"
            )
        }

        let payload: OpalFusion.Commitment.ComponentPayload
        switch message.payload {
        case let .input(input):
            guard input.outpointTransactionHash.count == 32 else {
                throw OpalFusion.Execution.WorkflowFailure.protocolValidationFailed(
                    "Shared input component at index \(componentIndex) previous transaction hash must be 32 bytes"
                )
            }

            guard input.amountSatoshis <= OpalFusion.Execution.ProtocolPrimitives.maximumMoneySatoshis else {
                throw OpalFusion.Execution.WorkflowFailure.protocolValidationFailed(
                    "Shared input component at index \(componentIndex) exceeds the maximum BCH money supply"
                )
            }
            guard OpalFusion.Execution.ProtocolPrimitives.isCompressedSecp256k1PublicKey(
                input.publicKey
            ) else {
                throw OpalFusion.Execution.WorkflowFailure.protocolValidationFailed(
                    "Shared input component at index \(componentIndex) must provide a valid compressed public key"
                )
            }

            payload = .input(input)
        case let .output(output):
            guard output.amountSatoshis <= OpalFusion.Execution.ProtocolPrimitives.maximumMoneySatoshis else {
                throw OpalFusion.Execution.WorkflowFailure.protocolValidationFailed(
                    "Shared output component at index \(componentIndex) exceeds the maximum BCH money supply"
                )
            }

            let minimumAmount = OpalFusion.Execution.ProtocolPrimitives.minimumOutputAmount(
                for: output.lockingScript,
                baseline: baseline
            )
            guard output.amountSatoshis >= minimumAmount else {
                throw OpalFusion.Execution.WorkflowFailure.protocolValidationFailed(
                    "Shared output component at index \(componentIndex) is below the minimum allowed amount"
                )
            }

            payload = .output(output)
        case .blank(_):
            payload = .blank(.init())
        case .none:
            throw OpalFusion.Execution.WorkflowFailure.protocolValidationFailed(
                "Shared component was missing its payload"
            )
        }
        return .init(
            serializedComponent: bytes,
            saltCommitment: message.saltCommitment,
            payload: payload
        )
    }

    func parseComponent(
        bytes: [UInt8]
    ) throws -> OpalFusion.Wire.CashFusionComponentData {
        do {
            return try OpalFusion.Wire.CashFusionComponentCodec.decode(bytes)
        } catch let error as OpalFusion.Execution.WorkflowFailure {
            throw error
        } catch {
            throw OpalFusion.Execution.WorkflowFailure.protocolValidationFailed(
                "Component decode failed"
            )
        }
    }

    func parseInitialCommitment(
        bytes: [UInt8]
    ) throws -> OpalFusion.Commitment.InitialCommitment {
        do {
            return try OpalFusion.Wire.CashFusionInitialCommitmentCodec.decode(bytes)
        } catch let error as OpalFusion.Execution.WorkflowFailure {
            throw error
        } catch {
            throw OpalFusion.Execution.WorkflowFailure.protocolValidationFailed(
                "Initial commitment decode failed"
            )
        }
    }

    func parseProof(
        bytes: [UInt8]
    ) throws -> OpalFusion.Blame.Proof {
        do {
            return try OpalFusion.Wire.CashFusionProofCodec.decode(bytes)
        } catch let error as OpalFusion.Execution.RelayedProofValidationFailure {
            throw error
        } catch {
            throw OpalFusion.Execution.RelayedProofValidationFailure(
                reason: "proof decode failed"
            )
        }
    }

    func serializeComponent(
        payload: OpalFusion.Commitment.ComponentPayload,
        saltCommitment: [UInt8]
    ) throws -> [UInt8] {
        try OpalFusion.Wire.CashFusionComponentCodec.encode(
            payload: payload,
            saltCommitment: saltCommitment
        )
    }

    func serializeInitialCommitment(
        _ commitment: OpalFusion.Commitment.InitialCommitment
    ) throws -> [UInt8] {
        try OpalFusion.Wire.CashFusionInitialCommitmentCodec.encode(commitment)
    }

    func serializeProof(
        componentIndex: UInt32,
        salt: [UInt8],
        pedersenNonce: [UInt8]
    ) throws -> [UInt8] {
        try OpalFusion.Wire.CashFusionProofCodec.encode(
            .init(
                componentIndex: componentIndex,
                salt: salt,
                pedersenNonce: pedersenNonce
            )
        )
    }

    func recordBlameProofValidationFailure(
        roundIdentifier: OpalFusion.Round.Identifier?,
        fields: [OpalDiagnostics.Field]
    ) {
        OpalDiagnostics.logger(category: .fusionBlame).record(
            event: .blameProofValidationFailed,
            level: .opalFusionDefault(for: .blameProofValidationFailed),
            traceID: .opalFusionRound(roundIdentifier),
            fields: fields
        )
    }

    func mapTransactionError(
        _ error: OpalFusion.Execution.BCHTransactionError
    ) -> OpalFusion.Execution.WorkflowFailure {
        switch error {
        case let .malformed(summary):
            return .protocolValidationFailed(summary)
        case let .templateMismatch(summary):
            return .invalidTransactionTemplate(summary)
        case let .unsupportedInput(summary):
            return .unsupportedExecution(summary)
        }
    }

    static func hasDuplicateByteArrays(_ arrays: [[UInt8]]) -> Bool {
        var seen = Set<Data>()
        for array in arrays {
            if seen.insert(Data(array)).inserted == false {
                return true
            }
        }
        return false
    }
}

// OpalFusion+Execution+ProductionWorkflow+ImplementationGroup3.swift

import Foundation
import OpalCrypto

extension OpalFusion.Execution.ProductionWorkflow {
    func ensurePlayerCommitMaterial(
        round: inout OpalFusion.Execution.RoundContext
    ) throws -> OpalFusion.Execution.PlayerCommitMaterial {
        if let material = round.executionMaterial.playerCommitMaterial {
            return material
        }

        let input = try requirePlayerCommitInput(round: round)
        let feeRateSatoshisPerKb = round.serverHello.componentFeeRateSatoshisPerKb
        var components: [OpalFusion.Execution.LocalComponentMaterial] = []
        components.reserveCapacity(input.numberOfComponents)
        var reservationInputOutpoints = Set<InputOutpoint>()

        try appendInputComponentMaterials(
            from: input.reservation,
            feeRateSatoshisPerKb: feeRateSatoshisPerKb,
            components: &components,
            reservationInputOutpoints: &reservationInputOutpoints
        )
        try appendOutputComponentMaterials(
            from: input.reservation,
            feeRateSatoshisPerKb: feeRateSatoshisPerKb,
            components: &components
        )
        try appendBlankComponentMaterials(
            numberOfComponents: input.numberOfComponents,
            components: &components
        )

        let sortedComponents = try sortedCommitmentComponents(from: components)
        let excessFeeSatoshis = try validateExcessFee(
            for: sortedComponents,
            serverHello: round.serverHello
        )
        let blindRequests = try makeBlindSignatureRequests(
            startRound: input.startRound,
            sortedComponents: sortedComponents
        )
        let pedersenTotalNonce = try OpalFusion.Execution.ProtocolPrimitives.sumNoncesModOrder(
            sortedComponents.map(\.proofMaterial.pedersenNonce)
        )
        let material = OpalFusion.Execution.PlayerCommitMaterial(
            componentsByCommitmentOrder: sortedComponents,
            blindSignatureRequests: blindRequests,
            pedersenTotalNonce: pedersenTotalNonce,
            excessFeeSatoshis: excessFeeSatoshis,
            randomNumber: try OpalFusion.Execution.ProtocolPrimitives.randomBytes(count: 32)
        )
        round.executionMaterial.playerCommitMaterial = material
        round.executionMaterial.finalizedBlindSignatures = []
        round.executionMaterial.covertSignatureMessages = nil
        round.executionMaterial.covertSignatureSourceTransaction = nil
        return material
    }
}

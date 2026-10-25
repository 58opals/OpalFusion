// MosaicMainnetAlphaExecutionPreparationData.swift

@testable import MosaicEngine
@testable import OpalFusionCore
struct MosaicMainnetAlphaExecutionPreparationData: Sendable {
    typealias Alpha = OpalFusion.Mosaic.OpalMainnetAlpha
    typealias Host = OpalFusion.Host

    let election: MosaicRoleElectionFixtures.Election
    let proposalValidation: Alpha.ManifestProposalValidation
    let materialized: MosaicMainnetAlphaFixtures.MaterializedPreparation
    let localMaterial: Alpha.LocalContributionMaterial
    let localAuthorizationResponseSet: Alpha.AuthorizationResponseSet
    let localAuthorizationValidation:
        Alpha.AuthorizationResponseSetMaterialValidation
    let acknowledgementSet: Alpha.PreSignAcknowledgementSet
    let previousOutputSource:
        MosaicMainnetAlphaExecutionFixtures.PreviousOutputSource
    let previousOutputs: Alpha.PreviousOutputResolver.Validation
    let signingRequest: Host.MosaicTransactionSigningRequest
    let localFinalizedTransaction: Host.FinalizedTransaction
    let signatureSet: Alpha.BCHSignatureSet
    let completePayload: Alpha.CompleteTransactionPayload
}

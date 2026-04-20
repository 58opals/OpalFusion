// ProductionWorkflowScenario.swift

@testable import OpalFusion

struct ProductionWorkflowScenario {
    let baseline: OpalFusion.Transport.BaselineConfiguration
    let workflow: OpalFusion.Execution.ProductionWorkflow
    let serverHello: OpalFusion.ProtocolModel.ServerHello
    let fusionBegin: OpalFusion.ProtocolModel.FusionBegin
    let reservation: OpalFusion.Host.ParticipantReservation
    let participantInputPrivateKey: [UInt8]
    var blindCoordinator: BlindSigningCoordinator
    var round: OpalFusion.Execution.RoundContext

    var startRound: OpalFusion.ProtocolModel.StartRound {
        round.startRound!
    }

    mutating func buildPlayerCommit() throws -> OpalFusion.ProtocolModel.PlayerCommit {
        let playerCommit = try workflow.buildPlayerCommit(round: &round)
        round.playerCommit = playerCommit
        return playerCommit
    }

    mutating func buildBlindSignatureResponses(
        for playerCommit: OpalFusion.ProtocolModel.PlayerCommit
    ) async throws -> OpalFusion.ProtocolModel.BlindSignatureResponses {
        let responses = try await blindCoordinator.responses(for: playerCommit)
        round.blindSignatureResponses = responses
        return responses
    }

    mutating func useSharedRound(
        allCommitments: [OpalFusion.Commitment.InitialCommitment],
        serializedComponents: [[UInt8]]
    ) throws {
        round.allCommitments = .init(initialCommitments: allCommitments)
        round.sharedComponents = .init(
            serializedComponents: serializedComponents,
            skipSignatures: false,
            sessionHash: nil
        )
    }

    func localSerializedComponents() -> [[UInt8]] {
        round.executionMaterial.playerCommitMaterial?.componentsByCommitmentOrder
            .map(\.serializedComponent) ?? []
    }

    func makeExternalInputComponent() throws -> ExternalInputComponentFixture {
        try ProductionWorkflowTestFixtures.makeExternalInputComponent(
            workflow: workflow,
            feeRateSatoshisPerKb: serverHello.componentFeeRateSatoshisPerKb
        )
    }

    func makeSignedFinalizedTransaction(
        proposal: OpalFusion.Host.TransactionFinalizationProposal,
        unlockingScriptBuilder: (([UInt8], [UInt8]) -> [UInt8])? = nil
    ) throws -> SigningTransactionFixture {
        try ProductionWorkflowTestFixtures.makeSignedFinalizedTransaction(
            proposal: proposal,
            participantInput: reservation.inputs[0],
            participantInputPrivateKey: participantInputPrivateKey,
            unlockingScriptBuilder: unlockingScriptBuilder
        )
    }
}

// ProductionWorkflowValidator+ValidationGroup8.swift

@testable import OpalFusion
import Testing

extension ProductionWorkflowValidator {
    @Test("Production workflow rejects excess-fee overflow without trapping")
    func validateExcessFeeOverflowRejection() throws {
        let workflow = OpalFusion.Execution.ProductionWorkflow(
            baseline: ProductionWorkflowTestFixtures.baseline
        )
        let serverHello = OpalFusion.ProtocolModel.ServerHello(
            tiers: [100_000],
            numberOfComponents: 2,
            componentFeeRateSatoshisPerKb: 1_000,
            minimumExcessFeeSatoshis: 0,
            maximumExcessFeeSatoshis: UInt64(Int64.max),
            donationAddress: nil
        )
        let components = [
            Self.localComponentMaterial(contributionSatoshis: Int64.max),
            Self.localComponentMaterial(contributionSatoshis: 1)
        ]

        do {
            _ = try workflow.validateExcessFee(
                for: components,
                serverHello: serverHello
            )
            Issue.record("Expected excess-fee overflow to fail")
        } catch let error as OpalFusion.Execution.WorkflowFailure {
            #expect(
                error == .invalidParticipantReservation(
                    "Participant reservation produced an excess fee outside the supported range"
                )
            )
        }
    }

    static func localComponentMaterial(
        contributionSatoshis: Int64
    ) -> OpalFusion.Execution.LocalComponentMaterial {
        .init(
            originalSlot: 0,
            payload: .blank(.init()),
            serializedComponent: [],
            serializedInitialCommitment: [],
            initialCommitment: .init(
                saltedComponentHash: [],
                amountCommitment: [],
                communicationPublicKey: []
            ),
            proofMaterial: .init(
                salt: [],
                pedersenNonce: []
            ),
            communicationPrivateKey: [],
            contributionSatoshis: contributionSatoshis
        )
    }
}

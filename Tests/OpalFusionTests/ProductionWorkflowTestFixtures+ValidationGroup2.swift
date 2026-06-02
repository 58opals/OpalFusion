// ProductionWorkflowTestFixtures+ValidationGroup2.swift

@testable import OpalFusion
import Foundation
import OpalCrypto

extension ProductionWorkflowTestFixtures {
    static func makeTwoInputScenario() throws -> ProductionWorkflowScenario {
        let workflow = OpalFusion.Execution.ProductionWorkflow(baseline: baseline)
        let blindCoordinator = try BlindSigningCoordinator(numberOfComponents: 4)
        let inputPrivateKeys = [
            [UInt8](repeating: 0x11, count: 32),
            [UInt8](repeating: 0x33, count: 32),
        ]
        let inputPublicKeys = try inputPrivateKeys.map { privateKey in
            try Array(
                OpalCrypto.Secp256k1.derivePublicKey(
                    from: OpalCrypto.Secp256k1.PrivateKey(
                        rawRepresentation: Data(privateKey)
                    )
                ).rawRepresentation
            )
        }
        let outputPrivateKey = [UInt8](repeating: 0x22, count: 32)
        let outputPublicKey = try Array(
            OpalCrypto.Secp256k1.derivePublicKey(
                from: OpalCrypto.Secp256k1.PrivateKey(
                    rawRepresentation: Data(outputPrivateKey)
                )
            ).rawRepresentation
        )
        let outputScript = p2pkhLockingScript(publicKey: outputPublicKey)
        let feeRateSatoshisPerKb: UInt64 = 1_000
        let inputAmounts: [UInt64] = [100_000, 60_000]
        let inputFees = inputPublicKeys.map { publicKey in
            OpalFusion.Execution.ProtocolPrimitives.componentFee(
                sizeBytes: OpalFusion.Execution.ProtocolPrimitives.inputSize(for: publicKey),
                feeRateSatoshisPerKb: feeRateSatoshisPerKb
            )
        }
        let outputFee = OpalFusion.Execution.ProtocolPrimitives.componentFee(
            sizeBytes: OpalFusion.Execution.ProtocolPrimitives.outputSize(for: outputScript),
            feeRateSatoshisPerKb: feeRateSatoshisPerKb
        )
        let outputAmount = inputAmounts.reduce(0, +)
            - inputFees.reduce(0, +)
            - outputFee
            - 250

        let reservation = OpalFusion.Host.ParticipantReservation(
            inputs: [
                .init(
                    outpointTransactionHashBytes: [UInt8](repeating: 0xAA, count: 32),
                    outpointIndex: 1,
                    amountSatoshis: inputAmounts[0],
                    lockingScriptBytes: p2pkhLockingScript(publicKey: inputPublicKeys[0]),
                    publicKey: inputPublicKeys[0]
                ),
                .init(
                    outpointTransactionHashBytes: [UInt8](repeating: 0xBB, count: 32),
                    outpointIndex: 2,
                    amountSatoshis: inputAmounts[1],
                    lockingScriptBytes: p2pkhLockingScript(publicKey: inputPublicKeys[1]),
                    publicKey: inputPublicKeys[1]
                ),
            ],
            outputs: [
                .init(
                    lockingScriptBytes: outputScript,
                    amountSatoshis: outputAmount
                )
            ]
        )

        let serverHello = OpalFusion.ProtocolModel.ServerHello(
            tiers: [10_000],
            numberOfComponents: 4,
            componentFeeRateSatoshisPerKb: feeRateSatoshisPerKb,
            minimumExcessFeeSatoshis: 200,
            maximumExcessFeeSatoshis: 500,
            donationAddress: "bitcoincash:qexample"
        )
        let fusionBegin = OpalFusion.ProtocolModel.FusionBegin(
            tier: 10_000,
            covertDomain: "covert.example.org",
            covertPort: 7_447,
            covertSsl: true,
            serverTimeUnixSeconds: 1_000
        )

        let deadlines = OpalFusion.Execution.Deadlines
            .fromFusionBegin(fusionBegin, timing: baseline.roundTiming)
            .withStartRound(blindCoordinator.startRound, timing: baseline.roundTiming)
        var round = OpalFusion.Execution.RoundContext(
            fusionBegin: fusionBegin,
            serverHello: serverHello,
            deadlines: deadlines
        )
        round.startRound = blindCoordinator.startRound
        round.identifier = .init(rawValue: blindCoordinator.roundPublicKey.map {
            String(format: "%02x", $0)
        }.joined())
        round.participantReservation = reservation

        return .init(
            baseline: baseline,
            workflow: workflow,
            serverHello: serverHello,
            fusionBegin: fusionBegin,
            reservation: reservation,
            participantInputPrivateKeys: inputPrivateKeys,
            blindCoordinator: blindCoordinator,
            round: round
        )
    }

    static func extractSerializedComponents(
        from covertMessages: [OpalFusion.ProtocolModel.CovertMessage]
    ) throws -> [[UInt8]] {
        try covertMessages.map { message in
            guard case let .component(componentMessage) = message else {
                throw ProductionWorkflowTestError.expectedComponentMessage
            }
            return componentMessage.serializedComponent
        }
    }
}

// ProductionWorkflowTestFixtures+ValidationGroup1.swift

@testable import OpalFusion
import Foundation
import OpalCrypto

extension ProductionWorkflowTestFixtures {
    static func makeScenario() throws -> ProductionWorkflowScenario {
        let workflow = OpalFusion.Execution.ProductionWorkflow(baseline: baseline)
        let blindCoordinator = try BlindSigningCoordinator(numberOfComponents: 3)
        let inputPrivateKey = [UInt8](repeating: 0x11, count: 32)
        let inputPublicKey = try Array(
            OpalCrypto.Secp256k1.derivePublicKey(
                from: OpalCrypto.Secp256k1.PrivateKey(
                    rawRepresentation: Data(inputPrivateKey)
                )
            ).rawRepresentation
        )
        let outputPrivateKey = [UInt8](repeating: 0x22, count: 32)
        let outputPublicKey = try Array(
            OpalCrypto.Secp256k1.derivePublicKey(
                from: OpalCrypto.Secp256k1.PrivateKey(
                    rawRepresentation: Data(outputPrivateKey)
                )
            ).rawRepresentation
        )

        let reservation = OpalFusion.Host.ParticipantReservation(
            inputs: [
                .init(
                    outpointTransactionHashBytes: [UInt8](repeating: 0xAA, count: 32),
                    outpointIndex: 1,
                    amountSatoshis: 100_000,
                    lockingScriptBytes: p2pkhLockingScript(publicKey: inputPublicKey),
                    publicKey: inputPublicKey
                )
            ],
            outputs: [
                .init(
                    lockingScriptBytes: p2pkhLockingScript(publicKey: outputPublicKey),
                    amountSatoshis: 99_600
                )
            ]
        )

        let serverHello = OpalFusion.ProtocolModel.ServerHello(
            tiers: [10_000],
            numberOfComponents: 3,
            componentFeeRateSatoshisPerKb: 1_000,
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
            participantInputPrivateKeys: [inputPrivateKey],
            blindCoordinator: blindCoordinator,
            round: round
        )
    }
}

// RoundEngineScriptedValidator+FixtureGroup1.swift

@testable import OpalFusion
import Testing

extension RoundEngineScriptedValidator {
    static var roundIdentifier: OpalFusion.Round.Identifier {
        .init(rawValue: "aabb")
    }

    static var configuration: OpalFusion.Client.Configuration {
        .init(
            coordinatorHost: "fusion.example.org",
            coordinatorPort: 8_787,
            covertChannel: .init(
                entryPath: "/fusion",
                maxPayloadBytes: 32_768,
                requestTimeoutMilliseconds: 15_000
            )
        )
    }

    static var closeStartReachableBaseline: OpalFusion.Transport.BaselineConfiguration {
        let baseline = OpalFusion.Transport.BaselineConfiguration.electronCash443
        return .init(
            protocolIdentity: baseline.protocolIdentity,
            framing: baseline.framing,
            covertTiming: baseline.covertTiming,
            roundTiming: .init(
                maximumClockDiscrepancy: baseline.roundTiming.maximumClockDiscrepancy,
                warmupDuration: baseline.roundTiming.warmupDuration,
                warmupSlop: baseline.roundTiming.warmupSlop,
                commitmentsDeadlineFromRoundStart: baseline.roundTiming.commitmentsDeadlineFromRoundStart,
                covertComponentsStartFromRoundStart: baseline.roundTiming.covertComponentsStartFromRoundStart,
                covertComponentsDeadlineFromRoundStart: baseline.roundTiming.covertComponentsDeadlineFromRoundStart,
                signaturesStartFromRoundStart: baseline.roundTiming.signaturesStartFromRoundStart,
                signaturesDeadlineFromRoundStart: baseline.roundTiming.signaturesDeadlineFromRoundStart,
                conclusionTimeoutFromRoundStart: .seconds(90),
                closeStartFromRoundStart: baseline.roundTiming.closeStartFromRoundStart,
                blameCloseStartFromRoundStart: baseline.roundTiming.blameCloseStartFromRoundStart,
                standardTimeout: baseline.roundTiming.standardTimeout,
                blameVerifyDuration: baseline.roundTiming.blameVerifyDuration
            )
        )
    }

    static var joinPools: OpalFusion.ProtocolModel.JoinPools {
        .init(
            tiers: [10_000],
            tags: [
                .init(
                    identifier: [0x01, 0x02, 0x03],
                    limit: 1,
                    noIp: true
                )
            ]
        )
    }

    static var clientHello: OpalFusion.ProtocolModel.ClientHello {
        .init(
            versionBytes: OpalFusion.Transport.BaselineConfiguration.electronCash443.protocolIdentity.versionBytes,
            genesisHash: [0xAA, 0xBB, 0xCC]
        )
    }

    static var serverHello: OpalFusion.ProtocolModel.ServerHello {
        .init(
            tiers: [10_000],
            numberOfComponents: 4,
            componentFeeRateSatoshisPerKb: 1_000,
            minimumExcessFeeSatoshis: 200,
            maximumExcessFeeSatoshis: 500,
            donationAddress: "bitcoincash:qexample"
        )
    }

    static var fusionBegin: OpalFusion.ProtocolModel.FusionBegin {
        .init(
            tier: 10_000,
            covertDomain: "covert.example.org",
            covertPort: 7_447,
            covertSsl: true,
            serverTimeUnixSeconds: 1_000
        )
    }

    static var startRound: OpalFusion.ProtocolModel.StartRound {
        .init(
            roundPublicKey: [0xAA, 0xBB],
            blindNoncePoints: [[0x01, 0x02], [0x03, 0x04], [0x05, 0x06], [0x07, 0x08]],
            serverTimeUnixSeconds: 1_030
        )
    }

    static var participantReservationContext: OpalFusion.Host.ParticipantReservationContext {
        .init(
            roundIdentifier: roundIdentifier,
            tierSatoshis: fusionBegin.tier,
            numberOfComponents: serverHello.numberOfComponents,
            componentFeeRateSatoshisPerKb: serverHello.componentFeeRateSatoshisPerKb,
            minimumExcessFeeSatoshis: serverHello.minimumExcessFeeSatoshis,
            maximumExcessFeeSatoshis: serverHello.maximumExcessFeeSatoshis
        )
    }

    static var participantInput: OpalFusion.Host.ParticipantInput {
        .init(
            outpointTransactionHashBytes: [0x10, 0x11],
            outpointIndex: 0,
            amountSatoshis: 50_000,
            lockingScriptBytes: [0x51],
            publicKey: [0x02, 0x10, 0x11]
        )
    }

    static var participantOutput: OpalFusion.Host.ParticipantOutput {
        .init(
            lockingScriptBytes: [0x76, 0xA9, 0x14, 0x01, 0x88, 0xAC],
            amountSatoshis: 49_000
        )
    }

    static var participantReservation: OpalFusion.Host.ParticipantReservation {
        .init(
            inputs: [participantInput],
            outputs: [participantOutput]
        )
    }

    static var initialCommitment: OpalFusion.Commitment.InitialCommitment {
        .init(
            saltedComponentHash: [0x21],
            amountCommitment: [0x22],
            communicationPublicKey: [0x23]
        )
    }

    static var playerCommit: OpalFusion.ProtocolModel.PlayerCommit {
        .init(
            initialCommitments: [initialCommitment],
            excessFeeSatoshis: 250,
            pedersenTotalNonce: [0x24],
            randomNumberCommitment: [0x25],
            blindSignatureRequests: [.init(scalar: [0x26])]
        )
    }

    static var blindSignatureResponses: OpalFusion.ProtocolModel.BlindSignatureResponses {
        .init(
            responses: [.init(scalar: [0x27])]
        )
    }

    static var allCommitments: OpalFusion.ProtocolModel.AllCommitments {
        .init(
            initialCommitments: [initialCommitment]
        )
    }

    static var covertComponentMessage: OpalFusion.ProtocolModel.CovertMessage {
        .component(
            .init(
                roundPublicKey: [0xAA, 0xBB],
                signature: [0x30],
                serializedComponent: [0x31]
            )
        )
    }
}

// PrimaryRuntimeTestFixtures+FixtureGroup1.swift

@testable import OpalFusion

extension PrimaryRuntimeTestFixtures {
    static let baseline = OpalFusion.Transport.BaselineConfiguration.electronCash443

    static let roundIdentifier = OpalFusion.Round.Identifier(rawValue: "aabb")

    static let closeStartReachableBaseline = OpalFusion.Transport.BaselineConfiguration(
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

    static let configuration = OpalFusion.Client.Configuration(
        coordinatorHost: "fusion.example.org",
        coordinatorPort: 8_787,
        covertChannel: .init(
            entryPath: "/fusion",
            maxPayloadBytes: 32_768,
            requestTimeoutMilliseconds: 15_000
        )
    )

    static let joinPools = OpalFusion.ProtocolModel.JoinPools(
        tiers: [10_000],
        tags: [
            .init(
                identifier: [0x01, 0x02, 0x03],
                limit: 1,
                noIp: true
            )
        ]
    )

    static let clientHello = OpalFusion.ProtocolModel.ClientHello(
        versionBytes: baseline.protocolIdentity.versionBytes,
        genesisHash: [UInt8](repeating: 0xAA, count: 32)
    )

    static let serverHello = OpalFusion.ProtocolModel.ServerHello(
        tiers: [10_000],
        numberOfComponents: 4,
        componentFeeRateSatoshisPerKb: 1_000,
        minimumExcessFeeSatoshis: 200,
        maximumExcessFeeSatoshis: 500,
        donationAddress: "bitcoincash:qexample"
    )

    static let tierStatusUpdate = OpalFusion.ProtocolModel.TierStatusUpdate(
        statusesByTier: [
            10_000: .init(
                playerCount: 3,
                minimumPlayerCount: 2,
                maximumPlayerCount: 8,
                timeRemainingSeconds: 17
            )
        ]
    )

    static let fusionBegin = OpalFusion.ProtocolModel.FusionBegin(
        tier: 10_000,
        covertDomain: "covert.example.org",
        covertPort: 7_447,
        covertSsl: true,
        serverTimeUnixSeconds: 1_000
    )

    static let startRound = OpalFusion.ProtocolModel.StartRound(
        roundPublicKey: [0xAA, 0xBB],
        blindNoncePoints: [[0x01, 0x02], [0x03, 0x04], [0x05, 0x06], [0x07, 0x08]],
        serverTimeUnixSeconds: 1_030
    )

    static let participantReservationContext = OpalFusion.Host.ParticipantReservationContext(
        roundIdentifier: roundIdentifier,
        tierSatoshis: fusionBegin.tier,
        numberOfComponents: serverHello.numberOfComponents,
        componentFeeRateSatoshisPerKb: serverHello.componentFeeRateSatoshisPerKb,
        minimumExcessFeeSatoshis: serverHello.minimumExcessFeeSatoshis,
        maximumExcessFeeSatoshis: serverHello.maximumExcessFeeSatoshis
    )

    static let participantInput = OpalFusion.Host.ParticipantInput(
        outpointTransactionHashBytes: [0x10, 0x11],
        outpointIndex: 0,
        amountSatoshis: 50_000,
        lockingScriptBytes: [0x51],
        publicKey: [0x02, 0x10, 0x11]
    )

    static let participantOutput = OpalFusion.Host.ParticipantOutput(
        lockingScriptBytes: [0x76, 0xA9, 0x14, 0x01, 0x88, 0xAC],
        amountSatoshis: 49_000
    )

    static let participantReservation = OpalFusion.Host.ParticipantReservation(
        inputs: [participantInput],
        outputs: [participantOutput]
    )

    static let initialCommitment = OpalFusion.Commitment.InitialCommitment(
        saltedComponentHash: [0x21],
        amountCommitment: [0x22],
        communicationPublicKey: [0x23]
    )

    static let playerCommit = OpalFusion.ProtocolModel.PlayerCommit(
        initialCommitments: [initialCommitment],
        excessFeeSatoshis: 250,
        pedersenTotalNonce: [0x24],
        randomNumberCommitment: [0x25],
        blindSignatureRequests: [.init(scalar: [0x26])]
    )

    static let blindSignatureResponses = OpalFusion.ProtocolModel.BlindSignatureResponses(
        responses: [.init(scalar: [0x27])]
    )

    static let allCommitments = OpalFusion.ProtocolModel.AllCommitments(
        initialCommitments: [initialCommitment]
    )

    static let covertComponentMessage = OpalFusion.ProtocolModel.CovertMessage.component(
        .init(
            roundPublicKey: [0xAA, 0xBB],
            signature: [0x30],
            serializedComponent: [0x31]
        )
    )

    static let pingMessage = OpalFusion.ProtocolModel.CovertMessage.ping(.init())

    static let sharedComponents = OpalFusion.ProtocolModel.ShareCovertComponents(
        serializedComponents: [[0x40], [0x42]],
        skipSignatures: false,
        sessionHash: [0x41]
    )

    static let transactionProposal = OpalFusion.Host.TransactionFinalizationProposal(
        unsignedTransactionBytes: [0x50],
        sessionHash: [0x41],
        expectedInputCount: 1,
        expectedOutputCount: 2,
        participantCount: 1
    )

    static let finalizedTransaction = OpalFusion.Host.FinalizedTransaction(
        transactionBytes: [0x60]
    )

    static let signatureMessage = OpalFusion.ProtocolModel.CovertMessage.transactionSignature(
        .init(
            roundPublicKey: [0xAA, 0xBB],
            inputIndex: 0,
            transactionSignature: [0x61]
        )
    )

    static let successResult = OpalFusion.ProtocolModel.FusionResult(
        isSuccess: true,
        transactionSignatures: [[0x70]],
        badComponentIndices: []
    )
}

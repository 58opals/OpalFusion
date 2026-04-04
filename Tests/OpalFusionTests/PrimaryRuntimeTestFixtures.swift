// PrimaryRuntimeTestFixtures.swift

@testable import OpalFusion

enum PrimaryRuntimeTestFixtureError: Swift.Error, Equatable {
    case expectedSinglePayload(Int)
    case expectedWriteEffect
}

enum PrimaryRuntimeTestFixtures {
    static let baseline = OpalFusion.Transport.BaselineConfiguration.electronCash443
    static let roundIdentifier = OpalFusion.Round.Identifier(rawValue: "aabb")

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
        genesisHash: [0xAA, 0xBB, 0xCC]
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
        blindNoncePoints: [[0x01, 0x02], [0x03, 0x04]],
        serverTimeUnixSeconds: 1_030
    )

    static let participantInput = OpalFusion.Host.ParticipantInput(
        outpointTransactionHash: [0x10, 0x11],
        outpointIndex: 0,
        amountSatoshis: 50_000,
        lockingScript: [0x51]
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

    static let sharedComponents = OpalFusion.ProtocolModel.ShareCovertComponents(
        serializedComponents: [[0x40], [0x42]],
        skipSignatures: false,
        sessionHash: [0x41]
    )

    static let transactionProposal = OpalFusion.Host.TransactionFinalizationProposal(
        serializedUnsignedTransaction: [0x50],
        sessionHash: [0x41],
        expectedInputCount: 1,
        expectedOutputCount: 2,
        participantCount: 1
    )

    static let finalizedTransaction = OpalFusion.Host.FinalizedTransaction(
        serializedTransaction: [0x60]
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

    static let failureResult = OpalFusion.ProtocolModel.FusionResult(
        isSuccess: false,
        transactionSignatures: [],
        badComponentIndices: [0]
    )

    static let myProofsList = OpalFusion.ProtocolModel.MyProofsList(
        encryptedProofs: [[0x80], [0x84]],
        randomNumber: [0x81]
    )

    static let theirProofsList = OpalFusion.ProtocolModel.TheirProofsList(
        proofs: [
            .init(
                encryptedProof: [0x82],
                sourceCommitmentIndex: 0,
                destinationKeyIndex: 0
            )
        ]
    )

    static let blames = OpalFusion.ProtocolModel.Blames(
        blames: [
            .init(
                proofIndex: 0,
                decrypter: .sessionKey([0x83]),
                requiresBlockchainLookup: false,
                reason: "invalid component"
            )
        ]
    )

    static let serverFailure = OpalFusion.ProtocolModel.ServerFailure(
        message: "Coordinator rejected"
    )

    static let clientMessages: [OpalFusion.ProtocolModel.ClientMessage] = [
        .clientHello(clientHello),
        .joinPools(joinPools),
        .playerCommit(playerCommit),
        .myProofsList(myProofsList),
        .blames(blames)
    ]

    static let serverMessages: [OpalFusion.ProtocolModel.ServerMessage] = [
        .serverHello(serverHello),
        .tierStatusUpdate(tierStatusUpdate),
        .fusionBegin(fusionBegin),
        .startRound(startRound),
        .blindSignatureResponses(blindSignatureResponses),
        .allCommitments(allCommitments),
        .shareCovertComponents(sharedComponents),
        .fusionResult(successResult),
        .theirProofsList(theirProofsList),
        .restartRound(.init()),
        .serverFailure(serverFailure)
    ]

    static let workflow = OpalFusion.Execution.WorkflowContext(
        buildPlayerCommit: { _ in playerCommit },
        buildCovertComponentMessages: { _ in [covertComponentMessage] },
        buildTransactionFinalizationProposal: { _ in transactionProposal },
        buildCovertSignatureMessages: { _ in [signatureMessage] },
        buildMyProofsList: { _ in myProofsList },
        buildBlames: { _ in blames }
    )

    static func makeSession() -> OpalFusion.Runtime.PrimaryRuntimeSession {
        .init(
            configuration: configuration,
            genesisHash: clientHello.genesisHash,
            joinPools: joinPools,
            workflow: workflow,
            baseline: baseline
        )
    }

    static func instant(_ unixSeconds: UInt64) -> OpalFusion.Execution.Instant {
        .init(unixSeconds: unixSeconds)
    }

    static func encodeServerPayload(
        _ message: OpalFusion.ProtocolModel.ServerMessage
    ) throws -> [UInt8] {
        try OpalFusion.Wire.PrimaryMessageEncoder().encode(message)
    }

    static func encodeServerFrame(
        _ message: OpalFusion.ProtocolModel.ServerMessage
    ) throws -> [UInt8] {
        try OpalFusion.Wire.PrimaryFrameEncoder(configuration: baseline.framing)
            .encode(payload: encodeServerPayload(message))
    }

    static func decodeClientMessage(
        from framedBytes: [UInt8]
    ) throws -> OpalFusion.ProtocolModel.ClientMessage {
        var frameDecoder = OpalFusion.Wire.PrimaryFrameDecoder(configuration: baseline.framing)
        let payloads = try frameDecoder.append(framedBytes)
        guard payloads.count == 1 else {
            throw PrimaryRuntimeTestFixtureError.expectedSinglePayload(payloads.count)
        }
        return try OpalFusion.Wire.PrimaryMessageDecoder().decodeClient(payloads[0])
    }

    static func extractWriteMessage(
        from effect: OpalFusion.Runtime.PrimaryRuntimeSession.Effect
    ) throws -> OpalFusion.ProtocolModel.ClientMessage {
        guard case let .writePrimaryBytes(bytes) = effect else {
            throw PrimaryRuntimeTestFixtureError.expectedWriteEffect
        }
        return try decodeClientMessage(from: bytes)
    }

    static func driveThroughStartRound(
        session: inout OpalFusion.Runtime.PrimaryRuntimeSession
    ) throws {
        try driveThroughWarmup(session: &session)
        _ = session.apply(
            input: .receivedPrimaryBytes(try encodeServerFrame(.startRound(startRound))),
            now: instant(1_030)
        )
    }

    static func driveThroughWarmup(
        session: inout OpalFusion.Runtime.PrimaryRuntimeSession
    ) throws {
        _ = session.apply(input: .connected, now: instant(995))
        _ = session.apply(
            input: .receivedPrimaryBytes(try encodeServerFrame(.serverHello(serverHello))),
            now: instant(996)
        )
        _ = session.apply(
            input: .receivedPrimaryBytes(try encodeServerFrame(.fusionBegin(fusionBegin))),
            now: instant(1_000)
        )
    }

    static func driveToAwaitingCovertSubmission(
        session: inout OpalFusion.Runtime.PrimaryRuntimeSession
    ) throws {
        try driveThroughStartRound(session: &session)
        _ = session.apply(
            input: .hostInputsLoaded([participantInput]),
            now: instant(1_031)
        )
        _ = session.apply(
            input: .receivedPrimaryBytes(
                try encodeServerFrame(.blindSignatureResponses(blindSignatureResponses))
            ),
            now: instant(1_032)
        )
        _ = session.apply(
            input: .receivedPrimaryBytes(try encodeServerFrame(.allCommitments(allCommitments))),
            now: instant(1_034)
        )
    }
}

// PrimaryRuntimeTestFixtures+FixtureGroup2.swift

@testable import OpalFusion

extension PrimaryRuntimeTestFixtures {
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
                decrypter: .sessionKey(secretBytes: [0x83]),
                requiresBlockchainLookup: false,
                reason: "invalid component"
            )
        ]
    )

    static let serverFailure = OpalFusion.ProtocolModel.ServerFailure(
        message: "Coordinator rejected"
    )

    static let covertServerFailure = OpalFusion.ProtocolModel.ServerFailure(
        message: "Covert transport failed"
    )

    static let acknowledgement = OpalFusion.ProtocolModel.CovertResponse.acknowledgement(.init())

    static let covertFailureResponse = OpalFusion.ProtocolModel.CovertResponse.serverFailure(
        covertServerFailure
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

    static let covertMessages: [OpalFusion.ProtocolModel.CovertMessage] = [
        covertComponentMessage,
        signatureMessage,
        pingMessage
    ]

    static let covertResponses: [OpalFusion.ProtocolModel.CovertResponse] = [
        acknowledgement,
        covertFailureResponse
    ]

    static let covertEndpointContext = OpalFusion.Runtime.CovertEndpointContext(
        roundIdentifier: nil,
        host: fusionBegin.covertDomain,
        port: fusionBegin.covertPort,
        requiresTLS: fusionBegin.covertSsl,
        entryPath: configuration.covertChannel.entryPath,
        maxPayloadBytes: configuration.covertChannel.maxPayloadBytes,
        requestTimeoutMilliseconds: configuration.covertChannel.requestTimeoutMilliseconds,
        connectTimeout: baseline.covertTiming.connectTimeout,
        connectWindow: baseline.covertTiming.connectWindow,
        submitTimeout: baseline.covertTiming.submitTimeout,
        submitWindow: baseline.covertTiming.submitWindow,
        spareConnectionCount: baseline.covertTiming.spareConnectionCount
    )
}

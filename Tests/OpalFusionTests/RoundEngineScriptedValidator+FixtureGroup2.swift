// RoundEngineScriptedValidator+FixtureGroup2.swift

@testable import OpalFusion
import Testing

extension RoundEngineScriptedValidator {
    static var covertEndpointContext: OpalFusion.Runtime.CovertEndpointContext {
        .init(
            roundIdentifier: nil,
            host: fusionBegin.covertDomain,
            port: fusionBegin.covertPort,
            requiresTLS: fusionBegin.covertSsl,
            entryPath: configuration.covertChannel.entryPath,
            maxPayloadBytes: configuration.covertChannel.maxPayloadBytes,
            requestTimeoutMilliseconds: configuration.covertChannel.requestTimeoutMilliseconds,
            connectTimeout: OpalFusion.Transport.BaselineConfiguration.electronCash443.covertTiming.connectTimeout,
            connectWindow: OpalFusion.Transport.BaselineConfiguration.electronCash443.covertTiming.connectWindow,
            submitTimeout: OpalFusion.Transport.BaselineConfiguration.electronCash443.covertTiming.submitTimeout,
            submitWindow: OpalFusion.Transport.BaselineConfiguration.electronCash443.covertTiming.submitWindow,
            spareConnectionCount: OpalFusion.Transport.BaselineConfiguration.electronCash443.covertTiming.spareConnectionCount
        )
    }

    static var sharedComponents: OpalFusion.ProtocolModel.ShareCovertComponents {
        .init(
            serializedComponents: [[0x40]],
            skipSignatures: false,
            sessionHash: [0x41]
        )
    }

    static var transactionProposal: OpalFusion.Host.TransactionFinalizationProposal {
        .init(
            unsignedFusionTransactionBytes: [0x50],
            sessionHash: [0x41],
            expectedInputCount: 1,
            expectedOutputCount: 2,
            participantCount: nil
        )
    }

    static var finalizedTransaction: OpalFusion.Host.FinalizedTransaction {
        .init(signedFusionTransactionBytes: [0x60])
    }

    static var signatureMessage: OpalFusion.ProtocolModel.CovertMessage {
        .transactionSignature(
            .init(
                roundPublicKey: [0xAA, 0xBB],
                inputIndex: 0,
                transactionSignature: [0x61]
            )
        )
    }

    static var successResult: OpalFusion.ProtocolModel.FusionResult {
        .init(
            isSuccess: true,
            transactionSignatures: [[0x70]],
            badComponentIndices: []
        )
    }

    static var failureResult: OpalFusion.ProtocolModel.FusionResult {
        .init(
            isSuccess: false,
            transactionSignatures: [],
            badComponentIndices: [0]
        )
    }

    static var myProofsList: OpalFusion.ProtocolModel.MyProofsList {
        .init(
            encryptedProofs: [[0x80]],
            randomNumber: [0x81]
        )
    }

    static var theirProofsList: OpalFusion.ProtocolModel.TheirProofsList {
        .init(
            proofs: [
                .init(
                    encryptedProof: [0x82],
                    sourceCommitmentIndex: 0,
                    destinationKeyIndex: 0
                )
            ]
        )
    }

    static var blames: OpalFusion.ProtocolModel.Blames {
        .init(
            blames: [
                .init(
                    proofIndex: 0,
                    decrypter: .sessionKey(secretBytes: [0x83]),
                    requiresBlockchainLookup: false,
                    reason: "invalid component"
                )
            ]
        )
    }

    static func makeEngine(
        baseline: OpalFusion.Transport.BaselineConfiguration = .electronCash443
    ) -> OpalFusion.Execution.RoundEngine {
        .init(
            configuration: configuration,
            genesisHash: [0xAA, 0xBB, 0xCC],
            joinPools: joinPools,
            workflow: .init(
                buildPlayerCommit: { _ in playerCommit },
                buildCovertComponentMessages: { _ in [covertComponentMessage] },
                buildTransactionFinalizationProposal: { _ in transactionProposal },
                buildCovertSignatureMessages: { _ in [signatureMessage] },
                buildMyProofsList: { _ in myProofsList },
                buildBlames: { _ in blames }
            ),
            baseline: baseline
        )
    }

    static func instant(_ unixSeconds: UInt64) -> OpalFusion.Execution.Instant {
        .init(unixSeconds: unixSeconds)
    }

    static func driveThroughStartRound(
        engine: inout OpalFusion.Execution.RoundEngine
    ) {
        _ = engine.apply(input: .primaryConnected, now: instant(995))
        _ = engine.apply(input: .primaryMessage(.serverHello(serverHello)), now: instant(996))
        _ = engine.apply(input: .primaryMessage(.fusionBegin(fusionBegin)), now: instant(1_000))
        _ = engine.apply(input: .primaryMessage(.startRound(startRound)), now: instant(1_030))
    }

    static func driveToSharedComponents(
        engine: inout OpalFusion.Execution.RoundEngine
    ) {
        driveThroughStartRound(engine: &engine)
        _ = engine.apply(
            input: .participantReservationLoaded(participantReservation),
            now: instant(1_031)
        )
        _ = engine.apply(
            input: .primaryMessage(.blindSignatureResponses(blindSignatureResponses)),
            now: instant(1_032)
        )
        _ = engine.apply(
            input: .primaryMessage(.allCommitments(allCommitments)),
            now: instant(1_034)
        )
        _ = engine.apply(input: .clockAdvanced, now: instant(1_035))
        _ = engine.apply(
            input: .primaryMessage(.shareCovertComponents(sharedComponents)),
            now: instant(1_040)
        )
    }

    static func driveToSignatureSubmission(
        engine: inout OpalFusion.Execution.RoundEngine
    ) {
        driveToSharedComponents(engine: &engine)
        _ = engine.apply(
            input: .finalizedTransactionLoaded(finalizedTransaction),
            now: instant(1_042)
        )
        _ = engine.apply(input: .clockAdvanced, now: instant(1_050))
    }
}

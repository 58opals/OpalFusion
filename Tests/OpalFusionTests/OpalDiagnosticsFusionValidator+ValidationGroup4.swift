// OpalDiagnosticsFusionValidator+ValidationGroup4.swift

@testable import OpalFusion
import Foundation
import Network
import OpalCrypto
import OpalDiagnostics
import Testing

extension OpalDiagnosticsFusionValidator {
    @Test("Proof validation failures emit redacted blame diagnostics")
    func validateProofValidationFailuresEmitRedactedDiagnostics() throws {
        try withDiagnosticsCapture {
            var scenario = try ProductionWorkflowTestFixtures.makeScenario()
            let playerCommit = try scenario.buildPlayerCommit()
            let extraInputComponent = try scenario.makeExternalInputComponent()

            try scenario.useSharedRound(
                allCommitments: playerCommit.initialCommitments + [extraInputComponent.initialCommitment],
                serializedComponents: scenario.makeLocalSerializedComponents() + [extraInputComponent.serializedComponent]
            )
            _ = try scenario.workflow.buildMyProofsList(round: &scenario.round)

            guard let playerCommitMaterial = scenario.round.executionMaterial.playerCommitMaterial,
                  let sharedRoundMaterial = scenario.round.executionMaterial.sharedRoundMaterial else {
                Issue.record("Expected shared production workflow material")
                return
            }

            let destinationComponent = playerCommitMaterial.componentsByCommitmentOrder[0]
            let invalidEncryptedProof = try Array(
                OpalCrypto.Communication.encrypt(
                    message: Data([0x00]),
                    recipientPublicKey: OpalCrypto.Secp256k1.PublicKey(
                        rawRepresentation: Data(
                            destinationComponent.initialCommitment.communicationPublicKey
                        )
                    ),
                    maximumCiphertextByteCount: OpalFusion.Execution.ProtocolPrimitives
                        .maximumEncryptedProofCiphertextByteCount
                ).rawRepresentation
            )
            scenario.round.fusionResult = .init(
                isSuccess: false,
                transactionSignatures: [],
                badComponentIndices: []
            )
            scenario.round.theirProofsList = .init(
                proofs: [
                    .init(
                        encryptedProof: invalidEncryptedProof,
                        sourceCommitmentIndex: UInt32(sharedRoundMaterial.allCommitmentBytes.count - 1),
                        destinationKeyIndex: 0
                    )
                ]
            )

            OpalDiagnostics.clearRecentRecords()
            let blames = try scenario.workflow.buildBlames(round: &scenario.round)

            #expect(blames.blames.first?.reason == "proof decode failed")
            let record = try #require(findDiagnosticRecord(named: OpalDiagnostics.Event.blameProofValidationFailed))
            #expect(record.category == OpalDiagnostics.Category.fusionBlame)
            #expect(
                record.traceID == OpalDiagnostics.TraceID(
                    publicValue: scenario.round.identifier!.rawValue
                )
            )
            #expect(findField("error_code", in: record)?.value == "relayed_proof_validation_failed")
            #expect(findField("error_message", in: record)?.value == "<redacted>")
            #expect(record.fields.contains { $0.value.contains("proof decode failed") } == false)
        }
    }

    @Test("Reconnect scheduling emits OpalDiagnostics")
    func validateReconnectSchedulingEmitsDiagnostics() async throws {
        try await withDiagnosticsCapture {
            let transportFactories = SessionTransportFactoryRecorder()
            let session = OpalFusion.Client.Session(
                configuration: PrimaryRuntimeTestFixtures.configuration,
                genesisHash: PrimaryRuntimeTestFixtures.clientHello.genesisHash,
                joinPools: PrimaryRuntimeTestFixtures.joinPools,
                hostParticipantReservationSource: HostParticipantReservationSourceAdapter(
                    participantInputs: [PrimaryRuntimeTestFixtures.participantInput]
                ),
                hostTransactionAssembler: HostTransactionAssemblerAdapter(
                    finalizedTransaction: PrimaryRuntimeTestFixtures.finalizedTransaction
                ),
                reconnectPolicy: Self.fastReconnectPolicy,
                primaryTransportFactory: { await transportFactories.makePrimary() },
                covertTransportFactory: { await transportFactories.makeCovert() }
            )

            await session.start()
            let firstTransport = try await waitForPrimaryTransport(
                transportFactories,
                at: 0
            )
            try await waitForWrittenPayloadCount(firstTransport, count: 1)
            await firstTransport.finishInbound()

            let record = try await waitForDiagnosticRecord(named: .primaryRetryScheduled)
            #expect(findField("retry_attempt", in: record)?.value == "1")
            #expect(findField("retry_delay_ms", in: record)?.value == "10")

            await session.stop()
        }
    }

    func makePreparingCovertSession() -> OpalFusion.Runtime.CovertRuntimeSession {
        var session = PrimaryRuntimeTestFixtures.makeCovertSession()
        _ = session.apply(
            input: .prepare(endpointContext: PrimaryRuntimeTestFixtures.covertEndpointContext),
            now: PrimaryRuntimeTestFixtures.instant(1_000)
        )
        return session
    }

    func makeDispatchedCovertSession(
        roundIdentifier: OpalFusion.Round.Identifier? = nil
    ) -> OpalFusion.Runtime.CovertRuntimeSession {
        var session = makePreparingCovertSession()
        _ = session.apply(input: .covertPrepared, now: PrimaryRuntimeTestFixtures.instant(1_001))

        let enqueueUnixSeconds: UInt64
        if let roundIdentifier {
            _ = session.apply(
                input: .roundIdentifierResolved(roundIdentifier),
                now: PrimaryRuntimeTestFixtures.instant(1_002)
            )
            enqueueUnixSeconds = 1_003
        } else {
            enqueueUnixSeconds = 1_002
        }

        _ = session.apply(
            input: .enqueue(message: PrimaryRuntimeTestFixtures.pingMessage),
            now: PrimaryRuntimeTestFixtures.instant(enqueueUnixSeconds)
        )
        return session
    }

    func withDiagnosticsCapture<Success>(
        _ operation: () throws -> Success
    ) rethrows -> Success {
        try OpalDiagnostics.withConfiguration(Self.diagnosticsConfiguration) {
            OpalDiagnostics.clearRecentRecords()
            return try operation()
        }
    }

    func withDiagnosticsCapture<Success>(
        _ operation: () async throws -> Success
    ) async rethrows -> Success {
        try await OpalDiagnostics.withConfiguration(Self.diagnosticsConfiguration) {
            OpalDiagnostics.clearRecentRecords()
            return try await operation()
        }
    }

    func makeDiagnosticsRuntimeDriver(
        primaryTransport: ScriptedPrimaryTransport,
        covertTransport: any OpalFusion.Runtime.CovertTransporting,
        nowProvider: ScriptedInstantClock
    ) -> OpalFusion.Runtime.LiveRuntimeDriver {
        OpalFusion.Runtime.LiveRuntimeDriver(
            configuration: PrimaryRuntimeTestFixtures.configuration,
            genesisHash: PrimaryRuntimeTestFixtures.clientHello.genesisHash,
            joinPools: PrimaryRuntimeTestFixtures.joinPools,
            workflow: PrimaryRuntimeTestFixtures.workflow,
            participantReservationSource: HostParticipantReservationSourceAdapter(
                participantInputs: [PrimaryRuntimeTestFixtures.participantInput]
            ),
            transactionAssembler: HostTransactionAssemblerAdapter(
                finalizedTransaction: PrimaryRuntimeTestFixtures.finalizedTransaction
            ),
            nowProvider: { await nowProvider.current },
            primaryTransport: primaryTransport,
            covertTransport: covertTransport
        )
    }

    func findDiagnosticRecord(
        named event: OpalDiagnostics.Event,
        matching matches: @Sendable (OpalDiagnostics.Record) -> Bool = { _ in true }
    ) -> OpalDiagnostics.Record? {
        OpalDiagnostics.recentRecords(matching: .init(event: event)).first(where: matches)
    }

    func findField(
        _ name: String,
        in record: OpalDiagnostics.Record
    ) -> OpalDiagnostics.Field? {
        record.fields.first { $0.name == name }
    }
}

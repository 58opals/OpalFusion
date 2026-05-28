// ElectronCashInteropValidator.swift

@testable import OpalFusion
import Foundation
import Testing

struct ElectronCashInteropValidator {
    @Test("Electron Cash interop optional boolean parser trims whitespace")
    func validateOptionalBooleanParserTrimsWhitespace() throws {
        #expect(
            try ElectronCashInteropEnvironmentParser.parseOptionalBool(
                " true ",
                environmentVariableName: "OPALFUSION_EC_COORDINATOR_TLS"
            ) == true
        )
        #expect(
            try ElectronCashInteropEnvironmentParser.parseOptionalBool(
                "\n0\t",
                environmentVariableName: "OPALFUSION_EC_TOR_REMOTE_RESOLUTION"
            ) == false
        )
        #expect(
            try ElectronCashInteropEnvironmentParser.parseOptionalBool(
                "   ",
                environmentVariableName: "OPALFUSION_EC_TOR_REMOTE_RESOLUTION"
            ) == nil
        )
    }

    @Test("Electron Cash interop numeric parser trims whitespace")
    func validateNumericParserTrimsWhitespace() throws {
        #expect(
            try ElectronCashInteropEnvironmentParser.parseUInt16(
                " 50001 ",
                environmentVariableName: "OPALFUSION_EC_COORDINATOR_PORT"
            ) == 50_001
        )
        #expect(
            try ElectronCashInteropEnvironmentParser.parseUInt32(
                "\n1\t",
                environmentVariableName: "OPALFUSION_EC_INPUT_INDEX"
            ) == 1
        )
        #expect(
            try ElectronCashInteropEnvironmentParser.parseUInt64(
                " 100000 ",
                environmentVariableName: "OPALFUSION_EC_JOIN_TIER"
            ) == 100_000
        )
    }

    @Test("Electron Cash interop ignores blank optional Tor settings")
    func validateBlankOptionalTorSettingsAreIgnored() throws {
        var environment = try makeMinimumInteropEnvironment()
        environment["OPALFUSION_EC_TOR_SOCKS5_PORT"] = "  "
        environment["OPALFUSION_EC_TOR_REMOTE_RESOLUTION"] = "\n\t"

        let configuration = try ElectronCashInteropConfiguration.fromEnvironment(environment)

        #expect(configuration.clientConfiguration.torSocks5 == nil)
    }

    @Test(
        "Real Electron Cash 4.4.3 coordinator smoke reaches eventual session success",
        .enabled(
            if: ProcessInfo.processInfo.environment["OPALFUSION_EC_INTEROP"] == "1",
            "Set OPALFUSION_EC_INTEROP=1 and the required OPALFUSION_EC_* variables to run the real Electron Cash interop smoke."
        )
    )
    func validateRealElectronCashCoordinatorInterop() async throws {
        let interopConfiguration = try ElectronCashInteropConfiguration.fromEnvironment()
        let participantReservationSource = DelayedParticipantReservationSource(
            participantInputs: interopConfiguration.participantReservation.inputs,
            participantOutputs: interopConfiguration.participantReservation.outputs
        )
        let transactionAssembler = SigningTransactionAssembler(
            participantInput: interopConfiguration.participantReservation.inputs[0],
            participantInputPrivateKey: interopConfiguration.participantInputPrivateKey
        )
        let eventObserver = RecordedRoundEventObserver()
        let stateObserver = RecordedClientStateObserver()
        let primaryTransport = RecordingPrimaryTransport(
            base: OpalFusion.Runtime.LivePrimaryTransport(
                host: interopConfiguration.clientConfiguration.coordinatorHost,
                port: interopConfiguration.clientConfiguration.coordinatorPort,
                requiresTLS: interopConfiguration.clientConfiguration.coordinatorRequiresTLS
            )
        )
        let covertTransport = RecordingCovertTransport(
            base: OpalFusion.Runtime.LiveCovertTransport(
                torSocks5: interopConfiguration.clientConfiguration.torSocks5
            )
        )
        let session = OpalFusion.Client.Session(
            configuration: interopConfiguration.clientConfiguration,
            genesisHash: interopConfiguration.genesisHash,
            joinPools: interopConfiguration.joinPools,
            participantReservationSource: participantReservationSource,
            transactionAssembler: transactionAssembler,
            eventObserver: eventObserver,
            stateObserver: stateObserver,
            primaryTransportFactory: { primaryTransport },
            covertTransportFactory: { covertTransport }
        )

        await session.start()
        defer {
            Task {
                await session.stop()
            }
        }

        let snapshot = try await SessionTranscriptHarness.waitForSessionSuccessOrFatalTermination(
            session: session,
            timeout: .seconds(600)
        )

        #expect(snapshot.lastError == nil)
        #expect(snapshot.state.isConnected == true)
        #expect(snapshot.state.round?.phase == .completed)
        #expect(snapshot.state.round?.completionStatus == .success)

        let transcript = SessionTranscript(
            clientMessageKinds: await primaryTransport.recordedClientMessages().map(
                SessionTranscriptHarness.clientKind
            ),
            serverMessageKinds: await primaryTransport.recordedServerMessages().map(
                SessionTranscriptHarness.serverKind
            ),
            covertMessageKinds: await covertTransport.recordedRequestMessages().map(
                SessionTranscriptHarness.covertKind
            ),
            roundEvents: await eventObserver.timedSnapshot(),
            stateSnapshots: await stateObserver.timedSnapshot(),
            reservationRequests: await participantReservationSource.timedRequestRecords(),
            transactionProposals: await transactionAssembler.timedProposalRecords()
        )

        #expect(
            SessionTranscriptHarness.hasSubsequence(
                transcript.clientMessageKinds,
                subsequence: ["clientHello", "joinPools", "playerCommit"]
            )
        )

        #expect(
            SessionTranscriptHarness.hasSubsequence(
                transcript.serverMessageKinds,
                subsequence: [
                    "fusionBegin",
                    "startRound",
                    "blindSignatureResponses",
                    "shareCovertComponents",
                    "fusionResult.success",
                ]
            )
        )

        #expect(
            SessionTranscriptHarness.hasSubsequence(
                transcript.covertMessageKinds,
                subsequence: ["component", "transactionSignature"]
            )
        )
        #expect(transcript.roundOutcomes.contains { $0.outcome == .success })
        let outcomesBeforeSuccess = transcript.roundOutcomes.prefix { $0.outcome != .success }
        #expect(
            outcomesBeforeSuccess.allSatisfy { outcome in
                outcome.outcome == .blameRequired || outcome.outcome == .restarted
            }
        )

        #expect(await primaryTransport.recordedOutboundDecodeFailures().isEmpty)
        #expect(await primaryTransport.recordedInboundDecodeFailures().isEmpty)
        #expect(await covertTransport.recordedRequestDecodeFailures().isEmpty)
        #expect(await covertTransport.recordedResponseDecodeFailures().isEmpty)

        #expect(transcript.reservationRequests.isEmpty == false)
        #expect(transcript.transactionProposals.isEmpty == false)

        #expect(
            transcript.stateSnapshots.contains {
                $0.snapshot.state.isConnected && $0.snapshot.state.round == nil
            }
        )
        #expect(
            transcript.stateSnapshots.contains {
                $0.snapshot.state.round?.completionStatus == .success
            }
        )

        let observedEventSummaries = transcript.roundEvents.map(\.event.summary)
        #expect(
            SessionTranscriptHarness.hasSubsequence(
                observedEventSummaries,
                subsequence: [
                    "StartRound received; collecting reserved inputs and outputs",
                    "Submitting player commitments and blind requests",
                    "Blind signature responses received",
                    "Submitting covert components",
                    "Shared components received; requesting transaction finalization",
                    "Transaction finalized; waiting for signature window",
                    "Submitting covert transaction signatures",
                    "Round completed successfully",
                ]
            )
        )
        let firstReservationRequest = try #require(transcript.reservationRequests.first?.recordedAt)
        let firstProposal = try #require(transcript.transactionProposals.first?.recordedAt)
        let successEvent = try #require(
            transcript.roundEvents.first {
                $0.event.summary == "Round completed successfully"
            }?.recordedAt
        )
        #expect(firstReservationRequest <= firstProposal)
        #expect(firstProposal <= successEvent)
    }

    private func makeMinimumInteropEnvironment() throws -> [String: String] {
        let scenario = try ProductionWorkflowTestFixtures.makeScenario()
        let input = try #require(scenario.reservation.inputs.first)
        let output = try #require(scenario.reservation.outputs.first)
        let genesisHash = try #require(PrimaryRuntimeTestFixtures.clientHello.genesisHash)

        return [
            "OPALFUSION_EC_COORDINATOR_HOST": "127.0.0.1",
            "OPALFUSION_EC_COORDINATOR_PORT": "50001",
            "OPALFUSION_EC_GENESIS_HASH_HEX": hexString(genesisHash),
            "OPALFUSION_EC_JOIN_TIER": "10000",
            "OPALFUSION_EC_INPUT_TXID_HEX": hexString(input.outpointTransactionHashBytes),
            "OPALFUSION_EC_INPUT_VOUT": "\(input.outpointIndex)",
            "OPALFUSION_EC_INPUT_AMOUNT_SATOSHIS": "\(input.amountSatoshis)",
            "OPALFUSION_EC_INPUT_LOCKING_SCRIPT_HEX": hexString(input.lockingScriptBytes),
            "OPALFUSION_EC_INPUT_PRIVATE_KEY_HEX": hexString(scenario.participantInputPrivateKey),
            "OPALFUSION_EC_OUTPUT_LOCKING_SCRIPT_HEX": hexString(output.lockingScriptBytes),
            "OPALFUSION_EC_OUTPUT_AMOUNT_SATOSHIS": "\(output.amountSatoshis)"
        ]
    }

    private func hexString(_ bytes: [UInt8]) -> String {
        bytes.map { String(format: "%02x", $0) }.joined()
    }
}

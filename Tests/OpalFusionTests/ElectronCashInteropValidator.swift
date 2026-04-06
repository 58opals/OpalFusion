// ElectronCashInteropValidator.swift

@testable import OpalFusion
import Foundation
import Testing

struct ElectronCashInteropValidator {
    @Test(
        "Real Electron Cash 4.4.3 coordinator smoke reaches eventual session success",
        .enabled(
            if: ProcessInfo.processInfo.environment["OPALFUSION_EC_INTEROP"] == "1",
            "Set OPALFUSION_EC_INTEROP=1 and the required OPALFUSION_EC_* variables to run the real Electron Cash interop smoke."
        )
    )
    func validateRealElectronCashCoordinatorInterop() async throws {
        let interopConfiguration = try ElectronCashInteropConfiguration.fromEnvironment()
        let participantInputProvider = DelayedParticipantInputProvider(
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
                port: interopConfiguration.clientConfiguration.coordinatorPort
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
            participantInputProvider: participantInputProvider,
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

        let snapshot = try await SessionTranscriptSupport.waitForSessionSuccessOrFatalTermination(
            session: session,
            timeout: .seconds(600)
        )

        #expect(snapshot.lastError == nil)
        #expect(snapshot.state.isConnected == true)
        #expect(snapshot.state.round?.phase == .completed)
        #expect(snapshot.state.round?.completionStatus == .success)

        let transcript = SessionTranscript(
            clientMessageKinds: await primaryTransport.recordedClientMessages().map(
                SessionTranscriptSupport.clientKind
            ),
            serverMessageKinds: await primaryTransport.recordedServerMessages().map(
                SessionTranscriptSupport.serverKind
            ),
            covertMessageKinds: await covertTransport.recordedRequestMessages().map(
                SessionTranscriptSupport.covertKind
            ),
            roundEvents: await eventObserver.timedSnapshot(),
            stateSnapshots: await stateObserver.timedSnapshot(),
            reservationRequests: await participantInputProvider.timedRequestRecords(),
            transactionProposals: await transactionAssembler.timedProposalRecords()
        )

        #expect(
            SessionTranscriptSupport.containsSubsequence(
                transcript.clientMessageKinds,
                subsequence: ["clientHello", "joinPools", "playerCommit"]
            )
        )

        #expect(
            SessionTranscriptSupport.containsSubsequence(
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
            SessionTranscriptSupport.containsSubsequence(
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
            SessionTranscriptSupport.containsSubsequence(
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
        guard
            let firstReservationRequest = transcript.reservationRequests.first?.recordedAt,
            let firstProposal = transcript.transactionProposals.first?.recordedAt,
            let successEvent = transcript.roundEvents.first(where: {
                $0.event.summary == "Round completed successfully"
            })?.recordedAt
        else {
            Issue.record("Expected timed reservation, proposal, and success-event records")
            return
        }
        #expect(firstReservationRequest <= firstProposal)
        #expect(firstProposal <= successEvent)
    }
}

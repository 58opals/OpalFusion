// ElectronCashInteropValidator+ValidationGroup2.swift

@testable import OpalFusion
import Foundation
import Testing

extension ElectronCashInteropValidator {
    @Test(
        "Electron Cash interop completes a real coordinator session",
        .enabled(if: ElectronCashInteropTestSupport.isLiveCoordinatorInteropEnabled)
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
            hostParticipantReservationSource: participantReservationSource,
            hostTransactionAssembler: transactionAssembler,
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

        let clientMessageKinds = (await primaryTransport.recordedClientMessages).map(
            SessionTranscriptHarness.describeClientMessageKind
        )
        let serverMessageKinds = (await primaryTransport.recordedServerMessages).map(
            SessionTranscriptHarness.describeServerMessageKind
        )
        let covertMessageKinds = (await covertTransport.recordedRequestMessages).map(
            SessionTranscriptHarness.describeCovertMessageKind
        )
        let covertResponseKinds = (await covertTransport.recordedResponses).map(
            SessionTranscriptHarness.describeCovertResponseKind
        )
        let primaryOutboundDecodeFailures = await primaryTransport
            .recordedOutboundDecodeFailures
        let primaryInboundDecodeFailures = await primaryTransport
            .recordedInboundDecodeFailures
        let covertRequestDecodeFailures = await covertTransport
            .recordedRequestDecodeFailures
        let covertResponseDecodeFailures = await covertTransport
            .recordedResponseDecodeFailures

        let transcript = SessionTranscript(
            clientMessageKinds: clientMessageKinds,
            serverMessageKinds: serverMessageKinds,
            covertMessageKinds: covertMessageKinds,
            roundEvents: await eventObserver.timedSnapshots,
            stateSnapshots: await stateObserver.timedSnapshots,
            reservationRequests: await participantReservationSource.timedRequestRecords,
            transactionProposals: await transactionAssembler.timedProposalRecords
        )

        let hasExpectedClientMessages = SessionTranscriptHarness.hasSubsequence(
            transcript.clientMessageKinds,
            subsequence: ["clientHello", "joinPools", "playerCommit"]
        )
        #expect(hasExpectedClientMessages)

        let hasExpectedServerMessages = SessionTranscriptHarness.hasSubsequence(
            transcript.serverMessageKinds,
            subsequence: [
                "fusionBegin",
                "startRound",
                "blindSignatureResponses",
                "shareCovertComponents",
                "fusionResult.success",
            ]
        )
        #expect(hasExpectedServerMessages)

        let hasExpectedCovertMessages = SessionTranscriptHarness.hasSubsequence(
            transcript.covertMessageKinds,
            subsequence: ["component", "transactionSignature"]
        )
        #expect(hasExpectedCovertMessages)
        #expect(transcript.roundOutcomes.contains { $0.outcome == .success })
        let outcomesBeforeSuccess = transcript.roundOutcomes.prefix { $0.outcome != .success }
        #expect(
            outcomesBeforeSuccess.allSatisfy { outcome in
                outcome.outcome == .blameRequired || outcome.outcome == .restarted
            }
        )

        #expect(primaryOutboundDecodeFailures.isEmpty)
        #expect(primaryInboundDecodeFailures.isEmpty)
        #expect(covertRequestDecodeFailures.isEmpty)
        #expect(covertResponseDecodeFailures.isEmpty)

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

        if shouldEmitTranscriptCapture(
            snapshot: snapshot,
            hasExpectedClientMessages: hasExpectedClientMessages,
            hasExpectedServerMessages: hasExpectedServerMessages,
            hasExpectedCovertMessages: hasExpectedCovertMessages,
            primaryOutboundDecodeFailures: primaryOutboundDecodeFailures,
            primaryInboundDecodeFailures: primaryInboundDecodeFailures,
            covertRequestDecodeFailures: covertRequestDecodeFailures,
            covertResponseDecodeFailures: covertResponseDecodeFailures
        ) {
            let capture = ElectronCashTranscriptCapture(
                primaryInboundChunks: await primaryTransport.recordedInboundPrimaryChunks,
                primaryOutboundChunks: await primaryTransport.recordedOutboundPrimaryChunks,
                covertRequestPayloads: await covertTransport.recordedRequestPayloads,
                covertResponsePayloads: await covertTransport.recordedResponsePayloads,
                clientMessageKinds: clientMessageKinds,
                serverMessageKinds: serverMessageKinds,
                covertMessageKinds: covertMessageKinds,
                covertResponseKinds: covertResponseKinds,
                roundOutcomes: transcript.roundOutcomes.map(\.outcome.rawValue),
                eventSummaries: observedEventSummaries
            )
            print(ElectronCashTranscriptCaptureLiteralEmitter.makeMarkedSwiftFixtureCandidate(for: capture))
        }
    }
}

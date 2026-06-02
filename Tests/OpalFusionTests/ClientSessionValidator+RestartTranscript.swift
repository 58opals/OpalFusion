// ClientSessionValidator+RestartTranscript.swift

@testable import OpalFusion
import Testing

extension ClientSessionValidator {
    func assertRestartSessionTranscript(
        coordinator: LoopbackPrimaryCoordinator,
        recordingCovertTransport: RecordingCovertTransport,
        eventObserver: RecordedRoundEventObserver,
        stateObserver: RecordedClientStateObserver,
        participantReservationSource: DelayedParticipantReservationSource,
        transactionAssembler: DelayedTransactionAssembler,
        firstStartRound: OpalFusion.ProtocolModel.StartRound,
        secondStartRound: OpalFusion.ProtocolModel.StartRound,
        session: OpalFusion.Client.Session
    ) async {
        let firstRoundIdentifier = SessionTranscriptHarness.makeRoundIdentifier(
            from: firstStartRound.roundPublicKey
        )
        let secondRoundIdentifier = SessionTranscriptHarness.makeRoundIdentifier(
            from: secondStartRound.roundPublicKey
        )
        let transcript = SessionTranscript(
            clientMessageKinds: (await coordinator.recordedClientMessages).map(
                SessionTranscriptHarness.describeClientMessageKind
            ),
            serverMessageKinds: (await coordinator.recordedServerMessages).map(
                SessionTranscriptHarness.describeServerMessageKind
            ),
            covertMessageKinds: (await recordingCovertTransport.recordedRequestMessages).map(
                SessionTranscriptHarness.describeCovertMessageKind
            ),
            roundEvents: await eventObserver.timedSnapshots,
            stateSnapshots: await stateObserver.timedSnapshots,
            reservationRequests: await participantReservationSource.timedRequestRecords,
            transactionProposals: await transactionAssembler.timedProposalRecords
        )

        #expect(transcript.reservationRequests.map(\.roundIdentifier) == [firstRoundIdentifier, secondRoundIdentifier])
        #expect(transcript.transactionProposals.map(\.roundIdentifier) == [firstRoundIdentifier, secondRoundIdentifier])
        #expect(
            transcript.roundOutcomes.contains {
                $0.roundIdentifier == firstRoundIdentifier && $0.outcome == .blameRequired
            }
        )
        #expect(
            transcript.roundOutcomes.contains {
                $0.roundIdentifier == firstRoundIdentifier && $0.outcome == .restarted
            }
        )
        #expect(
            transcript.roundOutcomes.contains {
                $0.roundIdentifier == secondRoundIdentifier && $0.outcome == .success
            }
        )
        #expect(
            SessionTranscriptHarness.hasSubsequence(
                transcript.roundEvents.map(\.event.summary),
                subsequence: [
                    "Round result requires blame handling",
                    "Submitting blame proofs and awaiting restart",
                    "Restarting round after blame handling",
                    "Round completed successfully",
                ]
            )
        )
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
        guard
            let restartedConnectedSnapshotTime = transcript.stateSnapshots.first(where: {
                $0.snapshot.state.isConnected && $0.snapshot.state.round == nil
            })?.recordedAt,
            let successSnapshotTime = transcript.stateSnapshots.first(where: {
                $0.snapshot.state.round?.completionStatus == .success
            })?.recordedAt
        else {
            Issue.record("Expected timed restart and success snapshots for ordering coverage")
            await session.stop()
            return
        }
        #expect(restartedConnectedSnapshotTime <= successSnapshotTime)
    }
}

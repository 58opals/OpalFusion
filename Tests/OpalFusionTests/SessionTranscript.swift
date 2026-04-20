// SessionTranscript.swift

@testable import OpalFusion

struct SessionTranscript: Sendable {
    let clientMessageKinds: [String]
    let serverMessageKinds: [String]
    let covertMessageKinds: [String]
    let roundEvents: [TimedRecordedRoundEvent]
    let stateSnapshots: [TimedClientSessionSnapshot]
    let reservationRequests: [TimedRoundRequestRecord]
    let transactionProposals: [TimedTransactionProposalRecord]
    let roundOutcomes: [TimedSessionRoundOutcome]

    init(
        clientMessageKinds: [String],
        serverMessageKinds: [String],
        covertMessageKinds: [String],
        roundEvents: [TimedRecordedRoundEvent],
        stateSnapshots: [TimedClientSessionSnapshot],
        reservationRequests: [TimedRoundRequestRecord],
        transactionProposals: [TimedTransactionProposalRecord]
    ) {
        self.clientMessageKinds = clientMessageKinds
        self.serverMessageKinds = serverMessageKinds
        self.covertMessageKinds = covertMessageKinds
        self.roundEvents = roundEvents
        self.stateSnapshots = stateSnapshots
        self.reservationRequests = reservationRequests
        self.transactionProposals = transactionProposals
        self.roundOutcomes = Self.makeRoundOutcomes(
            roundEvents: roundEvents,
            stateSnapshots: stateSnapshots
        )
    }

    private static func makeRoundOutcomes(
        roundEvents: [TimedRecordedRoundEvent],
        stateSnapshots: [TimedClientSessionSnapshot]
    ) -> [TimedSessionRoundOutcome] {
        var outcomes: [TimedSessionRoundOutcome] = []

        for event in roundEvents {
            let outcome: SessionRoundOutcomeKind?
            switch event.event.summary {
            case "Round result requires blame handling":
                outcome = .blameRequired
            case "Restarting round after blame handling":
                outcome = .restarted
            default:
                outcome = nil
            }

            if let outcome {
                outcomes.append(
                    .init(
                        roundIdentifier: event.roundIdentifier,
                        outcome: outcome,
                        recordedAt: event.recordedAt
                    )
                )
            }
        }

        for timedSnapshot in stateSnapshots {
            guard let round = timedSnapshot.snapshot.state.round,
                  let completionStatus = round.completionStatus else {
                continue
            }

            outcomes.append(
                .init(
                    roundIdentifier: round.identifier,
                    outcome: outcomeKind(for: completionStatus),
                    recordedAt: timedSnapshot.recordedAt
                )
            )
        }

        return deduplicate(outcomes)
    }

    private static func deduplicate(
        _ outcomes: [TimedSessionRoundOutcome]
    ) -> [TimedSessionRoundOutcome] {
        var seen = Set<String>()
        var result: [TimedSessionRoundOutcome] = []

        for outcome in outcomes.sorted(by: { $0.recordedAt < $1.recordedAt }) {
            let key = "\(outcome.roundIdentifier.rawValue):\(outcome.outcome.rawValue)"
            if seen.insert(key).inserted {
                result.append(outcome)
            }
        }

        return result
    }

    private static func outcomeKind(
        for completionStatus: OpalFusion.Round.CompletionStatus
    ) -> SessionRoundOutcomeKind {
        switch completionStatus {
        case .success:
            .success
        case .coordinatorRejected:
            .coordinatorRejected
        case .hostRejected:
            .hostRejected
        case .protocolIncompatible:
            .protocolIncompatible
        case .transportFailed:
            .transportFailed
        case .blameRequired:
            .blameRequired
        }
    }
}

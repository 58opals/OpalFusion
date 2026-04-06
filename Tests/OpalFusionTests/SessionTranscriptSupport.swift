// SessionTranscriptSupport.swift

@testable import OpalFusion
import Foundation

enum SessionRoundOutcomeKind: String, Sendable, Equatable {
    case success
    case blameRequired
    case restarted
    case coordinatorRejected
    case hostRejected
    case protocolIncompatible
    case transportFailed
}

struct TimedSessionRoundOutcome: Sendable, Equatable {
    let roundIdentifier: OpalFusion.Round.Identifier
    let outcome: SessionRoundOutcomeKind
    let recordedAt: Date
}

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

enum SessionTranscriptSupport {
    static func waitForSessionSuccessOrFatalTermination(
        session: OpalFusion.Client.Session,
        timeout: Duration,
        pollInterval: Duration = .milliseconds(250)
    ) async throws -> OpalFusion.Client.Session.Snapshot {
        try await withTimeout(timeout) {
            while true {
                let snapshot = await session.snapshot()

                if let completionStatus = snapshot.state.round?.completionStatus {
                    switch completionStatus {
                    case .success,
                         .coordinatorRejected,
                         .hostRejected,
                         .protocolIncompatible,
                         .transportFailed:
                        return snapshot
                    case .blameRequired:
                        break
                    }
                } else if snapshot.lastError != nil, snapshot.state.round == nil {
                    return snapshot
                }

                try await Task.sleep(for: pollInterval)
            }
        }
    }

    static func clientKind(
        _ message: OpalFusion.ProtocolModel.ClientMessage
    ) -> String {
        switch message {
        case .clientHello:
            "clientHello"
        case .joinPools:
            "joinPools"
        case .playerCommit:
            "playerCommit"
        case .myProofsList:
            "myProofsList"
        case .blames:
            "blames"
        }
    }

    static func serverKind(
        _ message: OpalFusion.ProtocolModel.ServerMessage
    ) -> String {
        switch message {
        case .serverHello:
            "serverHello"
        case .tierStatusUpdate:
            "tierStatusUpdate"
        case .fusionBegin:
            "fusionBegin"
        case .startRound:
            "startRound"
        case .blindSignatureResponses:
            "blindSignatureResponses"
        case .allCommitments:
            "allCommitments"
        case .shareCovertComponents:
            "shareCovertComponents"
        case let .fusionResult(result):
            result.isSuccess ? "fusionResult.success" : "fusionResult.failure"
        case .theirProofsList:
            "theirProofsList"
        case .restartRound:
            "restartRound"
        case .serverFailure:
            "serverFailure"
        }
    }

    static func covertKind(
        _ message: OpalFusion.ProtocolModel.CovertMessage
    ) -> String {
        switch message {
        case .component:
            "component"
        case .transactionSignature:
            "transactionSignature"
        case .ping:
            "ping"
        }
    }

    static func makeRoundIdentifier(
        from roundPublicKey: [UInt8]
    ) -> OpalFusion.Round.Identifier {
        let hexDigits = Array("0123456789abcdef")
        let hex = roundPublicKey.reduce(into: String()) { partialResult, byte in
            partialResult.append(hexDigits[Int(byte >> 4)])
            partialResult.append(hexDigits[Int(byte & 0x0F)])
        }
        return .init(rawValue: hex)
    }

    static func containsSubsequence<T: Equatable>(
        _ sequence: [T],
        subsequence: [T]
    ) -> Bool {
        guard subsequence.isEmpty == false else {
            return true
        }

        var subsequenceIndex = 0
        for element in sequence where element == subsequence[subsequenceIndex] {
            subsequenceIndex += 1
            if subsequenceIndex == subsequence.count {
                return true
            }
        }

        return false
    }
}

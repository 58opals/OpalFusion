// SessionTranscriptHarness.swift

@testable import OpalFusion

enum SessionTranscriptHarness {
    static func waitForSessionSuccessOrFatalTermination(
        session: OpalFusion.Client.Session,
        timeout: Duration,
        pollInterval: Duration = .milliseconds(250)
    ) async throws -> OpalFusion.Client.Session.Snapshot {
        try await LiveRuntimeTestHarness.withTimeout(timeout) {
            while true {
                let snapshot = await session.currentSnapshot

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

    static func describeClientMessageKind(
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

    static func describeServerMessageKind(
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

    static func describeCovertMessageKind(
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

    static func describeCovertResponseKind(
        _ response: OpalFusion.ProtocolModel.CovertResponse
    ) -> String {
        switch response {
        case .acknowledgement:
            "acknowledgement"
        case .serverFailure:
            "serverFailure"
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

    static func hasSubsequence<T: Equatable>(
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

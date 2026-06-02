// OpalFusion+Execution+RoundEngine+PreRoundPrimaryMessage.swift

import Foundation

extension OpalFusion.Execution.RoundEngine {
    mutating func handlePreRoundPrimaryMessage(
        _ message: OpalFusion.ProtocolModel.ServerMessage,
        now: OpalFusion.Execution.Instant
    ) -> [OpalFusion.Execution.RoundEngine.Effect] {
        switch session.connectionSubstate {
        case .awaitingServerHello:
            return handleServerHelloBeforeRound(message)
        case .awaitingFusionBegin:
            return handleFusionBeginBeforeRound(message, now: now)
        case .disconnected, .inRound, .failed:
            return []
        }
    }

    mutating func handleServerHelloBeforeRound(
        _ message: OpalFusion.ProtocolModel.ServerMessage
    ) -> [OpalFusion.Execution.RoundEngine.Effect] {
        guard case let .serverHello(serverHello) = message else {
            return failBeforeRound(
                error: .protocolIncompatible,
                summary: "Unexpected message before ServerHello"
            )
        }
        guard serverHello.numberOfComponents > 0 else {
            return failBeforeRound(
                error: .protocolIncompatible,
                summary: "ServerHello component count was invalid"
            )
        }
        guard serverHello.minimumExcessFeeSatoshis <= serverHello.maximumExcessFeeSatoshis else {
            return failBeforeRound(
                error: .protocolIncompatible,
                summary: "ServerHello excess fee range was invalid"
            )
        }

        session.latestServerHello = serverHello
        session.connectionSubstate = .awaitingFusionBegin

        return [
            .sendPrimary(.joinPools(session.joinPools)),
            hostEvent(
                roundIdentifier: nil,
                kind: .status,
                phase: .connecting,
                summary: "ServerHello received; joining eligible pools"
            )
        ]
    }

    mutating func handleFusionBeginBeforeRound(
        _ message: OpalFusion.ProtocolModel.ServerMessage,
        now: OpalFusion.Execution.Instant
    ) -> [OpalFusion.Execution.RoundEngine.Effect] {
        switch message {
        case let .tierStatusUpdate(update):
            session.latestTierStatus = update
            return []
        case let .fusionBegin(fusionBegin):
            return beginRound(from: fusionBegin, now: now)
        default:
            return failBeforeRound(
                error: .protocolIncompatible,
                summary: "Unexpected message before FusionBegin"
            )
        }
    }

    mutating func beginRound(
        from fusionBegin: OpalFusion.ProtocolModel.FusionBegin,
        now: OpalFusion.Execution.Instant
    ) -> [OpalFusion.Execution.RoundEngine.Effect] {
        guard let serverHello = session.latestServerHello else {
            return failBeforeRound(
                error: .protocolIncompatible,
                summary: "FusionBegin arrived before a valid ServerHello was recorded"
            )
        }
        guard session.joinPools.tiers.contains(fusionBegin.tier) else {
            return failBeforeRound(
                error: .protocolIncompatible,
                summary: "FusionBegin tier was not requested"
            )
        }
        guard serverHello.tiers.contains(fusionBegin.tier) else {
            return failBeforeRound(
                error: .protocolIncompatible,
                summary: "FusionBegin tier was not advertised by ServerHello"
            )
        }
        guard (1 ... UInt32(UInt16.max)).contains(fusionBegin.covertPort) else {
            return failBeforeRound(
                error: .protocolIncompatible,
                summary: "FusionBegin covert port was outside the supported range"
            )
        }
        guard isValidCovertDomain(fusionBegin.covertDomain) else {
            return failBeforeRound(
                error: .protocolIncompatible,
                summary: "FusionBegin covert domain was invalid"
            )
        }
        guard isServerTimeAcceptable(fusionBegin.serverTimeUnixSeconds, now: now) else {
            return failBeforeRound(
                error: .protocolIncompatible,
                summary: "FusionBegin server time exceeded the allowed clock skew"
            )
        }

        round = .init(
            fusionBegin: fusionBegin,
            serverHello: serverHello,
            deadlines: .fromFusionBegin(
                fusionBegin,
                timing: session.baseline.roundTiming
            )
        )
        session.connectionSubstate = .inRound

        return [
            .prepareCovert(makeCovertEndpointContext(from: fusionBegin)),
            hostEvent(
                roundIdentifier: nil,
                kind: .status,
                phase: .connecting,
                summary: "Fusion warmup started"
            )
        ]
    }
}

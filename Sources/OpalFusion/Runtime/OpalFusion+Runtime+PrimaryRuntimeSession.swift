// OpalFusion+Runtime+PrimaryRuntimeSession.swift

import OpalDiagnostics

extension OpalFusion.Runtime {
    struct PrimaryRuntimeSession: Sendable {
        var frameDecoder: OpalFusion.Wire.PrimaryFrameDecoder
        let frameEncoder: OpalFusion.Wire.PrimaryFrameEncoder
        let messageEncoder: OpalFusion.Wire.PrimaryMessageEncoder
        let messageDecoder: OpalFusion.Wire.PrimaryMessageDecoder
        var preRoundTrace: PreRoundTrace
        var covertSession: OpalFusion.Runtime.CovertRuntimeSession
        var engine: OpalFusion.Execution.RoundEngine

        init(
            configuration: OpalFusion.Client.Configuration,
            genesisHash: [UInt8]? = nil,
            joinPools: OpalFusion.ProtocolModel.JoinPools,
            workflow: OpalFusion.Execution.WorkflowContext? = nil,
            baseline: OpalFusion.Transport.BaselineConfiguration = .electronCash443
        ) {
            let resolvedWorkflow = workflow ?? .production(baseline: baseline)
            self.frameDecoder = .init(configuration: baseline.framing)
            self.frameEncoder = .init(configuration: baseline.framing)
            self.messageEncoder = .init()
            self.messageDecoder = .init()
            self.preRoundTrace = .init()
            self.covertSession = .init()
            self.engine = .init(
                configuration: configuration,
                genesisHash: genesisHash,
                joinPools: joinPools,
                workflow: resolvedWorkflow,
                baseline: baseline
            )
        }

        var clientState: OpalFusion.Client.State {
            engine.clientState
        }

        var lastError: OpalFusion.Client.Error? {
            engine.session.lastError
        }

        var lastErrorSummary: String? {
            engine.session.lastErrorSummary
        }

        var coordinatorStatus: OpalFusion.Client.Session.Snapshot.CoordinatorStatus {
            .init(
                updateSequence: preRoundTrace.updateSequence,
                latestInboundMessageKind: preRoundTrace.lastInboundKind?.rawValue,
                latestInboundPayloadByteCount: preRoundTrace.lastInboundPayloadBytes,
                queueStatus: requestedTierQueueStatus
            )
        }








        var shouldTracePreRoundTraffic: Bool {
            guard engine.round == nil else {
                return false
            }

            return switch engine.session.connectionSubstate {
            case .awaitingServerHello, .awaitingFusionBegin:
                true
            case .disconnected, .inRound, .failed:
                false
            }
        }

        var requestedTierQueueStatus: OpalFusion.Client.Session.Snapshot.CoordinatorStatus.TierQueue? {
            guard let latestTierStatus = engine.session.latestTierStatus else {
                return nil
            }

            for tierSatoshis in engine.session.joinPools.tiers {
                guard let tierStatus = latestTierStatus.statusesByTier[tierSatoshis] else {
                    continue
                }

                return .init(
                    tierSatoshis: tierSatoshis,
                    players: tierStatus.playerCount,
                    minPlayers: tierStatus.minimumPlayerCount,
                    maxPlayers: tierStatus.maximumPlayerCount,
                    timeRemaining: tierStatus.timeRemainingSeconds
                )
            }

            return nil
        }









    }
}

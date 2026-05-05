// OpalFusion+Runtime+PrimaryRuntimeSession.swift

import OSLog

extension OpalFusion.Runtime {
    struct PrimaryRuntimeSession: Sendable {
        private static let logger = Logger(
            subsystem: "OpalFusion",
            category: "PrimaryRuntimeSession"
        )

        private(set) var frameDecoder: OpalFusion.Wire.PrimaryFrameDecoder
        private let frameEncoder: OpalFusion.Wire.PrimaryFrameEncoder
        private let messageEncoder: OpalFusion.Wire.PrimaryMessageEncoder
        private let messageDecoder: OpalFusion.Wire.PrimaryMessageDecoder
        private(set) var preRoundTrace: PreRoundTrace
        private(set) var covertSession: OpalFusion.Runtime.CovertRuntimeSession
        private(set) var engine: OpalFusion.Execution.RoundEngine

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

        func diagnostics(
            activity: OpalFusion.Client.Diagnostics.Activity
        ) -> OpalFusion.Client.Diagnostics {
            .init(
                activity: activity,
                primaryFailureCategory: lastError,
                primaryFailureSummary: lastErrorSummary,
                handshakeStage: preRoundTrace.handshakeStage,
                recentEvents: preRoundTrace.recentEvents
            )
        }

        mutating func recordWrittenPrimaryFrame(_ bytes: [UInt8]) {
            guard shouldTracePreRoundTraffic else {
                return
            }

            do {
                var frameDecoder = OpalFusion.Wire.PrimaryFrameDecoder(
                    configuration: engine.session.baseline.framing
                )
                let payloads = try frameDecoder.append(bytes)
                guard payloads.count == 1 else {
                    Self.logger.debug(
                        "primary preround outbound decode failed framedBytes=\(bytes.count, privacy: .public) payloadCount=\(payloads.count, privacy: .public)"
                    )
                    return
                }

                let message = try messageDecoder.decodeClient(payloads[0])
                logPreRoundOutboundMessage(
                    message,
                    payloadBytes: payloads[0].count
                )
            } catch {
                Self.logger.debug(
                    "primary preround outbound decode failed framedBytes=\(bytes.count, privacy: .public) summary=\(String(describing: error), privacy: .private)"
                )
            }
        }

        mutating func apply(
            input: OpalFusion.Runtime.PrimaryRuntimeSession.Input,
            now: OpalFusion.Execution.Instant
        ) -> [OpalFusion.Runtime.PrimaryRuntimeSession.Effect] {
            switch input {
            case let .invalidConfiguration(summary):
                recordFailureEvent(summary: summary)
                return translate(
                    engine.apply(input: .configurationRejected(summary: summary), now: now),
                    now: now
                )
            case .connected:
                recordLifecycleEvent(
                    summary: "Primary channel connected",
                    handshakeStage: .awaitingServerHello
                )
                return translate(
                    engine.apply(input: .primaryConnected, now: now),
                    now: now
                )
            case .disconnected:
                recordFailureEvent(summary: "Primary channel disconnected")
                return translate(
                    engine.apply(input: .primaryDisconnected, now: now),
                    now: now
                )
            case .stopped:
                recordLifecycleEvent(
                    summary: "Session stopped",
                    handshakeStage: .notStarted
                )
                return translate(
                    engine.apply(input: .stopped, now: now),
                    now: now
                )
            case let .primaryTransportFailed(summary):
                recordFailureEvent(summary: summary)
                return translate(
                    engine.apply(input: .primaryTransportFailed(summary: summary), now: now),
                    now: now
                )
            case let .receivedPrimaryBytes(bytes):
                return handleReceivedPrimaryBytes(bytes, now: now)
            case .covertPrepared:
                return handleCovertRuntimeEffects(
                    covertSession.apply(input: .covertPrepared, now: now),
                    now: now
                )
            case let .covertPreparationFailed(summary):
                recordFailureEvent(summary: summary)
                return handleCovertRuntimeEffects(
                    covertSession.apply(
                        input: .covertPreparationFailed(summary: summary),
                        now: now
                    ),
                    now: now
                )
            case let .receivedCovertResponseBytes(bytes):
                return handleCovertRuntimeEffects(
                    covertSession.apply(
                        input: .covertResponseBytesReceived(bytes),
                        now: now
                    ),
                    now: now
                )
            case let .covertRequestFailed(summary):
                recordFailureEvent(summary: summary)
                return handleCovertRuntimeEffects(
                    covertSession.apply(
                        input: .covertRequestFailed(summary: summary),
                        now: now
                    ),
                    now: now
                )
            case let .participantReservationLoaded(reservation):
                return translate(
                    engine.apply(input: .participantReservationLoaded(reservation), now: now),
                    now: now
                )
            case .participantReservationRejected:
                return translate(
                    engine.apply(input: .participantReservationRejected, now: now),
                    now: now
                )
            case let .finalizedTransactionLoaded(transaction):
                return translate(
                    engine.apply(input: .finalizedTransactionLoaded(transaction), now: now),
                    now: now
                )
            case .transactionFinalizationRejected:
                return translate(
                    engine.apply(input: .transactionFinalizationRejected, now: now),
                    now: now
                )
            case .clockAdvanced:
                var runtimeEffects = handleCovertRuntimeEffects(
                    covertSession.apply(input: .clockAdvanced, now: now),
                    now: now
                )
                runtimeEffects.append(contentsOf: translate(
                    engine.apply(input: .clockAdvanced, now: now),
                    now: now
                ))
                return runtimeEffects
            }
        }

        private mutating func handleReceivedPrimaryBytes(
            _ bytes: [UInt8],
            now: OpalFusion.Execution.Instant
        ) -> [OpalFusion.Runtime.PrimaryRuntimeSession.Effect] {
            do {
                let payloads = try frameDecoder.append(bytes)
                var runtimeEffects: [OpalFusion.Runtime.PrimaryRuntimeSession.Effect] = []

                for payload in payloads {
                    let message = try messageDecoder.decodeServer(payload)
                    logPreRoundInboundMessage(
                        message,
                        payloadBytes: payload.count
                    )
                    let effects = translate(
                        engine.apply(input: .primaryMessage(message), now: now),
                        now: now
                    )
                    updateHandshakeStageFromEngine()
                    runtimeEffects.append(
                        contentsOf: effects
                    )
                }

                _ = try frameDecoder.append([])
                return runtimeEffects
            } catch {
                if shouldTracePreRoundTraffic {
                    Self.logger.debug(
                        "primary preround inbound decode failed chunkBytes=\(bytes.count, privacy: .public) summary=\(String(describing: error), privacy: .private)"
                    )
                }
                return protocolFailureEffects(
                    summary: "Primary wire decode failed",
                    now: now
                )
            }
        }

        private mutating func translate(
            _ engineEffects: [OpalFusion.Execution.RoundEngine.Effect],
            now: OpalFusion.Execution.Instant
        ) -> [OpalFusion.Runtime.PrimaryRuntimeSession.Effect] {
            var runtimeEffects: [OpalFusion.Runtime.PrimaryRuntimeSession.Effect] = []

            for effect in engineEffects {
                switch effect {
                case let .sendPrimary(message):
                    do {
                        let payload = try messageEncoder.encode(message)
                        let framed = try frameEncoder.encode(payload: payload)
                        runtimeEffects.append(.writePrimaryBytes(framed))
                    } catch {
                        return runtimeEffects + protocolFailureEffects(
                            summary: "Primary wire encode failed",
                            now: now
                        )
                    }
                case let .prepareCovert(endpointContext):
                    runtimeEffects.append(
                        contentsOf: handleCovertRuntimeEffects(
                            covertSession.apply(
                                input: .prepare(endpointContext: endpointContext),
                                now: now
                            ),
                            now: now
                        )
                    )
                case let .submitCovert(message):
                    runtimeEffects.append(
                        contentsOf: handleCovertRuntimeEffects(
                            covertSession.apply(
                                input: .enqueue(message: message),
                                now: now
                            ),
                            now: now
                        )
                    )
                case let .requestParticipantReservation(roundIdentifier):
                    runtimeEffects.append(
                        .requestParticipantReservation(roundIdentifier: roundIdentifier)
                    )
                case let .requestTransactionFinalization(roundIdentifier, proposal):
                    runtimeEffects.append(
                        .requestTransactionFinalization(
                            roundIdentifier: roundIdentifier,
                            proposal: proposal
                        )
                    )
                case let .emitHostEvent(roundIdentifier, event):
                    runtimeEffects.append(
                        .emitHostEvent(
                            roundIdentifier: roundIdentifier,
                            event: event
                        )
                    )
                }
            }

            if engine.session.connectionSubstate != .inRound {
                _ = covertSession.apply(input: .reset, now: now)
            }

            return runtimeEffects
        }

        private mutating func handleCovertRuntimeEffects(
            _ covertEffects: [OpalFusion.Runtime.CovertRuntimeSession.Effect],
            now: OpalFusion.Execution.Instant
        ) -> [OpalFusion.Runtime.PrimaryRuntimeSession.Effect] {
            var runtimeEffects: [OpalFusion.Runtime.PrimaryRuntimeSession.Effect] = []

            for effect in covertEffects {
                switch effect {
                case let .prepareCovertEndpoint(plan):
                    runtimeEffects.append(.prepareCovertEndpoint(plan: plan))
                case let .performCovertRequest(request):
                    runtimeEffects.append(.performCovertRequest(request: request))
                case let .deliverCovertResponse(response):
                    runtimeEffects.append(
                        contentsOf: translate(
                            engine.apply(input: .covertResponse(response), now: now),
                            now: now
                        )
                    )
                case let .emitProtocolFailure(summary):
                    runtimeEffects.append(
                        contentsOf: translate(
                            engine.apply(
                                input: .protocolRejected(summary: summary),
                                now: now
                            ),
                            now: now
                        )
                    )
                case let .emitTransportFailure(summary):
                    runtimeEffects.append(
                        contentsOf: translate(
                            engine.apply(
                                input: .covertTransportFailed(summary: summary),
                                now: now
                            ),
                            now: now
                        )
                    )
                }
            }

            return runtimeEffects
        }

        private mutating func protocolFailureEffects(
            summary: String,
            now: OpalFusion.Execution.Instant
        ) -> [OpalFusion.Runtime.PrimaryRuntimeSession.Effect] {
            recordFailureEvent(summary: summary)
            return translate(
                engine.apply(
                    input: .protocolRejected(summary: summary),
                    now: now
                ),
                now: now
            )
        }

        private var shouldTracePreRoundTraffic: Bool {
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

        private mutating func logPreRoundInboundMessage(
            _ message: OpalFusion.ProtocolModel.ServerMessage,
            payloadBytes: Int
        ) {
            guard shouldTracePreRoundTraffic else {
                return
            }

            switch message {
            case let .serverHello(serverHello):
                preRoundTrace.lastInboundKind = .serverHello
                preRoundTrace.lastInboundPayloadBytes = payloadBytes
                preRoundTrace.sawServerHello = true
                preRoundTrace.handshakeStage = .awaitingFusionBegin
                appendDiagnosticEvent(
                    .init(
                        kind: .inboundMessage,
                        summary: "Received ServerHello",
                        messageKind: "ServerHello",
                        payloadByteCount: payloadBytes,
                        handshakeStage: preRoundTrace.handshakeStage
                    )
                )
                Self.logger.debug(
                    "primary preround inbound kind=ServerHello payloadBytes=\(payloadBytes, privacy: .public) tiersCount=\(serverHello.tiers.count, privacy: .public) firstTier=\(Self.describe(serverHello.tiers.first), privacy: .public) numberOfComponents=\(Int(serverHello.numberOfComponents), privacy: .public)"
                )
            case let .tierStatusUpdate(update):
                preRoundTrace.lastInboundKind = .tierStatusUpdate
                preRoundTrace.lastInboundPayloadBytes = payloadBytes
                appendDiagnosticEvent(
                    .init(
                        kind: .inboundMessage,
                        summary: "Received TierStatusUpdate",
                        messageKind: "TierStatusUpdate",
                        payloadByteCount: payloadBytes,
                        handshakeStage: preRoundTrace.handshakeStage
                    )
                )
                Self.logger.debug(
                    "primary preround inbound kind=TierStatusUpdate payloadBytes=\(payloadBytes, privacy: .public) statusTierCount=\(update.statusesByTier.count, privacy: .public) firstTier=\(Self.describe(update.statusesByTier.keys.sorted().first), privacy: .public)"
                )
            case let .fusionBegin(fusionBegin):
                preRoundTrace.lastInboundKind = .fusionBegin
                preRoundTrace.lastInboundPayloadBytes = payloadBytes
                appendDiagnosticEvent(
                    .init(
                        kind: .inboundMessage,
                        summary: "Received FusionBegin",
                        messageKind: "FusionBegin",
                        payloadByteCount: payloadBytes,
                        handshakeStage: preRoundTrace.handshakeStage
                    )
                )
                Self.logger.debug(
                    "primary preround inbound kind=FusionBegin payloadBytes=\(payloadBytes, privacy: .public) tier=\(fusionBegin.tier, privacy: .public) covertPort=\(Int(fusionBegin.covertPort), privacy: .public) covertTLS=\(Self.describe(fusionBegin.covertSsl), privacy: .public)"
                )
            case let .serverFailure(failure):
                preRoundTrace.lastInboundKind = .serverFailure
                preRoundTrace.lastInboundPayloadBytes = payloadBytes
                appendDiagnosticEvent(
                    .init(
                        kind: .inboundMessage,
                        summary: "Received ServerFailure",
                        messageKind: "ServerFailure",
                        payloadByteCount: payloadBytes,
                        handshakeStage: preRoundTrace.handshakeStage
                    )
                )
                Self.logger.debug(
                    "primary preround inbound kind=ServerFailure payloadBytes=\(payloadBytes, privacy: .public) messagePresent=\(failure.message != nil, privacy: .public)"
                )
            case .startRound, .blindSignatureResponses, .allCommitments, .shareCovertComponents,
                    .fusionResult, .theirProofsList, .restartRound:
                break
            }
        }

        private mutating func logPreRoundOutboundMessage(
            _ message: OpalFusion.ProtocolModel.ClientMessage,
            payloadBytes: Int
        ) {
            switch message {
            case let .clientHello(clientHello):
                preRoundTrace.wroteClientHello = true
                preRoundTrace.handshakeStage = .awaitingServerHello
                appendDiagnosticEvent(
                    .init(
                        kind: .outboundMessage,
                        summary: "Sent ClientHello",
                        messageKind: "ClientHello",
                        payloadByteCount: payloadBytes,
                        handshakeStage: preRoundTrace.handshakeStage
                    )
                )
                Self.logger.debug(
                    "primary preround outbound kind=ClientHello payloadBytes=\(payloadBytes, privacy: .public) versionByteCount=\(clientHello.versionBytes.count, privacy: .public) hasGenesisHash=\(clientHello.genesisHash != nil, privacy: .public)"
                )
            case let .joinPools(joinPools):
                preRoundTrace.wroteJoinPools = true
                preRoundTrace.handshakeStage = .awaitingFusionBegin
                appendDiagnosticEvent(
                    .init(
                        kind: .outboundMessage,
                        summary: "Sent JoinPools",
                        messageKind: "JoinPools",
                        payloadByteCount: payloadBytes,
                        handshakeStage: preRoundTrace.handshakeStage
                    )
                )
                Self.logger.debug(
                    "primary preround outbound kind=JoinPools payloadBytes=\(payloadBytes, privacy: .public) tiersCount=\(joinPools.tiers.count, privacy: .public) firstTier=\(Self.describe(joinPools.tiers.first), privacy: .public) tagCount=\(joinPools.tags.count, privacy: .public)"
                )
            case .playerCommit, .myProofsList, .blames:
                break
            }
        }

        private static func describe<T>(
            _ value: T?
        ) -> String {
            guard let value else {
                return "nil"
            }

            return String(describing: value)
        }

        private mutating func recordLifecycleEvent(
            summary: String,
            handshakeStage: OpalFusion.Client.Diagnostics.HandshakeStage
        ) {
            preRoundTrace.handshakeStage = handshakeStage
            appendDiagnosticEvent(
                .init(
                    kind: .lifecycle,
                    summary: summary,
                    handshakeStage: handshakeStage
                )
            )
        }

        private mutating func recordFailureEvent(
            summary: String
        ) {
            appendDiagnosticEvent(
                .init(
                    kind: .failure,
                    summary: summary,
                    handshakeStage: preRoundTrace.handshakeStage
                )
            )
        }

        private mutating func appendDiagnosticEvent(
            _ event: OpalFusion.Client.Diagnostics.Event
        ) {
            preRoundTrace.recentEvents = OpalFusion.Client.Diagnostics.cappedRecentEvents(
                preRoundTrace.recentEvents + [event]
            )
        }

        private mutating func updateHandshakeStageFromEngine() {
            switch engine.session.connectionSubstate {
            case .awaitingServerHello:
                preRoundTrace.handshakeStage = .awaitingServerHello
            case .awaitingFusionBegin:
                preRoundTrace.handshakeStage = .awaitingFusionBegin
            case .inRound:
                preRoundTrace.handshakeStage = .inRound
            case .disconnected, .failed:
                break
            }
        }
    }
}

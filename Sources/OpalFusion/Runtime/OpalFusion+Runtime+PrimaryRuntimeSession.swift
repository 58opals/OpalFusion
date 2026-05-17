// OpalFusion+Runtime+PrimaryRuntimeSession.swift

import OpalDiagnostics

extension OpalFusion.Runtime {
    struct PrimaryRuntimeSession: Sendable {
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

        var coordinatorStatus: OpalFusion.Client.Session.Snapshot.CoordinatorStatus {
            .init(
                updateSequence: preRoundTrace.updateSequence,
                latestInboundMessageKind: preRoundTrace.lastInboundKind?.rawValue,
                latestInboundPayloadByteCount: preRoundTrace.lastInboundPayloadBytes,
                queueStatus: requestedTierQueueStatus
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
                    OpalDiagnostics.logger(category: .fusionPrimary).record(
                        event: .primaryMessageDecodeFailed,
                        level: .opalFusionDefault(for: .primaryMessageDecodeFailed),
                        fields: [
                            .operation("primary_preround_outbound_decode"),
                            .frameByteCount(bytes.count),
                            .errorCode("protocol_incompatible")
                        ]
                    )
                    return
                }

                let message = try messageDecoder.decodeClient(payloads[0])
                logPreRoundOutboundMessage(
                    message,
                    payloadBytes: payloads[0].count
                )
            } catch {
                OpalDiagnostics.logger(category: .fusionPrimary).record(
                    event: .primaryMessageDecodeFailed,
                    level: .opalFusionDefault(for: .primaryMessageDecodeFailed),
                    fields: [
                        .operation("primary_preround_outbound_decode"),
                        .frameByteCount(bytes.count)
                    ] + OpalDiagnostics.Field.errorFields(for: error)
                )
            }
        }

        mutating func apply(
            input: OpalFusion.Runtime.PrimaryRuntimeSession.Input,
            now: OpalFusion.Execution.Instant
        ) -> [OpalFusion.Runtime.PrimaryRuntimeSession.Effect] {
            switch input {
            case let .invalidConfiguration(summary):
                recordFailureEvent(
                    summary: summary,
                    errorCode: "invalid_configuration"
                )
                return translateEngineInput(.configurationRejected(summary: summary), now: now)
            case .connected:
                recordLifecycleEvent(
                    phase: "awaitingServerHello"
                )
                return translateEngineInput(.primaryConnected, now: now)
            case .disconnected:
                recordFailureEventUnlessRoundIsTerminal(summary: "Primary channel disconnected")
                return translateEngineInput(.primaryDisconnected, now: now)
            case .stopped:
                recordLifecycleEvent(
                    phase: "notStarted"
                )
                return translateEngineInput(.stopped, now: now)
            case let .primaryTransportFailed(summary):
                recordFailureEventUnlessRoundIsTerminal(summary: summary)
                return translateEngineInput(.primaryTransportFailed(summary: summary), now: now)
            case let .diagnosedPrimaryTransportFailed(summary):
                return translateEngineInput(.primaryTransportFailed(summary: summary), now: now)
            case let .receivedPrimaryBytes(bytes):
                return handleReceivedPrimaryBytes(bytes, now: now)
            case .covertPrepared:
                return handleCovertRuntimeEffects(
                    covertSession.apply(input: .covertPrepared, now: now),
                    now: now
                )
            case let .covertPreparationFailed(summary):
                recordFailureEventUnlessRoundIsTerminal(summary: summary)
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
                recordFailureEventUnlessRoundIsTerminal(summary: summary)
                return handleCovertRuntimeEffects(
                    covertSession.apply(
                        input: .covertRequestFailed(summary: summary),
                        now: now
                    ),
                    now: now
                )
            case let .participantReservationLoaded(reservation):
                return translateEngineInput(.participantReservationLoaded(reservation), now: now)
            case .participantReservationRejected:
                return translateEngineInput(.participantReservationRejected, now: now)
            case let .finalizedTransactionLoaded(transaction):
                return translateEngineInput(.finalizedTransactionLoaded(transaction), now: now)
            case let .transactionFinalizationRejected(failure):
                return translateEngineInput(.transactionFinalizationRejected(failure), now: now)
            case .clockAdvanced:
                var runtimeEffects = handleCovertRuntimeEffects(
                    covertSession.apply(input: .clockAdvanced, now: now),
                    now: now
                )
                runtimeEffects.append(contentsOf: translateEngineInput(.clockAdvanced, now: now))
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
                    let effects = translateEngineInput(.primaryMessage(message), now: now)
                    recordAcceptedPreRoundInboundMessage(message)
                    if engine.session.connectionSubstate == .failed {
                        return effects
                    }
                    runtimeEffects.append(
                        contentsOf: effects
                    )
                }

                _ = try frameDecoder.append([])
                return runtimeEffects
            } catch {
                if shouldTracePreRoundTraffic {
                    OpalDiagnostics.logger(category: .fusionPrimary).record(
                        event: .primaryMessageDecodeFailed,
                        level: .opalFusionDefault(for: .primaryMessageDecodeFailed),
                        fields: [
                            .operation("primary_inbound_decode"),
                            .frameByteCount(bytes.count)
                        ] + OpalDiagnostics.Field.errorFields(for: error)
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
                        OpalDiagnostics.logger(category: .fusionPrimary).record(
                            event: .primaryMessageEncodeFailed,
                            level: .opalFusionDefault(for: .primaryMessageEncodeFailed),
                            traceID: .opalFusionRound(engine.round?.identifier),
                            fields: [
                                .operation("primary_message_encode"),
                                .messageKind(for: message)
                            ] + OpalDiagnostics.Field.errorFields(for: error)
                        )
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
                case let .requestParticipantReservation(context):
                    runtimeEffects.append(
                        .requestParticipantReservation(context: context)
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

        private mutating func translateEngineInput(
            _ input: OpalFusion.Execution.RoundEngine.Input,
            now: OpalFusion.Execution.Instant
        ) -> [OpalFusion.Runtime.PrimaryRuntimeSession.Effect] {
            translate(
                engine.apply(input: input, now: now),
                now: now
            )
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
                        contentsOf: translateEngineInput(.covertResponse(response), now: now)
                    )
                case let .emitProtocolFailure(summary):
                    runtimeEffects.append(
                        contentsOf: translateEngineInput(.protocolRejected(summary: summary), now: now)
                    )
                case let .emitTransportFailure(summary):
                    runtimeEffects.append(
                        contentsOf: translateEngineInput(.covertTransportFailed(summary: summary), now: now)
                    )
                }
            }

            return runtimeEffects
        }

        private mutating func protocolFailureEffects(
            summary: String,
            now: OpalFusion.Execution.Instant
        ) -> [OpalFusion.Runtime.PrimaryRuntimeSession.Effect] {
            recordFailureEventUnlessRoundIsTerminal(summary: summary)
            return translateEngineInput(.protocolRejected(summary: summary), now: now)
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

        private var requestedTierQueueStatus: OpalFusion.Client.Session.Snapshot.CoordinatorStatus.TierQueue? {
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

        private mutating func logPreRoundInboundMessage(
            _ message: OpalFusion.ProtocolModel.ServerMessage,
            payloadBytes: Int
        ) {
            guard shouldTracePreRoundTraffic else {
                return
            }

            preRoundTrace.updateSequence += 1
            preRoundTrace.lastInboundKind = .init(message: message)
            preRoundTrace.lastInboundPayloadBytes = payloadBytes

            switch message {
            case .serverHello:
                recordPrimaryMessageReceived(
                    messageKind: "ServerHello",
                    payloadBytes: payloadBytes
                )
            case .tierStatusUpdate:
                recordPrimaryMessageReceived(
                    messageKind: "TierStatusUpdate",
                    payloadBytes: payloadBytes
                )
            case .fusionBegin:
                recordPrimaryMessageReceived(
                    messageKind: "FusionBegin",
                    payloadBytes: payloadBytes
                )
            case let .serverFailure(failure):
                var fields = [
                    OpalDiagnostics.Field.operation("primary_message_receive"),
                    OpalDiagnostics.Field.messageKind("ServerFailure"),
                    OpalDiagnostics.Field.payloadByteCount(payloadBytes)
                ]
                if let message = failure.message {
                    fields.append(OpalDiagnostics.Field.privateField("error_message", message))
                }
                OpalDiagnostics.logger(category: .fusionPrimary).record(
                    event: .primaryMessageReceived,
                    level: .opalFusionDefault(for: .primaryMessageReceived),
                    fields: fields
                )
            case .startRound, .blindSignatureResponses, .allCommitments, .shareCovertComponents,
                    .fusionResult, .theirProofsList, .restartRound:
                break
            }
        }

        private mutating func recordAcceptedPreRoundInboundMessage(
            _ message: OpalFusion.ProtocolModel.ServerMessage
        ) {
            guard case .serverHello = message,
                  engine.session.connectionSubstate == .awaitingFusionBegin else {
                return
            }

            preRoundTrace.sawServerHello = true
        }

        private mutating func logPreRoundOutboundMessage(
            _ message: OpalFusion.ProtocolModel.ClientMessage,
            payloadBytes: Int
        ) {
            switch message {
            case .clientHello:
                preRoundTrace.wroteClientHello = true
                recordPrimaryMessageSent(
                    messageKind: "ClientHello",
                    payloadBytes: payloadBytes
                )
            case .joinPools:
                preRoundTrace.wroteJoinPools = true
                recordPrimaryMessageSent(
                    messageKind: "JoinPools",
                    payloadBytes: payloadBytes
                )
            case .playerCommit, .myProofsList, .blames:
                break
            }
        }

        private func recordLifecycleEvent(
            phase: String
        ) {
            OpalDiagnostics.logger(category: .fusionPrimary).record(
                event: .handshakePhaseChanged,
                level: .opalFusionDefault(for: .handshakePhaseChanged),
                fields: [
                    .operation("handshake"),
                    .phase(phase)
                ]
            )
        }

        private mutating func recordFailureEvent(
            summary: String,
            errorCode: String = "transport_unavailable"
        ) {
            OpalDiagnostics.logger(category: .fusionTransport).record(
                event: .transportError,
                level: .opalFusionDefault(for: .transportError),
                fields: [
                    .operation("primary_runtime")
                ] + OpalDiagnostics.Field.sanitizedSummaryFields(
                    errorCode: errorCode,
                    summary: summary
                )
            )
        }

        private mutating func recordFailureEventUnlessRoundIsTerminal(
            summary: String
        ) {
            guard engine.round?.substate != .terminal else {
                return
            }

            recordFailureEvent(summary: summary)
        }

        private func recordPrimaryMessageReceived(
            messageKind: String,
            payloadBytes: Int
        ) {
            recordPrimaryMessage(
                OpalDiagnostics.Event.primaryMessageReceived,
                operation: "primary_message_receive",
                messageKind: messageKind,
                payloadBytes: payloadBytes
            )
        }

        private func recordPrimaryMessageSent(
            messageKind: String,
            payloadBytes: Int
        ) {
            recordPrimaryMessage(
                OpalDiagnostics.Event.primaryMessageSent,
                operation: "primary_message_send",
                messageKind: messageKind,
                payloadBytes: payloadBytes
            )
        }

        private func recordPrimaryMessage(
            _ event: OpalDiagnostics.Event,
            operation: String,
            messageKind: String,
            payloadBytes: Int
        ) {
            OpalDiagnostics.logger(category: .fusionPrimary).record(
                event: event,
                level: .opalFusionDefault(for: event),
                fields: [
                    .operation(operation),
                    .messageKind(messageKind),
                    .payloadByteCount(payloadBytes)
                ]
            )
        }
    }
}

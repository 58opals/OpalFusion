// OpalFusion+Runtime+PrimaryRuntimeSession+ImplementationGroup1.swift

import OpalDiagnostics

extension OpalFusion.Runtime.PrimaryRuntimeSession {
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
                        .errorCode(OpalDiagnostics.ErrorCode.protocolIncompatible)
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
                errorCode: .invalidConfiguration
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

    mutating func handleReceivedPrimaryBytes(
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
}

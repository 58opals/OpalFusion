// OpalFusion+Runtime+PrimaryRuntimeSession+ImplementationGroup2.swift

import OpalDiagnostics

extension OpalFusion.Runtime.PrimaryRuntimeSession {
    mutating func translate(
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
                if let roundIdentifier = engine.round?.identifier {
                    _ = covertSession.apply(
                        input: .roundIdentifierResolved(roundIdentifier),
                        now: now
                    )
                }
                runtimeEffects.append(
                    contentsOf: handleCovertRuntimeEffects(
                        covertSession.apply(
                            input: .enqueue(message: message),
                            now: now
                        ),
                        now: now
                    )
                )
            case .resetCovertTransport:
                _ = covertSession.apply(input: .reset, now: now)
                runtimeEffects.append(.resetCovertTransport)
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

    mutating func translateEngineInput(
        _ input: OpalFusion.Execution.RoundEngine.Input,
        now: OpalFusion.Execution.Instant
    ) -> [OpalFusion.Runtime.PrimaryRuntimeSession.Effect] {
        translate(
            engine.apply(input: input, now: now),
            now: now
        )
    }

    mutating func handleCovertRuntimeEffects(
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

    mutating func protocolFailureEffects(
        summary: String,
        now: OpalFusion.Execution.Instant
    ) -> [OpalFusion.Runtime.PrimaryRuntimeSession.Effect] {
        recordFailureEventUnlessRoundIsTerminal(summary: summary)
        return translateEngineInput(.protocolRejected(summary: summary), now: now)
    }
}

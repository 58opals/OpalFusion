// OpalFusion+Runtime+CovertRuntimeSession+ImplementationGroup2.swift

import OpalDiagnostics

extension OpalFusion.Runtime.CovertRuntimeSession {
    mutating func maybeDispatchNextRequest(
        now: OpalFusion.Execution.Instant
    ) -> [OpalFusion.Runtime.CovertRuntimeSession.Effect] {
        guard outstandingRequest == nil, substate == .prepared else {
            return []
        }
        guard queuedMessages.isEmpty == false else {
            return []
        }
        guard let endpointContext else {
            return protocolFailure(
                summary: "Covert request was queued before an endpoint was configured"
            )
        }

        let message = queuedMessages.removeFirst()

        do {
            let payload = try messageEncoder.encode(message)
            guard payload.count <= endpointContext.maxPayloadBytes else {
                return protocolFailure(
                    summary: "Covert payload exceeded the configured size limit"
                )
            }

            let submitWindowDeadline = submitWindowDeadline
                ?? now.advanced(by: endpointContext.submitWindow)
            self.submitWindowDeadline = submitWindowDeadline
            guard now <= submitWindowDeadline else {
                return transportFailure(summary: "Covert request timed out")
            }

            let requestDeadline = now.advanced(by: effectiveRequestTimeout(for: endpointContext))
            let deadline = min(requestDeadline, submitWindowDeadline)
            let request = OpalFusion.Runtime.CovertRequest(
                endpoint: endpointContext,
                roundIdentifier: roundIdentifier,
                payload: payload,
                startedAt: now,
                deadline: deadline
            )

            self.outstandingRequest = request
            OpalDiagnostics.logger(category: .fusionCovert).record(
                event: .covertRequestStarted,
                level: .opalFusionDefault(for: .covertRequestStarted),
                traceID: .opalFusionRound(request.roundIdentifier),
                fields: [
                    .operation("covert_request"),
                    .messageKind(for: message),
                    .payloadByteCount(payload.count)
                ]
            )

            return [.performCovertRequest(request: request)]
        } catch {
            OpalDiagnostics.logger(category: .fusionCovert).record(
                event: .covertMessageEncodeFailed,
                level: .opalFusionDefault(for: .covertMessageEncodeFailed),
                traceID: .opalFusionRound(endpointContext.roundIdentifier),
                fields: [
                    .operation("covert_message_encode"),
                    .messageKind(for: message)
                ] + OpalDiagnostics.Field.errorFields(for: error)
            )
            return protocolFailure(summary: "Covert request encode failed")
        }
    }

    mutating func protocolFailure(
        summary: String
    ) -> [OpalFusion.Runtime.CovertRuntimeSession.Effect] {
        reset()
        return [.emitProtocolFailure(summary: summary)]
    }

    mutating func transportFailure(
        summary: String,
        event: OpalDiagnostics.Event = OpalDiagnostics.Event.covertRequestFailed,
        operation: String = "covert_transport"
    ) -> [OpalFusion.Runtime.CovertRuntimeSession.Effect] {
        OpalDiagnostics.logger(category: .fusionCovert).record(
            event: event,
            level: .opalFusionDefault(for: event),
            traceID: .opalFusionRound(
                outstandingRequest.map(roundTraceIdentifier(for:)) ?? currentRoundTraceIdentifier
            ),
            fields: [
                .operation(operation)
            ] + OpalDiagnostics.Field.sanitizedSummaryFields(
                errorCode: .transportUnavailable,
                summary: summary
            )
        )
        reset()
        return [.emitTransportFailure(summary: summary)]
    }

    func roundTraceIdentifier(
        for request: OpalFusion.Runtime.CovertRequest
    ) -> OpalFusion.Round.Identifier? {
        request.roundIdentifier ?? currentRoundTraceIdentifier
    }

    mutating func diagnosedTransportFailure(
        summary: String
    ) -> [OpalFusion.Runtime.CovertRuntimeSession.Effect] {
        reset()
        return [.emitTransportFailure(summary: summary)]
    }

    mutating func reset() {
        endpointContext = nil
        substate = .idle
        preparationPlan = nil
        queuedMessages = []
        outstandingRequest = nil
        roundIdentifier = nil
        submitWindowDeadline = nil
    }

    func effectiveRequestTimeout(
        for endpointContext: OpalFusion.Runtime.CovertEndpointContext
    ) -> Duration {
        let requestTimeoutMilliseconds = min(
            endpointContext.requestTimeoutMilliseconds,
            UInt64(Int64.max)
        )
        let configuredTimeout = Duration.milliseconds(
            Int64(requestTimeoutMilliseconds)
        )
        return min(
            configuredTimeout,
            endpointContext.submitTimeout
        )
    }

    func effectiveConnectTimeout(
        for endpointContext: OpalFusion.Runtime.CovertEndpointContext
    ) -> Duration {
        min(
            endpointContext.connectTimeout,
            endpointContext.connectWindow
        )
    }

    func recordCovertPrepare(
        _ event: OpalDiagnostics.Event,
        roundIdentifier: OpalFusion.Round.Identifier?
    ) {
        OpalDiagnostics.logger(category: .fusionCovert).record(
            event: event,
            level: .opalFusionDefault(for: event),
            traceID: .opalFusionRound(roundIdentifier),
            fields: [
                .operation("covert_prepare")
            ]
        )
    }
}
